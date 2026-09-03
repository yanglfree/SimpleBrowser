import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { createHash, X509Certificate } from 'node:crypto';
import { readFileSync, realpathSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

export function validateProfile(profile, distribution, now = Date.now() / 1000) {
  assert.ok(['debug', 'app_gallery', 'internaltesting'].includes(distribution), 'Unknown signing channel');
  const bundle = profile['bundle-info'];
  assert.equal(bundle?.['bundle-name'], 'com.youdroid.zhuobrowser', 'Wrong profile bundle');
  assert.equal(bundle?.['app-identifier'], '6917614109541548410', 'Wrong profile app identifier');
  assert.equal(profile.type, distribution === 'debug' ? 'debug' : 'release', 'Wrong profile type');
  if (distribution !== 'debug') {
    assert.equal(profile['app-distribution-type'], distribution, 'Wrong distribution channel');
  }
  assert.ok(profile.validity?.['not-before'] <= now && now < profile.validity?.['not-after'], 'Profile is not currently valid');
  assert.ok(Object.hasOwn(profile['app-services-capabilities'] ?? {}, 'com.huawei.service.iap'), 'Profile is missing IAP capability');
  if (distribution === 'internaltesting') {
    assert.ok(profile['debug-info']?.['device-ids']?.length > 0, 'Device profile has no registered devices');
  }
}

function readProfile(path) {
  // CMS content integrity is checked here; final HAP verification is separate.
  const raw = execFileSync('openssl', ['cms', '-verify', '-inform', 'DER', '-in', path, '-noverify'],
    { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
  return JSON.parse(raw);
}

const sha256 = path => createHash('sha256').update(readFileSync(path)).digest('hex');

export function verifySigning(configPath, distribution, embeddedProfilePath, hapChainPath) {
  // Runner configuration is deliberately JSON-compatible JSON5, without executable parsing.
  const config = JSON.parse(readFileSync(configPath, 'utf8'));
  const product = config.app.products.find(item => item.name === 'default');
  const signer = config.app.signingConfigs.find(item => item.name === product?.signingConfig);
  assert.ok(signer?.material, 'Selected signing configuration is missing');
  const material = signer.material;
  const profile = readProfile(material.profile);
  validateProfile(profile, distribution);
  const bundle = profile['bundle-info'];
  const certificate = new X509Certificate(bundle['distribution-certificate'] ?? bundle['development-certificate']);
  const chain = readFileSync(material.certpath, 'utf8').match(/-----BEGIN CERTIFICATE-----[\s\S]+?-----END CERTIFICATE-----/g) ?? [];
  assert.ok(chain.some(pem => new X509Certificate(pem).fingerprint256 === certificate.fingerprint256), 'Signing certificate does not match profile');
  const now = Date.now();
  assert.ok(Date.parse(certificate.validFrom) <= now && now < Date.parse(certificate.validTo), 'Signing certificate is not currently valid');
  if (embeddedProfilePath) {
    assert.equal(sha256(embeddedProfilePath), sha256(material.profile), 'Built HAP does not contain the selected profile');
    assert.ok(hapChainPath, 'Verified HAP certificate chain is required');
    const hapChain = readFileSync(hapChainPath, 'utf8').match(/-----BEGIN CERTIFICATE-----[\s\S]+?-----END CERTIFICATE-----/g) ?? [];
    assert.ok(hapChain.some(pem => new X509Certificate(pem).fingerprint256 === certificate.fingerprint256), 'Actual HAP signing certificate does not match profile');
  }
  return {
    signingConfig: signer.name,
    profileUuid: profile.uuid,
    profileSha256: sha256(material.profile),
    distribution,
    certificateSha256: certificate.fingerprint256,
    iapEnabled: true,
  };
}

if (process.argv[1] && import.meta.url === pathToFileURL(realpathSync(process.argv[1])).href) {
  try {
    const [configPath, distribution, embeddedProfilePath, hapChainPath] = process.argv.slice(2);
    console.log(JSON.stringify(verifySigning(configPath, distribution, embeddedProfilePath, hapChainPath)));
  } catch (error) {
    // Never dump the config, CMS payload, or subprocess output containing signing data.
    const reason = error.code === 'ERR_ASSERTION' ? error.message.split('\n')[0] : (error.code ?? error.name);
    console.error(`Signing validation failed: ${reason}`);
    process.exitCode = 1;
  }
}
