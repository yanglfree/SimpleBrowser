import { webview } from '@kit.ArkWeb';
import {
  CONTENT_CLEANUP_SCRIPT,
  DARK_MODE_SCRIPT,
  DESKTOP_USER_AGENT,
  LIGHT_MODE_SCRIPT
} from '../constants/AppConstants';
import { BrowserTab } from '../models/BrowserModels';
import { AdsBlockService } from '../services/AdsBlockService';
import { Logger } from '../utils/Logger';

const TAG: string = 'BrowserWebView';

@Component
export struct BrowserWebView {
  @Prop tab: BrowserTab;
  @Prop isAdsBlockingEnabled: boolean;
  @Prop isDarkModeEnabled: boolean;
  @Prop isDesktopModeEnabled: boolean;
  controller: webview.WebviewController = new webview.WebviewController();
  private adsBlockService: AdsBlockService = new AdsBlockService();
  onPageBegin: (url: string) => void = (_url: string): void => {};
  onPageEnd: (url: string) => void = (_url: string): void => {};
  onTitleReceive: (title: string) => void = (_title: string): void => {};
  onProgressChange: (progress: number) => void = (_progress: number): void => {};
  onAdsBlocked: (count: number) => void = (_count: number): void => {};

  build() {
    Web({ src: this.tab.url, controller: this.controller })
      .javaScriptAccess(true)
      .domStorageAccess(true)
      .onlineImageAccess(true)
      .imageAccess(true)
      .zoomAccess(true)
      .userAgent(this.isDesktopModeEnabled ? DESKTOP_USER_AGENT : '')
      .backgroundColor($r('app.color.page_background'))
      .onAppear(() => this.configureAds())
      .onPageBegin((event: OnPageBeginEvent) => this.handlePageBegin(event.url))
      .onPageEnd((event: OnPageEndEvent) => this.handlePageEnd(event.url))
      .onProgressChange((event: OnProgressChangeEvent) => this.onProgressChange(event.newProgress))
      .onTitleReceive((event: OnTitleReceiveEvent) => this.onTitleReceive(event.title))
      .onAdsBlocked((details: AdsBlockedDetails) => this.onAdsBlocked(details.adsBlocked.length))
  }

  private configureAds(): void {
    this.adsBlockService.configure(this.controller, this.isAdsBlockingEnabled);
  }

  private handlePageBegin(url: string): void {
    this.onPageBegin(url);
  }

  private handlePageEnd(url: string): void {
    this.onPageEnd(url);
    this.applyPageEnhancements();
  }

  private async applyPageEnhancements(): Promise<void> {
    try {
      await this.controller.runJavaScript(CONTENT_CLEANUP_SCRIPT);
      await this.controller.runJavaScript(this.isDarkModeEnabled ? DARK_MODE_SCRIPT : LIGHT_MODE_SCRIPT);
    } catch (error) {
      Logger.warn(TAG, `Page enhancement skipped: ${String(error)}`);
    }
  }
}
