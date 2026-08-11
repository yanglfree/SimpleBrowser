import { describe, expect, it } from '@ohos/hypium';
import { Overlay, shouldMountOverlayLayer, shouldUseResponsivePanel } from '../main/ets/pages/Index';
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

    it('does not mount an overlay layer when no overlay is visible', 0, (): void => {
      expect(shouldMountOverlayLayer(Overlay.None)).assertFalse();
      expect(shouldMountOverlayLayer(Overlay.Actions)).assertTrue();
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
