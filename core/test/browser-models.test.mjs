import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');

function settingsFields(source, marker) {
  const start = source.indexOf(marker);
  assert.notEqual(start, -1, marker);
  const open = source.indexOf('{', start);
  const close = source.indexOf('\n}', open);
  const body = source.slice(open + 1, close);
  return body
    .split('\n')
    .map((line) => line.trim())
    .filter((line) => line.length > 0 && !line.startsWith('/') && !line.startsWith('*'))
    .map((line) => line.split(':')[0].trim())
    .filter(Boolean);
}

test('BrowserSettings keys stay aligned between Harmony and the TypeScript spec', async () => {
  const harmony = await readFile(path.join(root, 'entry/src/main/ets/models/BrowserModels.ets'), 'utf8');
  const spec = await readFile(path.join(root, 'core/spec/browser-models.ts'), 'utf8');
  const harmonyFields = settingsFields(harmony, 'export interface BrowserSettings {');
  const specFields = settingsFields(spec, 'export interface BrowserSettings {');
  assert.deepEqual(specFields, harmonyFields);
});
