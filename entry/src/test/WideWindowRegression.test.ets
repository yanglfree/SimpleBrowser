import { describe, expect, it } from '@ohos/hypium';
import { desktopTabWidth } from '../main/ets/components/DesktopTabStrip';
import { Overlay, shouldMountOverlayLayer, shouldUseResponsivePanel } from '../main/ets/pages/Index';
import { BrowserLayoutClass, shouldEnableDockTabSwipe } from '../main/ets/models/WindowMetrics';
import { shouldLayoutFullScreen } from '../main/ets/services/ThemeService';
import {
  MAIN_WINDOW_INSTANCE_ID,
  resolveWindowInstanceId
} from '../main/ets/models/WindowLaunchPolicy';

export default function wideWindowRegressionTest(): void {
  describe('Wide-window regression boundaries', (): void => {
    it('does not mount a responsive panel when no overlay is visible', 0, (): void => {
      const shouldMount: boolean = shouldUseResponsivePanel(true, Overlay.None);

      expect(shouldMount).assertFalse();
    });

    it('keeps the address sheet full-screen instead of a right-hand panel on wide layouts', 0, (): void => {
      expect(shouldUseResponsivePanel(true, Overlay.Address)).assertFalse();
    });

    it('does not mount an overlay layer when no overlay is visible', 0, (): void => {
      expect(shouldMountOverlayLayer(Overlay.None)).assertFalse();
      expect(shouldMountOverlayLayer(Overlay.Actions)).assertTrue();
    });

    it('disables phone tab swipe navigation when the desktop tab strip is visible', 0, (): void => {
      expect(shouldEnableDockTabSwipe(BrowserLayoutClass.Compact, true)).assertTrue();
      expect(shouldEnableDockTabSwipe(BrowserLayoutClass.Medium, true)).assertTrue();
      expect(shouldEnableDockTabSwipe(BrowserLayoutClass.Expanded, true)).assertTrue();
      expect(shouldEnableDockTabSwipe(BrowserLayoutClass.Desktop, true)).assertFalse();
      expect(shouldEnableDockTabSwipe(BrowserLayoutClass.Compact, false)).assertFalse();
      expect(shouldEnableDockTabSwipe(BrowserLayoutClass.Desktop, false)).assertFalse();
    });

    it('continuously fits desktop tab widths to the available chrome', 0, (): void => {
      expect(desktopTabWidth(1200, 4, 0)).assertEqual(240);
      expect(desktopTabWidth(1200, 8, 0)).assertEqual(139);
      expect(desktopTabWidth(1200, 16, 0)).assertEqual(88);
      expect(desktopTabWidth(1200, 8, 2)).assertEqual(168);
    });

    it('keeps one window coordinate system while switching between home and web tabs', 0, (): void => {
      expect(shouldLayoutFullScreen(true)).assertTrue();
      expect(shouldLayoutFullScreen(false)).assertTrue();
    });

    it('reuses the main instance for ordinary launches', 0, (): void => {
      const instanceId: string = resolveWindowInstanceId('');

      expect(instanceId).assertEqual(MAIN_WINDOW_INSTANCE_ID);
    });

    it('keeps an explicit token for a moved-tab window', 0, (): void => {
      const instanceId: string = resolveWindowInstanceId('window-42');

      expect(instanceId).assertEqual('window-42');
    });
  });
}
