import { webview } from '@kit.ArkWeb';
import { BrowserTab } from '../models/BrowserModels';
import { AdsBlockService } from '../services/AdsBlockService';
import { WebKernelCallbacks, WebKernelService } from '../services/WebKernelService';
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
  @Prop kernelCallbacks: WebKernelCallbacks;
  @Prop isAtTop: boolean = false;
  controller: webview.WebviewController = new webview.WebviewController();
  @State private pullDistance: number = 0;
  private adsBlockService: AdsBlockService = new AdsBlockService();
  onTitleReceive: (title: string) => void = (_title: string): void => {};
  onScroll: (offsetY: number) => void = (_offsetY: number): void => {};
  onKeyboardAttach: () => void = (): void => {};
  onPullRefresh: () => void = (): void => {};
  onAdsBlocked: (urls: string[]) => void = (_urls: string[]): void => {};

  build() {
    Stack({ alignContent: Alignment.Top }) {
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
      .onPageBegin((event: OnPageBeginEvent) => this.kernelCallbacks.onPageBegin(event.url))
      .onPageEnd((event: OnPageEndEvent) => this.kernelCallbacks.onPageEnd(event.url))
      .onProgressChange((event: OnProgressChangeEvent) =>
        this.kernelCallbacks.onProgressChange(event.newProgress))
      .onInterceptRequest((event: OnInterceptRequestEvent): WebResourceResponse | null =>
        this.adsBlockService.interceptRequest(event.request, this.tab.url, this.blockAds))
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
        this.kernelCallbacks.onError(code, message);
      })
      .parallelGesture(
        PanGesture({ direction: PanDirection.Vertical, distance: 8 })
          .onActionUpdate((event: GestureEvent) => this.updatePullDistance(event))
          .onActionEnd((_event: GestureEvent) => this.finishPull())
          .onActionCancel(() => this.cancelPull())
      )

      if (this.pullDistance > 0) {
        Row({ space: 8 }) {
          if (this.pullDistance >= 64) {
            Text($r('app.string.release_to_refresh'))
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
          } else {
            Text($r('app.string.pull_to_refresh'))
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
          }
        }
        .width('100%')
        .height(40)
        .justifyContent(FlexAlign.Center)
        .backgroundColor($r('app.color.surface_subtle'))
        .translate({ y: Math.min(40, this.pullDistance * 0.45) })
      }
    }
      .width('100%')
      .height('100%')
  }

  private updatePullDistance(event: GestureEvent): void {
    if (!this.isAtTop || this.tab.isLoading || event.offsetY <= 0 ||
      Math.abs(event.offsetY) < Math.abs(event.offsetX)) {
      this.pullDistance = 0;
      return;
    }
    this.pullDistance = Math.min(92, event.offsetY);
  }

  private finishPull(): void {
    const shouldRefresh: boolean = this.pullDistance >= 64 && this.isAtTop && !this.tab.isLoading;
    this.pullDistance = 0;
    if (shouldRefresh) {
      this.onPullRefresh();
    }
  }

  private cancelPull(): void {
    this.pullDistance = 0;
  }
}
