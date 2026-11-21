import { describe, expect, it } from '@ohos/hypium';
import { DESKTOP_VIEWPORT_SCRIPT } from '../main/ets/constants/AppConstants';
import { WebKernelService, WebLongPressKind } from '../main/ets/services/WebKernelService';

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

    it('keeps back available for a failed first page', 0, (): void => {
      expect(WebKernelService.canNavigateBack(false, false)).assertTrue();
      expect(WebKernelService.canNavigateBack(false, true)).assertFalse();
      expect(WebKernelService.canNavigateBack(true, false)).assertTrue();
      expect(WebKernelService.shouldReturnHomeOnBack(false, false)).assertTrue();
      expect(WebKernelService.shouldReturnHomeOnBack(true, false)).assertFalse();
      expect(WebKernelService.shouldReturnHomeOnBack(false, true)).assertFalse();
    });

    it('selects desktop or captured mobile user agent', 0, (): void => {
      const mobileUserAgent: string = 'mobile-agent';
      expect(WebKernelService.userAgentFor(false, mobileUserAgent)).assertEqual(mobileUserAgent);
      expect(WebKernelService.userAgentFor(true, mobileUserAgent)).assertContain('Chrome');
    });

    it('upgrades known mobile-only entry points for desktop browsing', 0, (): void => {
      expect(WebKernelService.desktopUrlFor('https://m.weibo.cn/'))
        .assertEqual('https://weibo.com/');
      expect(WebKernelService.desktopUrlFor('https://m.weibo.cn/search?q=dolphin'))
        .assertEqual('https://weibo.com/search?q=dolphin');
      expect(WebKernelService.desktopUrlFor('https://m.example.com/page'))
        .assertEqual('https://m.example.com/page');
    });

    it('uses the available web surface for desktop viewport layout', 0, (): void => {
      expect(DESKTOP_VIEWPORT_SCRIPT).assertContain('width=device-width');
      expect(DESKTOP_VIEWPORT_SCRIPT.includes('width=1024')).assertFalse();
    });

    it('synchronizes desktop UA Chrome version from the stock kernel user agent', 0, (): void => {
      const stock: string = 'Mozilla/5.0 (OpenHarmony) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.7390.55 Safari/537.36';
      const desktop: string = WebKernelService.resolveDesktopUserAgent(stock);
      expect(desktop).assertContain('Chrome/141.0.7390.55');
      expect(desktop).assertContain('X11; Linux x86_64');
      expect(WebKernelService.resolveDesktopUserAgent('custom-agent')).assertContain('Chrome/132.0.0.0');
      const legacyStock: string = 'Mozilla/5.0 (Phone; OpenHarmony 5.0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36 ArkWeb/4.1.6.1 Mobile';
      expect(WebKernelService.resolveDesktopUserAgent(legacyStock)).assertContain('Chrome/132.0.0.0');
    });

    it('uses compatible Android Chrome mobile UA only for Google hosts', 0, (): void => {
      const stock6: string =
        'Mozilla/5.0 (Phone; OpenHarmony 6.0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.7390.55 Safari/537.36 ArkWeb/6.0.0.130 Mobile';
      const stock5: string =
        'Mozilla/5.0 (Phone; OpenHarmony 5.0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36 ArkWeb/4.1.6.1 Mobile';

      expect(WebKernelService.needsCompatibleMobileUserAgent('https://google.com/')).assertTrue();
      expect(WebKernelService.needsCompatibleMobileUserAgent('https://www.google.com/search?q=test')).assertTrue();
      expect(WebKernelService.needsCompatibleMobileUserAgent('https://accounts.google.com/')).assertTrue();
      expect(WebKernelService.needsCompatibleMobileUserAgent('https://www.google.com.hk/')).assertTrue();
      expect(WebKernelService.needsCompatibleMobileUserAgent('https://www.google.co.jp/')).assertTrue();
      expect(WebKernelService.needsCompatibleMobileUserAgent('https://www.google.de/')).assertTrue();

      expect(WebKernelService.needsCompatibleMobileUserAgent('https://www.zhihu.com/')).assertFalse();
      expect(WebKernelService.needsCompatibleMobileUserAgent('https://developer.huawei.com/')).assertFalse();
      expect(WebKernelService.needsCompatibleMobileUserAgent('https://evilgoogle.com/')).assertFalse();
      expect(WebKernelService.needsCompatibleMobileUserAgent('https://google.com.evil.com/')).assertFalse();
      expect(WebKernelService.needsCompatibleMobileUserAgent('')).assertFalse();

      const googleUa6: string = WebKernelService.userAgentFor(false, stock6, 'https://www.google.com/search?q=test');
      expect(googleUa6).assertContain('Linux; Android 10; K');
      expect(googleUa6).assertContain('Chrome/141.0.7390.55');
      expect(googleUa6).assertContain('Mobile Safari/537.36');
      expect(googleUa6.includes('OpenHarmony')).assertFalse();
      expect(googleUa6.includes('ArkWeb')).assertFalse();

      const googleUa5: string = WebKernelService.userAgentFor(false, stock5, 'https://google.com/');
      expect(googleUa5).assertContain('Linux; Android 10; K');
      expect(googleUa5).assertContain('Chrome/132.0.0.0');
      expect(googleUa5).assertContain('Mobile Safari/537.36');
      expect(googleUa5.includes('OpenHarmony')).assertFalse();

      expect(WebKernelService.userAgentFor(false, stock6, 'https://www.zhihu.com/')).assertEqual(stock6);

      const desktopGoogleUa: string = WebKernelService.userAgentFor(true, stock6, 'https://www.google.com/');
      expect(desktopGoogleUa).assertContain('X11; Linux x86_64');
      expect(desktopGoogleUa).assertContain('Chrome/141.0.7390.55');
      const desktopLegacyUa: string = WebKernelService.userAgentFor(true, stock5, 'https://www.zhihu.com/');
      expect(desktopLegacyUa).assertContain('X11; Linux x86_64');
      expect(desktopLegacyUa).assertContain('Chrome/132.0.0.0');
    });

    it('resolves desktop right-click targets, file selector limits, and bounded zoom percentages', 0, (): void => {
      const linkTarget = WebKernelService.resolveContextMenuTarget('https://example.com/a', '', false, 'Link');
      expect(linkTarget?.kind).assertEqual(WebLongPressKind.Link);
      expect(linkTarget?.url).assertEqual('https://example.com/a');

      const imageTarget = WebKernelService.resolveContextMenuTarget('', 'https://cdn.example/a.png', true, '');
      expect(imageTarget?.kind).assertEqual(WebLongPressKind.Image);
      expect(imageTarget?.url).assertEqual('https://cdn.example/a.png');

      expect(WebKernelService.resolveContextMenuTarget('javascript:void(0)', '', false, '') === undefined).assertTrue();
      expect(WebKernelService.resolveFileSelectorMaxCount(0)).assertEqual(1);
      expect(WebKernelService.resolveFileSelectorMaxCount(1)).assertEqual(50);

      expect(WebKernelService.stepSiteZoomPercent(100, 10)).assertEqual(110);
      expect(WebKernelService.stepSiteZoomPercent(200, 10)).assertEqual(200);
      expect(WebKernelService.stepSiteZoomPercent(50, -10)).assertEqual(50);
      expect(WebKernelService.stepSiteZoomPercent(Number.NaN, -10)).assertEqual(90);
    });
  });
}
