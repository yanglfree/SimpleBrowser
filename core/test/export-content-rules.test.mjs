import test from 'node:test';
import assert from 'node:assert/strict';
import { checkExportedRules, writeExportedRules } from '../src/export-content-rules.mjs';
import { compileContentRules } from '../src/content-rules.mjs';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');

test('exported content rules include the MSN supplement and stay within WK limits', async () => {
  await writeExportedRules();
  const manifest = JSON.parse(
    await readFile(path.join(root, 'core/rules/manifest.json'), 'utf8')
  );
  const supplement = JSON.parse(
    await readFile(path.join(root, 'core/rules/supplement.json'), 'utf8')
  );
  assert.equal(manifest.lists.length, 3);
  assert.ok(supplement.some((rule) => rule.action.type === 'block'));
  assert.ok(supplement.some((rule) => rule.action.type === 'css-display-none'));
  for (const list of manifest.lists) {
    assert.ok(list.count <= 50000, list.id);
    assert.equal(typeof list.sha256, 'string');
    assert.equal(list.sha256.length, 64);
  }
  const china = JSON.parse(await readFile(path.join(root, 'core/rules/easylistchina.json'), 'utf8'));
  assert.ok(china.length > 1000);
  const drift = await checkExportedRules();
  assert.deepEqual(drift, []);
});

test('easylist export prefers network blocks and never exceeds 50000 rules', async () => {
  const source = await readFile(
    path.join(root, 'ohos/entry/src/main/resources/rawfile/ads/easylist.txt'),
    'utf8'
  );
  const compiled = compileContentRules(source, { maxRules: 50000 });
  assert.equal(compiled.rules.length, 50000);
  assert.equal(compiled.truncated, true);
  assert.equal(compiled.rules[0].action.type, 'block');
});
