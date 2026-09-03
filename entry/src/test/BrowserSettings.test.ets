import { describe, expect, it } from '@ohos/hypium';
import {
  BrowserSettings,
  SitePermissionDecision,
  cloneSettings,
  defaultBrowserSettings,
  normalizeBrowserSettings
} from '../main/ets/models/BrowserModels';

export default function browserSettingsTest(): void {
  describe('BrowserSettings persistence shape', (): void => {
    it('keeps telemetry disabled until the user explicitly opts in', 0, (): void => {
      const settings: BrowserSettings = defaultBrowserSettings();

      expect(settings.telemetryEnabled).assertFalse();
    });

    it('clones the persisted schema shape without sharing mutable arrays', 0, (): void => {
      const settings: BrowserSettings = defaultBrowserSettings();
      settings.blockAds = false;
      settings.blockTrackers = false;
      settings.webDarkModeExcludedHosts = ['dark.example'];
      settings.sitePermissions = [{
        origin: 'https://camera.example',
        camera: SitePermissionDecision.Allow,
        microphone: SitePermissionDecision.Deny,
        location: SitePermissionDecision.Prompt,
        notifications: SitePermissionDecision.Deny
      }];

      const cloned: BrowserSettings = cloneSettings(settings);

      expect(cloned.blockAds).assertEqual(false);
      expect(cloned.blockTrackers).assertEqual(false);
      expect(cloned.siteZoomRatios.length).assertEqual(0);
      expect(cloned.webDarkModeExcludedHosts.length).assertEqual(1);
      expect(cloned.sitePermissions.length).assertEqual(1);
      expect(cloned.sitePermissions[0].camera).assertEqual(SitePermissionDecision.Allow);
      expect(cloned.sitePermissions[0].microphone).assertEqual(SitePermissionDecision.Deny);
      expect(cloned.sitePermissions[0].location).assertEqual(SitePermissionDecision.Prompt);
      expect(cloned.sitePermissions[0].notifications).assertEqual(SitePermissionDecision.Deny);

      settings.webDarkModeExcludedHosts[0] = 'changed.example';
      settings.sitePermissions[0].camera = SitePermissionDecision.Deny;

      expect(cloned.webDarkModeExcludedHosts[0]).assertEqual('dark.example');
      expect(cloned.sitePermissions[0].camera).assertEqual(SitePermissionDecision.Allow);
    });

    it('canonicalizes combined content protection through blockAds OR blockTrackers', 0, (): void => {
      const inputs: boolean[][] = [
        [false, false],
        [true, false],
        [false, true],
        [true, true]
      ];
      const expected: boolean[] = [false, true, true, true];

      for (let index: number = 0; index < inputs.length; index += 1) {
        const settings: BrowserSettings = defaultBrowserSettings();
        settings.blockAds = inputs[index][0];
        settings.blockTrackers = inputs[index][1];

        const cloned: BrowserSettings = normalizeBrowserSettings(settings);

        expect(cloned.blockAds).assertEqual(expected[index]);
        expect(cloned.blockTrackers).assertEqual(expected[index]);
      }
    });

    it('drops legacy site scale factors that included device density', 0, (): void => {
      const settings: BrowserSettings = defaultBrowserSettings();
      settings.siteZoomRatios = [{ host: 'developer.huawei.com', percent: 300 }];

      expect(cloneSettings(settings).siteZoomRatios.length).assertEqual(0);
    });

    it('forces notification permissions to Deny without changing other decisions', 0, (): void => {
      const settings: BrowserSettings = defaultBrowserSettings();
      settings.sitePermissions = [{
        origin: 'https://permissions.example',
        camera: SitePermissionDecision.Allow,
        microphone: SitePermissionDecision.Prompt,
        location: SitePermissionDecision.Deny,
        notifications: SitePermissionDecision.Allow
      }];

      const cloned: BrowserSettings = normalizeBrowserSettings(settings);

      expect(cloned.sitePermissions[0].camera).assertEqual(SitePermissionDecision.Allow);
      expect(cloned.sitePermissions[0].microphone).assertEqual(SitePermissionDecision.Prompt);
      expect(cloned.sitePermissions[0].location).assertEqual(SitePermissionDecision.Deny);
      expect(cloned.sitePermissions[0].notifications).assertEqual(SitePermissionDecision.Deny);
    });

    it('clamps the start-page shortcut limit to the supported range', 0, (): void => {
      const settings: BrowserSettings = defaultBrowserSettings();
      settings.quickSiteLimit = 99;

      const normalized: BrowserSettings = normalizeBrowserSettings(settings);

      expect(normalized.quickSiteLimit).assertEqual(8);
    });

    it('defaults privacy consent to false and preserves accepted status through normalization', 0, (): void => {
      const initial: BrowserSettings = defaultBrowserSettings();
      expect(initial.privacyConsentAccepted).assertFalse();

      initial.privacyConsentAccepted = true;
      const cloned: BrowserSettings = cloneSettings(initial);
      expect(cloned.privacyConsentAccepted).assertTrue();

      initial.privacyConsentAccepted = false;
      const clonedFalse: BrowserSettings = cloneSettings(initial);
      expect(clonedFalse.privacyConsentAccepted).assertFalse();
    });
  });
}
