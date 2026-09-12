import test from 'node:test';
import assert from 'node:assert/strict';
import { HOME_URL, SearchEngine } from '../src/constants.mjs';
import {
  displayHost,
  isHomeUrl,
  looksLikeUrl,
  normalizeAddress,
  normalizeUrlInput,
  rawHost
} from '../src/url-policy.mjs';

test('looksLikeUrl matches the Harmony address-bar contract', () => {
  assert.equal(looksLikeUrl('localhost:8787'), true);
  assert.equal(looksLikeUrl('192.168.1.20:3000/path'), true);
  assert.equal(looksLikeUrl('[::1]:8080'), true);
  assert.equal(looksLikeUrl('例子.中国'), true);
  assert.equal(looksLikeUrl('999.168.1.20'), false);
  assert.equal(looksLikeUrl('privacy browser'), false);
});

test('normalizeAddress sends search phrases to Bing by default', () => {
  assert.equal(
    normalizeAddress('privacy browser', SearchEngine.Bing),
    'https://www.bing.com/search?q=privacy%20browser'
  );
  assert.equal(normalizeAddress('', SearchEngine.Bing), HOME_URL);
  assert.equal(normalizeUrlInput('sspai.com'), 'https://sspai.com');
});

test('home and host helpers ignore the native start page', () => {
  assert.equal(isHomeUrl(HOME_URL), true);
  assert.equal(isHomeUrl(''), true);
  assert.equal(isHomeUrl('https://example.com'), false);
  assert.equal(displayHost(HOME_URL), '');
  assert.equal(displayHost('https://www.zhihu.com/question/1'), 'zhihu.com');
  assert.equal(rawHost('https://www.zhihu.com/question/1'), 'www.zhihu.com');
});
