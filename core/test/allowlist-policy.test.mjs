import test from 'node:test';
import assert from 'node:assert/strict';
import { adsBlockEnabledForUrl, isHostAllowed, setHostAllowed } from '../src/allowlist-policy.mjs';
import { rawHost } from '../src/url-policy.mjs';

test('allow-list is exact raw host, so 127.0.0.1 does not cover localhost', () => {
  const host = rawHost('http://127.0.0.1:4188/fixture');
  const hosts = setHostAllowed([], host, true);
  assert.equal(host, '127.0.0.1');
  assert.equal(isHostAllowed(hosts, host), true);
  assert.equal(adsBlockEnabledForUrl('http://127.0.0.1:4188/next', hosts, true), false);
  assert.equal(adsBlockEnabledForUrl('http://localhost:4188/fixture', hosts, true), true);
});

test('removing a host restores blocking', () => {
  const host = rawHost('https://www.zhihu.com/question/1');
  const allowed = setHostAllowed([], host, true);
  const restored = setHostAllowed(allowed, host, false);
  assert.equal(adsBlockEnabledForUrl('https://www.zhihu.com/', allowed, true), false);
  assert.equal(adsBlockEnabledForUrl('https://www.zhihu.com/', restored, true), true);
  assert.equal(adsBlockEnabledForUrl('https://www.zhihu.com/', restored, false), false);
});

test('home URLs never enable blocking', () => {
  assert.equal(adsBlockEnabledForUrl('browser://home', [], true), false);
});
