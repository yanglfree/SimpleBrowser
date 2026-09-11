import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { runInNewContext } from 'node:vm';

const read = path => readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');
const pageSource = read('entry/src/main/ets/pages/Index.ets');
const repositorySource = read('entry/src/main/ets/repositories/BrowserRepository.ets');
const viewModelSource = read('entry/src/main/ets/viewmodels/BrowserViewModel.ets');
const cloneSettings = value => ({ ...value });
const Logger = { warn() {}, error() {}, info() {} };
function between(source, start, end) {
  const from = source.indexOf(start);
  const to = source.indexOf(end, from);
  assert.ok(from >= 0 && to > from, `${start} -> ${end}`);
  return source.slice(from, to);
}
function evaluate(source, context = {}) {
  return runInNewContext(stripTypeScriptTypes(source), { Logger, cloneSettings, ...context });
}
const styleSource = read('entry/src/main/ets/models/SystemBarStyle.ets')
  .replace(/^import .*;\n/gm, '').replace(/export /g, '');
const readerSource = between(read('entry/src/main/ets/models/BrowserModels.ets'),
  'export function getReaderTheme', 'export enum');
const getReaderTheme = evaluate(`${readerSource.replace(/export /g, '')}\ngetReaderTheme;`, {
  ReaderPaper: { White: 0, Sepia: 1, Night: 2 }
});
const styles = evaluate(`${styleSource}\n({ resolveSystemBarStyle, HOME_STATUS_SCRIM });`, { getReaderTheme });
function luminance(rgb) {
  const linear = rgb.map(value => value / 255).map(v => v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4);
  return linear[0] * 0.2126 + linear[1] * 0.7152 + linear[2] * 0.0722;
}
const rgb = hex => hex.match(/[a-f0-9]{2}/gi).map(value => parseInt(value, 16));
function contrast(a, b) {
  const values = [luminance(a), luminance(b)].sort((x, y) => y - x);
  return (values[0] + 0.05) / (values[1] + 0.05);
}

test('status backdrop meets contrast on white wallpaper, light/dark pages and reader sheets', () => {
  const alpha = parseInt(styles.HOME_STATUS_SCRIM.slice(1, 3), 16) / 255;
  assert.ok(contrast([255, 255, 255], [255, 255, 255].map(v => v * (1 - alpha))) >= 3);
  for (const dark of [true, false]) {
    for (const overlay of [true, false]) {
      for (const paper of [0, 1, 2]) {
        const style = styles.resolveSystemBarStyle(dark, false, true, paper, overlay);
        assert.ok(contrast(rgb(style.background), rgb(style.content)) >= 3);
        if (overlay) assert.equal(style.background, dark ? '#131311' : '#FAF9F7');
      }
    }
  }
});

test('settings refresh preserves modal bar styling and skips repeated native calls', () => {
  const calls = [];
  const Page = evaluate(`class Page {
    ${between(pageSource, '  private onSheetChanged()', '  private decodeTransferredTab()')}
  }\nPage;`, {
    resolveSystemBarStyle: styles.resolveSystemBarStyle,
    ThemeService: { isDark: () => false, applySurface: async (_, style) => calls.push(style) },
    Overlay: { None: 0 }
  });
  const page = new Page();
  Object.assign(page, {
    appContext: () => ({}), isActiveHome: () => true, isActiveReader: () => false, usesWideChrome: () => false,
    settings: { startPageBackgroundEnabled: true }, sheet: 0
  });
  page.refreshSystemBarStyle();
  assert.equal(calls.at(-1).wallpaper, true);
  page.sheet = 1;
  page.onSheetChanged();
  assert.equal(calls.at(-1).content, '#1A1A18');
  page.settings.quickSitesEnabled = false;
  page.refreshSystemBarStyle();
  assert.equal(calls.length, 2);
  page.sheet = 0;
  page.onSheetChanged();
  assert.equal(calls.at(-1).wallpaper, true);
  page.usesWideChrome = () => true;
  page.refreshSystemBarStyle();
  assert.equal(calls.at(-1).wallpaper, false);
});

test('native window resolution cannot apply a stale style after a newer request', async () => {
  let oldResolve;
  let count = 0;
  const calls = [];
  const mainWindow = {
    getWindowProperties: () => ({ isLayoutFullScreen: true }),
    setWindowLayoutFullScreen: async () => { assert.fail('Already-fullscreen windows must not relayout'); },
    setWindowBackgroundColor: () => {},
    setWindowSystemBarProperties: async properties => calls.push(properties)
  };
  const source = read('entry/src/main/ets/services/ThemeService.ets')
    .replace(/^import .*;\n/gm, '').replace(/export /g, '');
  const ThemeService = evaluate(`${source}\nThemeService;`, {
    window: { getLastWindow: () => ++count === 1 ? new Promise(resolve => { oldResolve = resolve; }) : Promise.resolve(mainWindow) }
  });
  const context = {};
  const old = ThemeService.applySurface(context, { background: '#000000', content: '#FFFFFF' });
  await ThemeService.applySurface(context, { background: '#FFFFFF', content: '#000000' });
  oldResolve(mainWindow);
  await old;
  assert.equal(calls.length, 1);
  assert.equal(calls[0].statusBarContentColor, '#000000');
});

function persistenceFixture() {
  const Repository = evaluate(`class Repository {
    ${between(repositorySource, '  async saveSettings(', '  getSiteStats(')}
  }\nRepository;`, { TAG: 'Repository', SETTINGS_KEY: 'settings' });
  const ViewModel = evaluate(`class ViewModel {
    ${between(viewModelSource, '  async updateSettings(', '  async clearHistory(')}
  }\nViewModel;`, { TAG: 'ViewModel', DownloadService: { setConcurrencyLimit() {} } });
  const repository = new Repository();
  const initial = { privacyConsentAccepted: false, historyRetentionDays: 30 };
  let cached = JSON.stringify(initial);
  let durable = cached;
  let failNext = false;
  repository.settings = cloneSettings(initial);
  repository.saveQueue = Promise.resolve();
  repository.store = {
    put: async (_, value) => { cached = value; },
    flush: async () => {
      if (failNext) { failNext = false; throw new Error('disk unavailable'); }
      durable = cached;
    }
  };
  const viewModel = new ViewModel();
  viewModel.settings = cloneSettings(initial);
  viewModel.repository = repository;
  return { repository, viewModel, fail: () => { failNext = true; }, durable: () => JSON.parse(durable) };
}

test('failed consent flush restores both settings snapshots and the Preferences cache, then permits retry', async () => {
  const { repository, viewModel, fail, durable } = persistenceFixture();
  fail();
  await assert.rejects(viewModel.updateSettings({ ...viewModel.settings, privacyConsentAccepted: true }), /disk unavailable/);
  assert.equal(viewModel.settings.privacyConsentAccepted, false);
  assert.equal(repository.settings.privacyConsentAccepted, false);
  assert.equal(durable().privacyConsentAccepted, false);
  await repository.store.flush();
  assert.equal(durable().privacyConsentAccepted, false);
  await viewModel.updateSettings({ ...viewModel.settings, privacyConsentAccepted: true });
  assert.equal(viewModel.settings.privacyConsentAccepted, true);
  assert.equal(durable().privacyConsentAccepted, true);
});

test('settings cannot succeed before storage initialization', async () => {
  const { repository, viewModel } = persistenceFixture();
  repository.store = undefined;
  await assert.rejects(viewModel.updateSettings({ ...viewModel.settings, privacyConsentAccepted: true }), /not initialized/);
  assert.equal(viewModel.settings.privacyConsentAccepted, false);
});

test('ordinary settings changes skip history cleanup and preserve queued ordering', async () => {
  const { repository, viewModel, durable } = persistenceFixture();
  let retentions = 0;
  repository.applyHistoryRetention = async () => { retentions++; };
  repository.getHistory = () => [];
  await Promise.all([
    viewModel.updateSettings({ ...viewModel.settings, quickSitesEnabled: false }),
    viewModel.updateSettings({ ...viewModel.settings, quickSitesEnabled: true })
  ]);
  assert.equal(durable().quickSitesEnabled, true);
  assert.equal(viewModel.settings.quickSitesEnabled, true);
  assert.equal(retentions, 0);
  await viewModel.updateSettings({ ...viewModel.settings, historyRetentionDays: 7 });
  assert.equal(retentions, 1);
});

test('privacy card fits phone, landscape and floating heights with system clearance', () => {
  const source = read('entry/src/main/ets/components/PrivacyConsentDialog.ets');
  const fn = evaluate(`${between(source, 'export function privacyDialogHeight', '@Component').replace('export ', '')}\nprivacyDialogHeight;`);
  for (const height of [360, 480, 800, 1000]) {
    for (const bottom of [0, 24, 40]) {
      const top = 36;
      const card = fn(height, top, bottom);
      const offset = (Math.max(top, 28) - Math.max(bottom, 28) - 4) / 2;
      const cardBottom = (height + card) / 2 + offset;
      assert.ok(height - cardBottom >= Math.max(bottom, 28) + 16);
      assert.ok((height - card) / 2 + offset >= top + 12);
    }
  }
});

test('launcher icon has one unambiguous 1024px PNG resource', () => {
  const roots = ['AppScope/resources/base/media', 'entry/src/main/resources/base/media'];
  const matches = roots.flatMap(root => readdirSync(new URL(`../${root}`, import.meta.url))
    .filter(name => /^app_icon\./.test(name)).map(name => `${root}/${name}`));
  assert.deepEqual(matches, ['AppScope/resources/base/media/app_icon.png']);
  const png = readFileSync(new URL(`../${matches[0]}`, import.meta.url));
  assert.equal(png.readUInt32BE(16), 1024);
  assert.equal(png.readUInt32BE(20), 1024);
});
