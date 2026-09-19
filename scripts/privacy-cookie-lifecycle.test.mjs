import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { runInNewContext } from 'node:vm';

function fixture(deviceType = 'phone') {
  const calls = [];
  const policy = readFileSync(new URL('../ohos/entry/src/main/ets/services/CookiePersistence.ets', import.meta.url), 'utf8')
    .replace(/^export /gm, '');
  const source = readFileSync(new URL('../ohos/entry/src/main/ets/services/PrivacyService.ets', import.meta.url), 'utf8')
    .replace(/^import[\s\S]*?from ['"][^'"]+['"];\n/gm, '').replace('export class', 'class');
  const service = runInNewContext(stripTypeScriptTypes(`${policy}\n${source}\nPrivacyService;`), {
    Logger: { warn: () => calls.push('warning') },
    deviceInfo: { deviceType },
    webview: {
      WebviewController: { setWebDebuggingAccess: () => {} },
      WebCookieManager: {
        putAcceptCookieEnabled: () => {},
        putAcceptThirdPartyCookieEnabled: () => {},
        saveCookieSync: () => calls.push('save'),
        fetchCookieSync: (url) => {
          calls.push(`fetch:${url}`);
          return 'session=abc; hwssot=token; state=old_nonce; urlBeforeLogin=/home';
        },
        configCookieSync: (url, value, incognito, httpOnly) => {
          calls.push(`config:${url}:${value}:${incognito}:${httpOnly}`);
        },
        clearAllCookiesSync: (privateMode = false) => calls.push(`clear:${privateMode}`)
      },
      WebStorage: { deleteAllData: (privateMode = false) => calls.push(`storage:${privateMode}`) }
    }
  });
  return { service, calls };
}

test('cold homepage close and background flush never access native cookies', () => {
  const { service, calls } = fixture();
  service.flushCookies();
  service.clearCookiesWhenReady();
  service.clearPrivateSiteDataWhenReady([]);
  assert.deepEqual(calls, []);
});

test('deferred cleanup runs once when a Web controller attaches', () => {
  const { service, calls } = fixture();
  service.clearCookiesWhenReady();
  service.clearCookiesWhenReady();
  service.clearPrivateSiteDataWhenReady([]);
  service.onWebControllerAttached();
  service.onWebControllerAttached();
  assert.equal(calls[0], 'config:https://developer.huawei.com/:state=; Max-Age=0; Path=/; Secure:false:true');
  assert.equal(calls[1], 'config:https://developer.huawei.com/:urlBeforeLogin=; Max-Age=0; Path=/; Secure:false:true');
  assert.equal(calls[2], 'clear:false');
  assert.equal(calls[3], 'clear:true');
  assert.equal(calls[4], 'storage:true');
});

test('initialized browser retains cookie persistence and private isolation', () => {
  const { service, calls } = fixture();
  service.onWebControllerAttached();
  service.flushCookies();
  service.clearPrivateSiteDataWhenReady([{ removeCache: () => calls.push('cache') }]);
  service.clearCookiesWhenReady();
  assert.equal(calls[0], 'config:https://developer.huawei.com/:state=; Max-Age=0; Path=/; Secure:false:true');
  assert.equal(calls[1], 'config:https://developer.huawei.com/:urlBeforeLogin=; Max-Age=0; Path=/; Secure:false:true');
  assert.equal(calls[2], 'save');
  assert.equal(calls[3], 'clear:true');
  assert.equal(calls[4], 'storage:true');
  assert.equal(calls[5], 'cache');
  assert.equal(calls[6], 'clear:false');
});

test('explicit user clearing remains immediate before browsing', () => {
  const { service, calls } = fixture();
  service.clearCookiesAndStorage();
  assert.deepEqual(calls, ['clear:false', 'storage:false']);
});

test('tablet process-death flush promotes session cookies and purges poisoned nonces then saves', () => {
  const { service, calls } = fixture('tablet');
  service.onWebControllerAttached();
  const mark = calls.length;
  service.rememberCookieUrls(
    ['https://developer.huawei.com/consumer/cn/service/josp/agc/index.html#/'],
    ['https://id1.cloud.huawei.com/cas/login']
  );
  service.persistCookiesAcrossProcessDeath();
  const flushCalls = calls.slice(mark);
  assert.equal(flushCalls[0], 'fetch:https://developer.huawei.com/');
  assert.equal(flushCalls[1], 'config:https://developer.huawei.com/:state=; Max-Age=0; Path=/; Secure:false:true');
  assert.equal(flushCalls[2], 'config:https://developer.huawei.com/:urlBeforeLogin=; Max-Age=0; Path=/; Secure:false:true');
  assert.equal(flushCalls[3], 'config:https://developer.huawei.com/:session=abc; Max-Age=2592000; Path=/; Secure:false:true');
  assert.equal(flushCalls[4], 'config:https://developer.huawei.com/:hwssot=token; Max-Age=2592000; Path=/; Secure:false:true');
  assert.equal(flushCalls[5], 'fetch:https://id1.cloud.huawei.com/');
  assert.equal(flushCalls[flushCalls.length - 1], 'save');
});

test('phone process-death flush saves without rewriting cookies', () => {
  const { service, calls } = fixture('phone');
  service.onWebControllerAttached();
  const mark = calls.length;
  service.rememberCookieUrls(['https://developer.huawei.com/agc'], []);
  service.persistCookiesAcrossProcessDeath();
  assert.deepEqual(calls.slice(mark), ['save']);
});

test('tab close cannot inject a warm-up cookie and both Web hosts signal readiness', () => {
  const page = readFileSync(new URL('../ohos/entry/src/main/ets/pages/Index.ets', import.meta.url), 'utf8');
  const ability = readFileSync(new URL('../ohos/entry/src/main/ets/entryability/EntryAbility.ets', import.meta.url), 'utf8');
  assert.doesNotMatch(page, /configCookieSync|dpkeep/);
  assert.match(page, /PrivacyService\.clearCookiesWhenReady\(\)/);
  assert.match(page, /PrivacyService\.clearPrivateSiteDataWhenReady\(/);
  assert.match(page, /onPageHide\(\): void/);
  assert.match(page, /persistCookiesAcrossProcessDeath\(\)/);
  assert.match(ability, /persistCookiesAcrossProcessDeath\(\)/);
  for (const name of ['BrowserWebView', 'OfflineArticleReader']) {
    const source = readFileSync(new URL(`../ohos/entry/src/main/ets/components/${name}.ets`, import.meta.url), 'utf8');
    assert.match(source, /\.onControllerAttached\([^]*?PrivacyService\.onWebControllerAttached\(\)/);
  }
});
