import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { runInNewContext } from 'node:vm';

function deferred() {
  let resolve;
  let reject;
  const promise = new Promise((accept, decline) => {
    resolve = accept;
    reject = decline;
  });
  return { promise, resolve, reject };
}

function createService() {
  const source = readFileSync(new URL('../entry/src/main/ets/services/AdsBlockService.ets', import.meta.url), 'utf8')
    .replace(/^import .*;\n/gm, '')
    .replace(/^export /gm, '');
  const installed = [];
  const AdsBlockService = runInNewContext(`${stripTypeScriptTypes(source)}\nAdsBlockService;`, {
    Logger: { info() {}, warn() {}, error() {} },
    RuleEngine: { compile: () => ({ ruleCount: 1 }) },
    CosmeticFilterService: { compile: () => ({}) },
    webview: { AdsBlockManager: { setAdsBlockRules: (path) => installed.push(path) } }
  });
  const service = new AdsBlockService();
  const written = [];
  service.isInitialized = true;
  service.rulesPath = 'current-rules';
  service.isWifiConnected = () => true;
  service.updateSupplement = async () => {};
  service.writeRulesAtomically = async (rules) => written.push(rules);
  service.saveUpdatedAt = async () => {};
  let requests = 0;
  let download = deferred();
  AdsBlockService.fetchRemoteRules = () => {
    requests++;
    return download.promise;
  };
  return {
    service, installed, written,
    get requests() { return requests; },
    get download() { return download; },
    nextDownload() { download = deferred(); }
  };
}

function createPage(service) {
  const source = readFileSync(new URL('../entry/src/main/ets/pages/Index.ets', import.meta.url), 'utf8');
  const start = source.indexOf('  private async updateRules(): Promise<void> {');
  const end = source.indexOf('  private async setDefaultBrowser()', start);
  assert.ok(start >= 0 && end > start);
  const Page = runInNewContext(stripTypeScriptTypes(`class Page {\n${source.slice(start, end)}\n}\nPage;`), {
    $r: (key) => key,
    Logger: { warn() {} }
  });
  const page = new Page();
  const toasts = [];
  page.viewModel = { adsBlockService: service };
  page.isRulesUpdating = false;
  page.rulesLastUpdatedAt = 0;
  page.getUIContext = () => ({ getPromptAction: () => ({ showToast: ({ message }) => toasts.push(message) }) });
  return { page, toasts };
}

test('manual update joins a pending automatic refresh without reporting failure', async () => {
  const fixture = createService();
  const automatic = fixture.service.updateRulesIfNeeded();
  const manual = fixture.service.updateRules(true);
  let settled = false;
  void manual.then(() => { settled = true; });
  await new Promise(setImmediate);
  assert.equal(settled, false);
  assert.equal(fixture.requests, 1);
  fixture.download.resolve('||ads.example^');
  assert.deepEqual(await Promise.all([automatic, manual]), [true, true]);
  assert.equal(fixture.installed.length, 1);
  assert.equal(fixture.written.length, 1);
  assert.ok(fixture.service.lastUpdatedAt > 0);
});

test('concurrent failures preserve current rules and release the next retry', async () => {
  const fixture = createService();
  fixture.service.updatedAt = 123;
  const first = fixture.service.updateRules(true);
  const second = fixture.service.updateRules(true);
  fixture.download.reject(new Error('offline'));
  assert.deepEqual(await Promise.all([first, second]), [false, false]);
  assert.equal(fixture.requests, 1);
  assert.equal(fixture.written.length, 0);
  assert.equal(fixture.installed.length, 0);
  assert.equal(fixture.service.lastUpdatedAt, 123);
  fixture.nextDownload();
  const retry = fixture.service.updateRules(true);
  fixture.download.resolve('||ads.example^');
  assert.equal(await retry, true);
  assert.equal(fixture.requests, 2);
});

test('a completed update releases the pending task for a later forced update', async () => {
  const fixture = createService();
  const first = fixture.service.updateRules(true);
  fixture.download.resolve('||first.example^');
  assert.equal(await first, true);
  fixture.nextDownload();
  const second = fixture.service.updateRules(true);
  fixture.download.resolve('||second.example^');
  assert.equal(await second, true);
  assert.equal(fixture.requests, 2);
  assert.equal(fixture.installed.length, 2);
});

test('repeated settings taps stay busy and show only the final success', async () => {
  const fixture = createService();
  const { page, toasts } = createPage(fixture.service);
  const first = page.updateRules();
  const second = page.updateRules();
  await new Promise(setImmediate);
  assert.equal(page.isRulesUpdating, true);
  assert.deepEqual(toasts, []);
  fixture.download.resolve('||ads.example^');
  await Promise.all([first, second]);
  assert.deepEqual(toasts, ['app.string.rules_update_success']);
  assert.equal(page.isRulesUpdating, false);
  assert.equal(page.rulesLastUpdatedAt, fixture.service.lastUpdatedAt);
});

test('settings joins automatic refresh and shows a single failure before allowing retry', async () => {
  const fixture = createService();
  const { page, toasts } = createPage(fixture.service);
  const automatic = fixture.service.updateRulesIfNeeded();
  const manual = page.updateRules();
  await page.updateRules();
  await new Promise(setImmediate);
  assert.deepEqual(toasts, []);
  fixture.download.reject(new Error('offline'));
  await Promise.all([automatic, manual]);
  assert.deepEqual(toasts, ['app.string.rules_update_failed']);
  assert.equal(page.isRulesUpdating, false);
  fixture.nextDownload();
  const retry = page.updateRules();
  fixture.download.resolve('||ads.example^');
  await retry;
  assert.deepEqual(toasts, ['app.string.rules_update_failed', 'app.string.rules_update_success']);
});
