import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync, copyFileSync, mkdirSync, mkdtempSync, rmSync, symlinkSync } from 'node:fs';
import { tmpdir, homedir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { root, readSource, snapshot, fingerprint } from './signing-source.mjs';

const files = ['install.hap', 'icon.png', 'manifest.json5', 'release-metadata.json'];
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const save = (path, data) => writeFileSync(path, JSON.stringify(data, null, 2) + '\n', { mode: 0o600 });
const source = readSource();
const portalBase = source.portalBase;
assert.ok(portalBase?.startsWith('https://'), 'Canonical portal base must use HTTPS');
const origin = new URL(portalBase).origin;
const token = process.env.PORTAL_UPLOAD_TOKEN;
const ciRunId = Number(process.env.ACCEPTED_CI_RUN_ID);
const sourceSha = process.env.SOURCE_SHA ?? execFileSync('git', ['rev-parse', 'HEAD'], { cwd: root, encoding: 'utf8' }).trim();
assert.match(sourceSha, /^[a-f0-9]{40}$/);

async function api(path, method = 'GET', body, headers = {}) {
  assert.ok(token?.length >= 32, 'Product-scoped portal token is required');
  const response = await fetch(`${origin}/api/v1/harmony/${path}`, {
    method, redirect: 'error', signal: AbortSignal.timeout(120000),
    headers: { authorization: `Bearer ${token}`, ...(body ? { 'content-type': 'application/json' } : {}), ...headers },
    body: body instanceof Buffer ? body : body ? JSON.stringify(body) : undefined,
  });
  assert.ok(response.ok, `Portal request failed (${response.status})`);
  return response.json();
}

async function verifyResource(url, bytes) {
  const response = await fetch(url, { redirect: 'error', signal: AbortSignal.timeout(120000) });
  assert.equal(response.status, 200, 'Artifact GET failed');
  assert.equal(hash(Buffer.from(await response.arrayBuffer())), hash(bytes), 'Live artifact checksum mismatch');
  const head = await fetch(url, { method: 'HEAD', redirect: 'error', signal: AbortSignal.timeout(30000) });
  assert.equal(head.status, 200, 'Artifact HEAD failed');
  assert.equal(Number(head.headers.get('content-length')), bytes.length, 'Artifact length mismatch');
  const range = await fetch(url, { headers: { range: 'bytes=0-0' }, redirect: 'error', signal: AbortSignal.timeout(30000) });
  assert.equal(range.status, 206, 'Artifact Range failed');
  assert.equal(range.headers.get('content-range'), `bytes 0-0/${bytes.length}`, 'Artifact Range length mismatch');
  assert.deepEqual(Buffer.from(await range.arrayBuffer()), bytes.subarray(0, 1), 'Artifact Range bytes mismatch');
}

function signManifest(configPath, unsignedPath, outputPath) {
  const toolsHome = process.env.DEVECO_HOME ?? join(homedir(), 'Library/Huawei/CommandLineTools/current');
  const moduleRoot = join(dirname(configPath), 'node_modules');
  mkdirSync(join(moduleRoot, '@ohos'), { recursive: true });
  symlinkSync(join(toolsHome, 'hvigor/hvigor'), join(moduleRoot, '@ohos/hvigor'));
  const result = spawnSync(process.execPath, [join(root, 'scripts/mobile_cicd/sign-manifest.cjs'),
    configPath, unsignedPath, outputPath, source.manifestSignTool, toolsHome], {
    env: { ...process.env, NODE_PATH: moduleRoot }, stdio: 'inherit',
  });
  assert.equal(result.status, 0, 'Manifest signing or verification failed');
}

async function main() {
  const command = process.argv[2] ?? 'publish';
  const directory = resolve(process.argv[3] ?? join(root, 'output/device-release'));
  mkdirSync(directory, { recursive: true, mode: 0o700 });
  const temporary = mkdtempSync(join(tmpdir(), 'zhuobrowser-device-signing-'));
  try {
    const inputDigest = fingerprint('internaltesting');
    const signing = snapshot('internaltesting', join(temporary, 'snapshot'));
    const app = JSON.parse(readFileSync(join(root, 'AppScope/app.json5'), 'utf8')).app;
    const inputs = { sourceSha, inputDigest, profileSha256: signing.profileSha256,
      certificateSha256: signing.certificateSha256.replaceAll(':', '').toLowerCase(),
      profileUuid: signing.profileUuid, profileExpiresAt: signing.profileExpiresAt,
      ciRunId, bundleName: app.bundleName, version: app.versionName, minimumBuild: app.versionCode };
    assert.ok(command === 'build-only' || command === 'publish', 'Unknown device release command');
    if (command === 'publish') {
      assert.ok(Number.isSafeInteger(ciRunId) && ciRunId > 0, 'Accepted CI identity is required');
      const actual = execFileSync('git', ['rev-parse', 'HEAD'], { cwd: root, encoding: 'utf8' }).trim();
      assert.equal(actual, sourceSha, 'Checkout does not match accepted source');
      execFileSync('git', ['diff', '--quiet', 'HEAD', '--', ':!iap_paywall_kit/BuildProfile.ets'], { cwd: root });
    }
    const allocated = command === 'publish' ? await api('releases', 'POST', inputs) : {
      id: hash(`${sourceSha}\n${inputDigest}\noffline-verification`), build: String(app.versionCode + 1), status: 'uploaded',
    };
    if (command === 'publish' && allocated.status === 'published') {
      assert.equal((await api('current'))?.id, allocated.id, 'Previously published release is no longer current; refusing implicit rollback');
      const recorded = await api(`releases/${allocated.id}`);
      assert.equal(recorded.artifacts.length, files.length, 'Published artifact set is incomplete');
      for (const name of files) {
        const artifact = recorded.artifacts.find(item => item.name === name);
        assert.ok(artifact, 'Published artifact is missing');
        const url = `${portalBase}/builds/${allocated.id}/${name}`;
        const live = await fetch(url, { redirect: 'error', signal: AbortSignal.timeout(120000) });
        assert.equal(live.status, 200);
        const bytes = Buffer.from(await live.arrayBuffer());
        assert.equal(hash(bytes), artifact.sha256, 'Published artifact checksum changed');
        await verifyResource(url, bytes);
        if (name === 'manifest.json5') await verifyResource(`${portalBase}/install-manifest.json5`, bytes);
      }
      console.log(`DEVICE_RELEASE_ALREADY_CURRENT release=${allocated.id}`);
      return;
    }
    const buildOutput = join(temporary, 'build');
    const build = spawnSync('bash', [join(root, 'scripts/mobile_cicd/build_harmony_artifacts.sh'), buildOutput], {
      cwd: root, stdio: 'inherit', env: { ...process.env, HARMONY_CHANNEL: 'internaltesting',
        HARMONY_BUILD_NUMBER: allocated.build, SOURCE_SHA: sourceSha },
    });
    assert.equal(build.status, 0, 'Device HAP build failed');
    const built = JSON.parse(readFileSync(join(buildOutput, 'release-metadata.json'), 'utf8'));
    assert.equal(built.inputDigest, inputDigest, 'Build used different signing inputs');
    assert.equal(built.signing.profileSha256, signing.profileSha256);
    assert.equal(built.versionCode, Number(allocated.build));
    copyFileSync(join(buildOutput, built.artifact), join(directory, 'install.hap'));
    copyFileSync(join(root, 'config/harmony-install-icon.png'), join(directory, 'icon.png'));
    const hapHash = hash(readFileSync(join(directory, 'install.hap')));
    const config = JSON.parse(readFileSync(signing.path, 'utf8'));
    const pack = JSON.parse(execFileSync('unzip', ['-p', join(directory, 'install.hap'), 'pack.info'], { encoding: 'utf8' }));
    assert.equal(pack.summary.modules.length, 1, 'Device release currently supports a single entry module');
    const product = config.app.products[0];
    const assetBase = `${portalBase}/builds/${allocated.id}`;
    const manifest = { app: {
      bundleName: app.bundleName, bundleType: 'app', versionCode: built.versionCode, versionName: built.versionName,
      label: '卓阅浏览器', deployDomain: new URL(portalBase).hostname,
      icons: { normal: `${assetBase}/icon.png`, large: `${assetBase}/icon.png` },
      minAPIVersion: product.compatibleSdkVersion, targetAPIVersion: product.targetSdkVersion,
      modules: [{ name: pack.summary.modules[0].distro.moduleName, type: 'entry',
        deviceTypes: pack.summary.modules[0].deviceType, packageUrl: `${assetBase}/install.hap`, packageHash: hapHash }],
    }, sign: '' };
    const unsignedPath = join(temporary, 'unsigned.json5');
    save(unsignedPath, manifest);
    signManifest(signing.path, unsignedPath, join(directory, 'manifest.json5'));
    const metadata = { ...inputs, releaseId: allocated.id, versionCode: built.versionCode,
      iapEnabled: true, distribution: 'internaltesting', hapSha256: hapHash };
    save(join(directory, 'release-metadata.json'), metadata);
    assert.equal(fingerprint('internaltesting'), inputDigest, 'Profile changed before publication');
    if (command === 'build-only') {
      console.log(`DEVICE_RELEASE_BUILT_ONLY output=${directory}`);
      return;
    }
    const hashes = {};
    for (const name of files) {
      const bytes = readFileSync(join(directory, name));
      hashes[name] = hash(bytes);
      await api(`releases/${allocated.id}/artifacts/${name}`, 'PUT', bytes,
        { 'content-length': String(bytes.length), 'x-artifact-sha256': hashes[name] });
      await verifyResource(`${assetBase}/${name}`, bytes);
    }
    assert.equal(fingerprint('internaltesting'), inputDigest, 'Profile changed during upload');
    const current = await api('current');
    await api(`releases/${allocated.id}/publish`, 'POST', {
      expectedCurrent: current?.id ?? null, reason: `Accepted CI ${ciRunId}`, verified: true, hashes,
    });
    await verifyResource(`${portalBase}/install-manifest.json5`, readFileSync(join(directory, 'manifest.json5')));
    assert.equal((await api('current'))?.id, allocated.id, 'Published pointer mismatch');
    console.log(`DEVICE_RELEASE_PUBLISHED release=${allocated.id} build=${allocated.build} profile=${signing.profileSha256}`);
  } finally {
    rmSync(temporary, { recursive: true, force: true });
  }
}
main().catch(error => { console.error(`Device release failed: ${error.code === 'ERR_ASSERTION' ? error.message.split('\n')[0] : error.code ?? error.name}`); process.exitCode = 1; });
