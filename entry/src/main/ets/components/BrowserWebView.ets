import { webview } from '@kit.ArkWeb';
import { BrowserTab } from '../models/BrowserModels';
import { AdsBlockService } from '../services/AdsBlockService';
import { WebKernelService } from '../services/WebKernelService';
import { Logger } from '../utils/Logger';

const TAG: string = 'BrowserWebView';

/**
 * Thin wrapper around ArkWeb. It reports events upwards and owns no policy —
 * script injection and statistics live in the page so there is a single place
 * that decides what happens after a load.
 */
@Component
export struct BrowserWebView {
  @Prop tab: BrowserTab;
  @Prop blockAds: boolean;
  controller: webview.WebviewController = new webview.WebviewController();
  private adsBlockService: AdsBlockService = new AdsBlockService();
  onPageBegin: (url: string) => void = (_url: string): void => {};
  onPageEnd: (url: string) => void = (_url: string): void => {};
  onTitleReceive: (title: string) => void = (_title: string): void => {};
  onProgressChange: (progress: number) => void = (_progress: number): void => {};
  onScroll: (offsetY: number) => void = (_offsetY: number): void => {};
  onKeyboardAttach: () => void = (): void => {};
  onAdsBlocked: (urls: string[]) => void = (_urls: string[]): void => {};
  onError: (code: number, message: string) => void = (_code: number, _message: string): void => {};

  build() {
    Web({ src: this.tab.url, controller: this.controller })
      .javaScriptAccess(true)
      .domStorageAccess(true)
      .onlineImageAccess(true)
      .imageAccess(true)
      .zoomAccess(true)
      .darkMode(WebDarkMode.Auto)
      .forceDarkAccess(true)
      .backgroundColor($r('app.color.content_background'))
      .width('100%')
      .height('100%')
      .onControllerAttached(() => {
        this.adsBlockService.configure(this.controller, this.blockAds);
        WebKernelService.applyUserAgent(this.controller, this.tab.isDesktop);
      })
      .onPageBegin((event: OnPageBeginEvent) => this.onPageBegin(event.url))
      .onPageEnd((event: OnPageEndEvent) => this.onPageEnd(event.url))
      .onProgressChange((event: OnProgressChangeEvent) => this.onProgressChange(event.newProgress))
      .onScroll((event: OnScrollEvent) => this.onScroll(event.yOffset))
      .onInterceptKeyboardAttach((_info: WebKeyboardCallbackInfo): WebKeyboardOptions => {
        this.onKeyboardAttach();
        return { useSystemKeyboard: true };
      })
      .onTitleReceive((event: OnTitleReceiveEvent) => this.onTitleReceive(event.title))
      .onAdsBlocked((details: AdsBlockedDetails) => this.onAdsBlocked(details.adsBlocked))
      .onErrorReceive((event: OnErrorReceiveEvent) => {
        const code: number = event.error.getErrorCode();
        const message: string = event.error.getErrorInfo();
        Logger.warn(TAG, `Load error ${code}: ${message}`);
        this.onError(code, message);
      })
  }
}
