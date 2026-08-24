import { describe, expect, it } from '@ohos/hypium';
import { WebDarkModePreference } from '../main/ets/models/BrowserModels';
import { SiteControlMode, defaultSiteControl, resolveSiteControl } from '../main/ets/models/SiteControlModels';

export default function siteControlModelsTest(): void {
  describe('Site control models', (): void => {
    it('inherits defaults until a site override is selected', 0, (): void => {
      const control = defaultSiteControl('example.com');
      control.networkBlocking = SiteControlMode.Disabled;
      control.darkMode = SiteControlMode.Enabled;
      const effective = resolveSiteControl(control, true, true, true, WebDarkModePreference.Light, false);
      expect(effective.networkBlockingEnabled).assertFalse();
      expect(effective.trackerBlockingEnabled).assertTrue();
      expect(effective.webDarkMode).assertEqual(WebDarkModePreference.Dark);
      expect(effective.desktopUserAgentEnabled).assertFalse();
    });
  });
}
