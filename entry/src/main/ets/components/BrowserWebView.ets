import { webview } from '@kit.ArkWeb';
import { BrowserTab } from '../models/BrowserModels';
import { AdsBlockService } from '../services/AdsBlockService';
import { UserAgentService } from '../services/UserAgentService';
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
  onAdsBlocked: (urls: string[]) => void = (_urls: string[]): void => {};

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
        UserAgentService.apply(this.controller, this.tab.isDesktop);
      })
      .onPageBegin((event: OnPageBeginEvent) => this.onPageBegin(event.url))
      .onPageEnd((event: OnPageEndEvent) => this.onPageEnd(event.url))
      .onProgressChange((event: OnProgressChangeEvent) => this.onProgressChange(event.newProgress))
      .onTitleReceive((event: OnTitleReceiveEvent) => this.onTitleReceive(event.title))
      .onAdsBlocked((details: AdsBlockedDetails) => this.onAdsBlocked(details.adsBlocked))
      .onErrorReceive((event: OnErrorReceiveEvent) => {
        Logger.warn(TAG, `Load error ${event.error.getErrorCode()} for ${this.tab.url}`);
      })
  }
}
