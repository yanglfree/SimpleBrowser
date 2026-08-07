import { webview } from '@kit.ArkWeb';
import { BrowserTab, WebDarkModePreference } from '../models/BrowserModels';
import { AdsBlockService } from '../services/AdsBlockService';
import { WebKernelCallbacks, WebKernelService } from '../services/WebKernelService';
import { Logger } from '../utils/Logger';
import { AppIcon, IconName } from './AppIcon';

const TAG: string = 'BrowserWebView';
const EDGE_NAV_WIDTH: number = 28;
const EDGE_NAV_THRESHOLD: number = 56;
const EDGE_NAV_MAX_DISTANCE: number = 76;
/** net::ERR_ABORTED — a load that was replaced, not one that failed. */
const ERR_ABORTED: number = -3;

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
  @Prop gesturesEnabled: boolean = true;
  @Prop minimumFontSize: number = 14;
  @Prop initialZoomPercent: number = 100;
  @Prop webDarkMode: WebDarkModePreference = WebDarkModePreference.System;
  @Prop darkModeExcluded: boolean = false;
  controller: webview.WebviewController = new webview.WebviewController();
  @State private pullDistance: number = 0;
  @State private edgeBackDistance: number = 0;
  @State private edgeForwardDistance: number = 0;
  private adsBlockService: AdsBlockService = new AdsBlockService();
  onTitleReceive: (title: string) => void = (_title: string): void => {};
  onScroll: (offsetY: number) => void = (_offsetY: number): void => {};
  onKeyboardAttach: () => void = (): void => {};
  onPullRefresh: () => void = (): void => {};
  onEdgeBack: () => void = (): void => {};
  onEdgeForward: () => void = (): void => {};
  onAdsBlocked: (urls: string[]) => void = (_urls: string[]): void => {};
  onScaleChange: (scale: number) => void = (_scale: number): void => {};
  onLongPress: () => void = (): void => {};
  onPermissionRequest: (event: OnPermissionRequestEvent) => void =
    (_event: OnPermissionRequestEvent): void => {};
  onGeolocationShow: (event: OnGeolocationShowEvent) => void =
    (_event: OnGeolocationShowEvent): void => {};
  onPasswordFieldFocus: () => void = (): void => {};
  private securityBridge: DolphinSecurityBridge = new DolphinSecurityBridge();

  build() {
    Stack({ alignContent: Alignment.Top }) {
      Web({ src: this.tab.url, controller: this.controller, incognitoMode: this.tab.isPrivate })
      .javaScriptAccess(true)
      .domStorageAccess(true)
      .onlineImageAccess(true)
      .imageAccess(true)
      .zoomAccess(true)
      .minFontSize(this.minimumFontSize)
      .initialScale(this.initialZoomPercent)
      .darkMode(this.webDarkModeValue())
      .forceDarkAccess(this.shouldForceDark())
      .backgroundColor($r('app.color.content_background'))
      .width('100%')
      .height('100%')
      .onControllerAttached(() => {
        this.adsBlockService.configure(this.controller, this.blockAds);
        WebKernelService.applyUserAgent(this.controller, this.tab.isDesktop);
        this.registerSecurityBridge();
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
      .onScaleChange((event: OnScaleChangeEvent) => this.onScaleChange(event.newScale))
      .onAdsBlocked((details: AdsBlockedDetails) => this.onAdsBlocked(details.adsBlocked))
      .onPermissionRequest((event: OnPermissionRequestEvent) => this.onPermissionRequest(event))
      .onGeolocationShow((event: OnGeolocationShowEvent) => this.onGeolocationShow(event))
      .onErrorReceive((event: OnErrorReceiveEvent) => {
        const code: number = event.error.getErrorCode();
        const message: string = event.error.getErrorInfo();
        // ArkWeb reports every failed resource here — images, XHR, iframes, and
        // anything the blocker cancelled. Only the main document failing means
        // the page failed; treating a subresource as fatal replaces a perfectly
        // readable page with the error view.
        if (!event.request.isMainFrame()) {
          Logger.debug(TAG, `Subresource error ${code}: ${message}`);
          return;
        }
        if (code === ERR_ABORTED) {
          // A load the user or a redirect superseded; the replacement is already
          // on its way.
          return;
        }
        Logger.warn(TAG, `Load error ${code}: ${message}`);
        this.kernelCallbacks.onError(code, message);
      })
      .onSslErrorEventReceive((event: OnSslErrorEventReceiveEvent) => {
        const chain: Array<Uint8Array> = event.certChainData ?? [];
        Logger.warn(TAG, `SSL error ${event.error} on ${this.tab.url}`);
        this.kernelCallbacks.onSslError(event.error, chain);
      })
      .parallelGesture(
        PanGesture({ direction: PanDirection.Vertical, distance: 8 })
          .onActionUpdate((event: GestureEvent) => this.updatePullDistance(event))
          .onActionEnd((_event: GestureEvent) => this.finishPull())
          .onActionCancel(() => this.cancelPull())
      )
      .gesture(
        LongPressGesture({ repeat: false, duration: 500 })
          .onAction(() => this.onLongPress())
      )

      if (this.gesturesEnabled) {
        this.EdgeRail(true)
        this.EdgeRail(false)
      }

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

  private webDarkModeValue(): WebDarkMode {
    if (this.darkModeExcluded || this.webDarkMode === WebDarkModePreference.Light) {
      return WebDarkMode.Off;
    }
    if (this.webDarkMode === WebDarkModePreference.Dark) {
      return WebDarkMode.On;
    }
    return WebDarkMode.Auto;
  }

  private registerSecurityBridge(): void {
    this.securityBridge.onPasswordFocus = (): void => this.onPasswordFieldFocus();
    this.controller.registerJavaScriptProxy(
      this.securityBridge,
      'dolphinSecurity',
      ['notifyPasswordFocus'],
      ['notifyPasswordFocus']
    );
    Logger.info(TAG, 'Security bridge registered');
  }

  private shouldForceDark(): boolean {
    return !this.darkModeExcluded && this.webDarkMode !== WebDarkModePreference.Light;
  }

  @Builder
  private EdgeRail(isBack: boolean) {
    Row() {
      if (this.edgeDistance(isBack) > 0) {
        AppIcon({
          name: isBack ? IconName.ChevronLeft : IconName.ChevronRight,
          glyphSize: 21,
          color: this.edgeDistance(isBack) >= EDGE_NAV_THRESHOLD && this.canNavigate(isBack)
            ? $r('app.color.accent')
            : $r('app.color.text_secondary')
        })
      }
    }
    .width(EDGE_NAV_WIDTH)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .align(isBack ? Alignment.TopStart : Alignment.TopEnd)
    .translate({
      x: isBack ? this.edgeBackDistance * 0.55 : -this.edgeForwardDistance * 0.55
    })
    .gesture(
      PanGesture({ direction: PanDirection.Horizontal, distance: 6 })
        .onActionUpdate((event: GestureEvent) => this.updateEdgeDistance(isBack, event))
        .onActionEnd((_event: GestureEvent) => this.finishEdgeNavigation(isBack))
        .onActionCancel(() => this.cancelEdgeNavigation(isBack))
    )
  }

  private canNavigate(isBack: boolean): boolean {
    return isBack ? this.tab.canGoBack : this.tab.canGoForward;
  }

  private edgeDistance(isBack: boolean): number {
    return isBack ? this.edgeBackDistance : this.edgeForwardDistance;
  }

  private updateEdgeDistance(isBack: boolean, event: GestureEvent): void {
    const travel: number = isBack
      ? Math.max(0, event.offsetX)
      : Math.max(0, -event.offsetX);
    const distance: number = this.canNavigate(isBack)
      ? Math.min(EDGE_NAV_MAX_DISTANCE, travel)
      : Math.min(18, travel * 0.25);
    if (isBack) {
      this.edgeBackDistance = distance;
    } else {
      this.edgeForwardDistance = distance;
    }
  }

  private finishEdgeNavigation(isBack: boolean): void {
    const distance: number = isBack ? this.edgeBackDistance : this.edgeForwardDistance;
    const shouldNavigate: boolean = distance >= EDGE_NAV_THRESHOLD && this.canNavigate(isBack);
    this.cancelEdgeNavigation(isBack);
    if (shouldNavigate) {
      if (isBack) {
        this.onEdgeBack();
      } else {
        this.onEdgeForward();
      }
    }
  }

  private cancelEdgeNavigation(isBack: boolean): void {
    if (isBack) {
      this.edgeBackDistance = 0;
    } else {
      this.edgeForwardDistance = 0;
    }
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

/** JS side of the security bridge; ArkWeb calls notifyPasswordFocus from page scripts. */
class DolphinSecurityBridge {
  onPasswordFocus: () => void = (): void => {};

  notifyPasswordFocus(): void {
    this.onPasswordFocus();
  }
}
