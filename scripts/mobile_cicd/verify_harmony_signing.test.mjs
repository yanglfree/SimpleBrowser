import assert from 'node:assert/strict';
import test from 'node:test';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, symlinkSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { validateProfile } from './verify_harmony_signing.mjs';

function profile() {
  return {
    type: 'release',
    'app-distribution-type': 'internaltesting',
    'bundle-info': { 'bundle-name': 'com.youdroid.zhuobrowser', 'app-identifier': '6917614109541548410' },
    validity: { 'not-before': 10, 'not-after': 100 },
    'app-services-capabilities': { 'com.huawei.service.iap': {} },
    'debug-info': { 'device-ids': ['test-device'] },
  };
}

test('CLI runs through a symlink and fails closed for missing input', () => {
  const directory = mkdtempSync(join(tmpdir(), 'signing-cli-test-'));
  try {
    const link = join(directory, 'verify.mjs');
    symlinkSync(fileURLToPath(new URL('./verify_harmony_signing.mjs', import.meta.url)), link);
    const result = spawnSync(process.execPath, [link], { encoding: 'utf8' });
    assert.equal(result.status, 1);
    assert.match(result.stderr, /Signing validation failed/);
  } finally {
    rmSync(directory, { recursive: true });
  }
});

test('accepts the IAP-enabled specified-device profile', () => {
  assert.doesNotThrow(() => validateProfile(profile(), 'internaltesting', 50));
});

for (const [name, change] of [
  ['missing IAP', p => delete p['app-services-capabilities']],
  ['wrong bundle', p => p['bundle-info']['bundle-name'] = 'another.app'],
  ['wrong app identifier', p => p['bundle-info']['app-identifier'] = 'other'],
  ['wrong profile type', p => p.type = 'debug'],
  ['store profile on device channel', p => p['app-distribution-type'] = 'app_gallery'],
  ['expired profile', p => p.validity['not-after'] = 50],
  ['future profile', p => p.validity['not-before'] = 51],
  ['missing devices', p => delete p['debug-info']],
]) {
  test(`rejects ${name}`, () => {
    const candidate = profile();
    change(candidate);
    assert.throws(() => validateProfile(candidate, 'internaltesting', 50));
  });
}

test('accepts store and debug profiles only on their own channels', () => {
  const store = profile();
  store['app-distribution-type'] = 'app_gallery';
  delete store['debug-info'];
  assert.doesNotThrow(() => validateProfile(store, 'app_gallery', 50));
  store.type = 'debug';
  delete store['app-distribution-type'];
  assert.doesNotThrow(() => validateProfile(store, 'debug', 50));
  assert.throws(() => validateProfile(store, 'app_gallery', 50));
});
