import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync, mkdirSync, copyFileSync, chmodSync, statSync, realpathSync, renameSync, rmSync } from 'node:fs';
import { homedir, tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { mkdtempSync } from 'node:fs';
import { verifySigning } from './verify_harmony_signing.mjs';

export const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
export const sourcePath = process.env.HARMONY_SIGNING_SOURCE ?? join(homedir(), '.config/zhuobrowser/signing.json');
const channels = { debug: 'default', app_gallery: 'dis', internaltesting: 'device' };
export function readSource() {
  assert.equal(statSync(sourcePath).mode & 0o777, 0o600, 'Signing source must have mode 600');
  const source = JSON.parse(readFileSync(sourcePath, 'utf8'));
  assert.equal(source.schemaVersion, 1, 'Unsupported signing source schema');
  return source;
}
export function makeConfig(source, channel) {
  assert.ok(Object.hasOwn(channels, channel), 'Unknown signing channel');
  const config = JSON.parse(readFileSync(join(root, 'config/harmony-build-profile.json'), 'utf8'));
  const matches = source.signingConfigs.filter(item => item.name === channels[channel]);
  assert.equal(matches.length, 1, 'Signing channel must have exactly one source');
  const signer = matches[0];
  assert.ok(signer, 'Canonical signing selection is missing');
  config.app.signingConfigs = [structuredClone(signer)];
  config.app.products[0].signingConfig = signer.name;
  return config;
}
function save(path, data) {
  writeFileSync(path, `${JSON.stringify(data, null, 2)}\n`, { mode: 0o600 });
  chmodSync(path, 0o600);
}
export function snapshot(channel, directory) {
  const config = makeConfig(readSource(), channel);
  mkdirSync(directory, { recursive: true, mode: 0o700 });
  const material = config.app.signingConfigs[0].material;
  for (const field of ['profile', 'certpath']) {
    const target = join(directory, field === 'profile' ? 'profile.p7b' : 'certificate.cer');
    copyFileSync(material[field], target);
    chmodSync(target, 0o600);
    material[field] = target;
  }
  // The keystore stays at its canonical path: the SDK locates password material beside it.
  const path = join(directory, 'build-profile.json5');
  save(path, config);
  return { path, ...verifySigning(path, channel) };
}
export function fingerprint(channel) {
  const source = readSource();
  const signer = makeConfig(source, channel).app.signingConfigs[0];
  const profileSha256 = createHash('sha256').update(readFileSync(signer.material.profile)).digest('hex');
  const certificateFileSha256 = createHash('sha256').update(readFileSync(signer.material.certpath)).digest('hex');
  return createHash('sha256').update(JSON.stringify({ channel, profileSha256, certificateFileSha256 })).digest('hex');
}
export async function changed(sourceSha) {
  const validation = mkdtempSync(join(tmpdir(), 'zhuobrowser-profile-check-'));
  try { snapshot('internaltesting', validation); } finally { rmSync(validation, { recursive: true, force: true }); }
  const source = readSource();
  assert.ok(source.portalBase?.startsWith('https://'), 'Portal base URL is missing');
  const response = await fetch(`${source.portalBase}/release.json`, { redirect: 'error', signal: AbortSignal.timeout(30000) });
  assert.ok(response.ok, 'Cannot inspect current portal release');
  const current = await response.json();
  if (current?.automation_paused) return false;
  return current?.source_sha !== sourceSha || current?.input_digest !== fingerprint('internaltesting');
}
export function assertSelected() {
  const actual = JSON.parse(readFileSync(join(root, 'build-profile.json5'), 'utf8'));
  const selected = actual.app.products.find(p => p.name === 'default')?.signingConfig;
  const channel = Object.keys(channels).find(key => channels[key] === selected);
  assert.ok(channel, 'Selected signing channel is not canonical');
  const expected = makeConfig(readSource(), channel).app.signingConfigs[0].material;
  const material = actual.app.signingConfigs.find(s => s.name === selected)?.material;
  assert.ok(material, 'Selected signing material is missing');
  for (const key of Object.keys(expected)) {
    if (key === 'profile' || key === 'certpath') {
      assert.ok(readFileSync(expected[key]).equals(readFileSync(material[key])), 'Generated signing inputs drifted; run sync-local');
    } else {
      assert.ok(expected[key] === material[key], 'Generated signing identity drifted; run sync-local');
    }
  }
  verifySigning(join(root, 'build-profile.json5'), channel);
}
async function main() {
  const [command, channel = 'debug', destination] = process.argv.slice(2);
  if (command === 'assert-selected') {
    assertSelected();
  } else if (command === 'snapshot') {
    assert.ok(destination, 'Snapshot directory is required');
    console.log(JSON.stringify(snapshot(channel, resolve(destination))));
  } else if (command === 'sync-local') {
    const config = makeConfig(readSource(), channel);
    const target = join(root, 'build-profile.json5');
    save(target, config);
    console.log(JSON.stringify(verifySigning(target, channel)));
  } else if (command === 'fingerprint') {
    console.log(fingerprint(channel));
  } else if (command === 'changed') {
    const sha = execFileSync('git', ['rev-parse', 'HEAD'], { cwd: root, encoding: 'utf8' }).trim();
    console.log(await changed(sha) ? 'true' : 'false');
  } else if (command === 'replace-profile') {
    assert.ok(destination, 'Replacement profile path is required');
    const config = makeConfig(readSource(), channel);
    const material = config.app.signingConfigs[0].material;
    const target = material.profile;
    // Validate the candidate against the canonical identity before atomic promotion.
    const temporary = `${target}.candidate-${process.pid}`;
    const configPath = `${target}.check-${process.pid}.json`;
    try {
      copyFileSync(resolve(destination), temporary);
      chmodSync(temporary, 0o600);
      material.profile = temporary;
      save(configPath, config);
      verifySigning(configPath, channel);
      renameSync(temporary, target);
    } finally {
      rmSync(temporary, { force: true });
      rmSync(configPath, { force: true });
    }
    // A failed dispatch is visible; the scheduled device fingerprint gate provides recovery.
    execFileSync('gh', ['workflow', 'run', 'ci.yml', '--repo', 'yanglfree/SimpleBrowser', '--ref', 'main'], { stdio: 'inherit' });
    console.log('Profile updated; CI requested. Publication is not yet verified.');
  } else {
    throw new Error('Use snapshot, sync-local, assert-selected, fingerprint, changed, or replace-profile');
  }
}
if (process.argv[1] && import.meta.url === pathToFileURL(realpathSync(process.argv[1])).href) {
  main().catch(error => {
    const reason = error.code === 'ERR_ASSERTION' ? error.message.split('\n')[0] : error.code ?? error.name;
    console.error(`Signing source operation failed: ${reason}`);
    process.exitCode = 1;
  });
}
