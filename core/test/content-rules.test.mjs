import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { compileContentRules, parseFilterList } from '../src/content-rules.mjs';

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const supplementPath = path.join(
  repositoryRoot,
  'entry/src/main/resources/rawfile/ads/dolphin-supplement.txt'
);

test('parses dolphin-supplement network and cosmetic rules', async () => {
  const text = await readFile(supplementPath, 'utf8');
  const parsed = parseFilterList(text);
  assert.equal(parsed.network.length, 1);
  assert.equal(parsed.network[0].host, 'assets.msn.com');
  assert.ok(parsed.network[0].path.includes('thirdparty/adsdk'));
  assert.ok(parsed.cosmetic.length >= 4);
  assert.ok(parsed.cosmetic.some((rule) => rule.selector === 'csm-native-ad-card'));
});

test('compiles Safari content blockers for host and hide rules', () => {
  const compiled = compileContentRules([
    '||ads.example.com^',
    'news.example.com##.ad-slot',
    '@@||ads.example.com^',
    '/too-regex/'
  ].join('\n'));
  assert.equal(compiled.rules.length, 2);
  assert.equal(compiled.rules[0].action.type, 'block');
  assert.match(compiled.rules[0].trigger['url-filter'], /ads\\.example\\.com/);
  assert.equal(compiled.rules[1].action.type, 'css-display-none');
  assert.equal(compiled.rules[1].action.selector, '.ad-slot');
  assert.deepEqual(compiled.rules[1].trigger['if-domain'], ['*news.example.com']);
  assert.equal(compiled.parsed.skipped.length, 2);
});

test('compiled supplement JSON is valid WKContentRuleList input', async () => {
  const text = await readFile(supplementPath, 'utf8');
  const compiled = compileContentRules(text);
  JSON.parse(JSON.stringify(compiled.rules));
  assert.ok(compiled.rules.length >= 5);
  assert.equal(compiled.truncated, false);
});
