import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { runInNewContext } from 'node:vm';

function fixture(deviceType = 'phone', cookies = []) {
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
          // Model Chromium's cookie identity: name, domain, path and partition.
          const name = value.split('=')[0];
          const domain = new URL(url).hostname;
          if (value.includes('Max-Age=0') && !value.includes('Domain=')) {
            for (let i = cookies.length - 1; i >= 0; i--) {
              const cookie = cookies[i];
              if (cookie.name === name && cookie.domain === domain && cookie.path === '/' &&
                  cookie.private === incognito) cookies.splice(i, 1);
            }
          }
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

test('legacy repair runs once and deferred user cleanup remains isolated', () => {
  const { service, calls } = fixture();
  service.clearCookiesWhenReady();
  service.clearPrivateSiteDataWhenReady([]);
  service.onWebControllerAttached();
  const firstAttach = calls.slice();
  service.onWebControllerAttached();
  assert.deepEqual(calls, firstAttach);
  assert.deepEqual(calls.slice(-3), ['clear:false', 'clear:true', 'storage:true']);
  const repairs = calls.filter(call => call.startsWith('config:'));
  assert.equal(repairs.length, 13);
  for (const name of ['state', 'urlBeforeLogin', 'authInfo', 'authdata', 'csrfToken', 'developer_userinfo',
    'x-siteId', 'x-country', 'x-userType', 'x-hd-grey', 'x-uid', 'x-teamId', 'X-HD-SESSION']) {
    assert(repairs.includes(`config:https://developer.huawei.com/:${name}=; Max-Age=0; Path=/; Secure:false:true`));
  }
  assert(repairs.every(call => !call.includes('Domain=')));
});

test('initialized browser retains native persistence and private isolation', () => {
  const { service, calls } = fixture();
  service.onWebControllerAttached();
  const mark = calls.length;
  service.flushCookies();
  service.clearPrivateSiteDataWhenReady([{ removeCache: () => calls.push('cache') }]);
  service.clearCookiesWhenReady();
  assert.deepEqual(calls.slice(mark), ['save', 'clear:true', 'storage:true', 'cache', 'clear:false']);
});

test('explicit user clearing remains immediate before browsing', () => {
  const { service, calls } = fixture();
  service.clearCookiesAndStorage();
  assert.deepEqual(calls, ['clear:false', 'storage:false']);
});

for (const type of ['phone', 'tablet', '2in1', 'pc']) {
  test(`${type} background flush never rewrites cookie attributes or active OAuth state`, () => {
    const { service, calls } = fixture(type);
    service.onWebControllerAttached();
    const mark = calls.length;
    service.persistCookiesAcrossProcessDeath();
    service.persistCookiesAcrossProcessDeath();
    assert.deepEqual(calls.slice(mark), ['save', 'save']);
  });
}

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

test('tablet backgrounding never reconstructs cookies from a lossy request header', () => {
  const { service, calls } = fixture('tablet');
  service.onWebControllerAttached();
  const mark = calls.length;
  service.persistCookiesAcrossProcessDeath();
  assert.deepEqual(calls.slice(mark), ['save']);
});

test('attaching a second tab cannot delete an active OAuth flow', () => {
  const { service, calls } = fixture('tablet');
  service.onWebControllerAttached();
  const mark = calls.length;
  service.onWebControllerAttached();
  assert.deepEqual(calls.slice(mark), []);
});


test('AGC migration removes stale host shadows while retaining fresh domain and private cookies', () => {
  const fresh = { name: 'developer_userinfo', domain: '.developer.huawei.com', path: '/',
    private: false, value: 'fresh-csrf', secure: true, httpOnly: false, sameSite: 'Lax' };
  const auth = { name: 'authdata', domain: '.developer.huawei.com', path: '/',
    private: false, value: 'fresh-auth', secure: true, httpOnly: true, sameSite: 'None' };
  const unrelated = { name: 'authdata', domain: 'example.com', path: '/', private: false, value: 'other' };
  const privateCookie = { name: 'authdata', domain: 'developer.huawei.com', path: '/', private: true, value: 'private' };
  const pathCookie = { name: 'authdata', domain: 'developer.huawei.com', path: '/other', private: false, value: 'path' };
  const cookies = [
    { ...fresh, domain: 'developer.huawei.com', value: 'stale-csrf' },
    { ...auth, domain: 'developer.huawei.com', value: 'stale-auth', httpOnly: false },
    fresh, auth, unrelated, privateCookie, pathCookie
  ];
  const { service } = fixture('tablet', cookies);
  service.onWebControllerAttached();
  service.persistCookiesAcrossProcessDeath();
  service.onWebControllerAttached();
  assert.deepEqual(cookies, [fresh, auth, unrelated, privateCookie, pathCookie]);
});
