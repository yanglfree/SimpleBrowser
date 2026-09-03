import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { runInNewContext } from 'node:vm';

const source = readFileSync(new URL('../entry/src/main/ets/pages/Index.ets', import.meta.url), 'utf8');
function method(start, end) {
  const from = source.indexOf(`  private ${start}`);
  const to = source.indexOf(`  private ${end}`, from);
  assert.ok(from >= 0 && to > from);
  return source.slice(from, to);
}

function fixture(settings = {}) {
  const calls = [];
  const Page = runInNewContext(stripTypeScriptTypes(`class Page {
    ${method('resumeConsentedStartup()', 'decodeTransferredTab()')}
    ${method('async acceptPrivacyConsent()', 'async openExternalWebUrl(')}
    ${method('async finishOnboarding()', 'async exportBookmarks()')}
  }\nPage;`), {
    TAG: 'PrivacyStartupTest',
    Overlay: { None: 0, PrivacyConsent: 26, Onboarding: 1 },
    cloneSettings: value => ({ ...value }),
    TelemetryService: { setEnabled: value => calls.push(['telemetry', value]) },
    ExternalOpenRouter: { subscribe: () => calls.push(['external']) },
    Logger: { warn: () => {} },
    $r: value => value
  });
  const page = new Page();
  page.settings = { privacyConsentAccepted: false, onboardingCompleted: false, telemetryEnabled: false, ...settings };
  page.sheet = 0;
  page.consentServicesStarted = false;
  page.isAcceptingPrivacyConsent = false;
  page.refreshSiteIcons = () => calls.push(['icons']);
  page.syncProEntitlement = async () => calls.push(['entitlement']);
  page.promptExpiredTabs = () => calls.push(['expired']);
  page.showToast = () => calls.push(['error']);
  page.viewModel = {
    updateSettings: async () => calls.push(['persist']),
    adsBlockService: { updateRulesIfNeeded: async () => calls.push(['rules']) }
  };
  return { page, calls };
}

test('unresolved consent never starts background services or delivers an external link', () => {
  const { page, calls } = fixture({ telemetryEnabled: true, onboardingCompleted: true });
  page.resumeConsentedStartup();
  assert.equal(page.sheet, 26);
  assert.deepEqual(calls, []);
});

test('onboarding keeps external entry queued after acceptance', async () => {
  const { page, calls } = fixture();
  await page.acceptPrivacyConsent();
  assert.equal(page.settings.privacyConsentAccepted, true);
  assert.equal(page.sheet, 1);
  assert.deepEqual(calls, [['persist']]);
  await page.finishOnboarding();
  assert.equal(page.sheet, 0);
  assert.deepEqual(calls.map(call => call[0]), ['persist', 'persist', 'telemetry', 'icons', 'rules', 'entitlement', 'expired', 'external']);
});

test('accepted returning users start services once with the stored telemetry choice', async () => {
  const { page, calls } = fixture({ onboardingCompleted: true });
  await page.acceptPrivacyConsent();
  page.resumeConsentedStartup();
  assert.equal(page.sheet, 0);
  assert.equal(calls.filter(call => call[0] === 'entitlement').length, 1);
  assert.equal(calls.filter(call => call[0] === 'external').length, 1);
  assert.deepEqual(calls.find(call => call[0] === 'telemetry'), ['telemetry', false]);
});

test('failed consent persistence leaves the dialog and all network services blocked', async () => {
  const { page, calls } = fixture();
  page.sheet = 26;
  page.viewModel.updateSettings = async () => { throw new Error('storage unavailable'); };
  await page.acceptPrivacyConsent();
  assert.equal(page.settings.privacyConsentAccepted, false);
  assert.equal(page.sheet, 26);
  assert.equal(page.isAcceptingPrivacyConsent, false);
  assert.deepEqual(calls, [['error']]);
});

test('duplicate acceptance waits for one persistence operation', async () => {
  const { page, calls } = fixture({ onboardingCompleted: true });
  let complete;
  page.viewModel.updateSettings = () => new Promise(resolve => { complete = resolve; });
  const pending = page.acceptPrivacyConsent();
  await page.acceptPrivacyConsent();
  assert.equal(page.isAcceptingPrivacyConsent, true);
  assert.deepEqual(calls, []);
  complete();
  await pending;
  assert.equal(page.isAcceptingPrivacyConsent, false);
  assert.equal(calls.filter(call => call[0] === 'entitlement').length, 1);
});
