import { describe, expect, it } from '@ohos/hypium';
import { WebKernelService } from '../main/ets/services/WebKernelService';

export default function browserKernelServiceTest(): void {
  describe('WebKernelService policy', (): void => {
    it('clamps progress to the ArkWeb callback range', 0, (): void => {
      expect(WebKernelService.clampProgress(-1)).assertEqual(0);
      expect(WebKernelService.clampProgress(42)).assertEqual(42);
      expect(WebKernelService.clampProgress(101)).assertEqual(100);
      expect(WebKernelService.clampProgress(Number.NaN)).assertEqual(0);
    });

    it('accepts only negative relative back steps', 0, (): void => {
      expect(WebKernelService.isBackwardStep(-1)).assertTrue();
      expect(WebKernelService.isBackwardStep(0)).assertFalse();
      expect(WebKernelService.isBackwardStep(1)).assertFalse();
    });

    it('refreshes navigation state only for main-frame history commits', 0, (): void => {
      expect(WebKernelService.shouldRefreshNavigationState(true)).assertTrue();
      expect(WebKernelService.shouldRefreshNavigationState(false)).assertFalse();
    });

    it('selects desktop or captured mobile user agent', 0, (): void => {
      const mobileUserAgent: string = 'mobile-agent';
      expect(WebKernelService.userAgentFor(false, mobileUserAgent)).assertEqual(mobileUserAgent);
      expect(WebKernelService.userAgentFor(true, mobileUserAgent)).assertContain('Chrome');
    });
  });
}
