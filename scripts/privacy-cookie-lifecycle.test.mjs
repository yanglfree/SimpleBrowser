import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { runInNewContext } from 'node:vm';

function fixture() {
  const calls = [];
  const source = readFileSync(new URL('../ohos/entry/src/main/ets/services/PrivacyService.ets', import.meta.url), 'utf8')
    .replace(/^import .*;\n/gm, '').replace('export class', 'class');
  const service = runInNewContext(stripTypeScriptTypes(`${source}\nPrivacyService;`), {
    Logger: { warn: () => calls.push('warning') },
    webview: {
      WebviewController: { setWebDebuggingAccess: () => {} },
      WebCookieManager: {
        putAcceptCookieEnabled: () => {},
        putAcceptThirdPartyCookieEnabled: () => {},
        saveCookieSync: () => calls.push('save'),
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
  assert.deepEqual(calls, ['clear:false', 'clear:true', 'storage:true']);
});

test('initialized browser retains cookie persistence and private isolation', () => {
  const { service, calls } = fixture();
  service.onWebControllerAttached();
  service.flushCookies();
  service.clearPrivateSiteDataWhenReady([{ removeCache: () => calls.push('cache') }]);
  service.clearCookiesWhenReady();
  assert.deepEqual(calls, ['save', 'clear:true', 'storage:true', 'cache', 'clear:false']);
});

test('explicit user clearing remains immediate before browsing', () => {
  const { service, calls } = fixture();
  service.clearCookiesAndStorage();
  assert.deepEqual(calls, ['clear:false', 'storage:false']);
});

test('tab close cannot inject a warm-up cookie and both Web hosts signal readiness', () => {
  const page = readFileSync(new URL('../ohos/entry/src/main/ets/pages/Index.ets', import.meta.url), 'utf8');
  assert.doesNotMatch(page, /configCookieSync|dpkeep/);
  assert.match(page, /PrivacyService\.clearCookiesWhenReady\(\)/);
  assert.match(page, /PrivacyService\.clearPrivateSiteDataWhenReady\(/);
  for (const name of ['BrowserWebView', 'OfflineArticleReader']) {
    const source = readFileSync(new URL(`../ohos/entry/src/main/ets/components/${name}.ets`, import.meta.url), 'utf8');
    assert.match(source, /\.onControllerAttached\([^]*?PrivacyService\.onWebControllerAttached\(\)/);
  }
});
