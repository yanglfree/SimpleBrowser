import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const specPath = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  '../spec/phone-v1.json'
);

test('Phone V1 matrix covers browsing chrome and defers Harmony-only surfaces', async () => {
  const matrix = JSON.parse(await readFile(specPath, 'utf8'));
  const phone = new Set(matrix.phoneV1);
  const deferred = new Set(matrix.deferred);
  const harmonyOnly = new Set(matrix.harmonyOnly);

  for (const required of [
    'tabs',
    'privateTabs',
    'omniBar',
    'blocking',
    'reader',
    'downloads',
    'bookmarks',
    'history',
    'settings',
    'startPage'
  ]) {
    assert.ok(phone.has(required), required);
  }

  for (const later of [
    'splitPanes',
    'multiWindow',
    'foldCrease',
    'desktopTabStrip',
    'defaultBrowser',
    'iap'
  ]) {
    assert.ok(deferred.has(later), later);
    assert.equal(phone.has(later), false, later);
  }

  for (const local of ['adsBlockManager', 'specifiedWindows', 'agcIap', 'hapSigning']) {
    assert.ok(harmonyOnly.has(local), local);
  }

  const overlap = [...phone].filter((item) => deferred.has(item) || harmonyOnly.has(item));
  assert.deepEqual(overlap, []);
});
