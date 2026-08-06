import { webview } from '@kit.ArkWeb';

import { image } from '@kit.ImageKit';
import {
  DESKTOP_VIEWPORT_SCRIPT,
  HOME_URL,
  READER_EXIT_SCRIPT,
  READ_FAVICON_SCRIPT,
  READ_SCROLL_POSITION_SCRIPT,
  READER_FONT_MAX,
  READER_FONT_MIN,
  READER_FONT_STEP,
  RESTORE_HIDDEN_SCRIPT,
  TRACKER_BLOCK_SCRIPT,
  contentCleanupScript,
  readerApplyScript,
  restoreScrollPositionScript
} from '../constants/AppConstants';
import {
  BlockStats,
  BrowserSettings,
  BrowserTab,
  QuickSite,
  ReaderPaper,
  RuleStrength,
  Suggestion,
  LoadErrorKind,
  SecurityState,
  cloneSettings,
  cloneTab,
  defaultBrowserSettings,
  emptyBlockStats,
  totalBlocked
} from '../models/BrowserModels';
import { ActionSheet } from '../components/ActionSheet';
import { AddressSheet } from '../components/AddressSheet';
import { BlockPanel } from '../components/BlockPanel';
import { BrowserWebView } from '../components/BrowserWebView';
import { OmniCapsule } from '../components/OmniCapsule';
import { NavigationHistorySheet } from '../components/NavigationHistorySheet';
import { ReaderBar, nextLineHeight } from '../components/ReaderBar';
import { SettingsPage } from '../components/SettingsPage';
import { SecurityPanel } from '../components/SecurityPanel';
import { StartPage } from '../components/StartPage';
import { TabLauncher } from '../components/TabLauncher';
import { TabOverview, TabThumbnail } from '../components/TabOverview';
import { TAB_LAUNCHER_RIGHT_MARGIN, TAB_LAUNCHER_TOP_MARGIN, TAB_WEB_BOTTOM_INSET } from '../components/TabTokens';
import { PrivacyService } from '../services/PrivacyService';
import { ShareService, ShareOutcome } from '../services/ShareService';
import { ThemeService } from '../services/ThemeService';
import { WebHistoryEntry, WebKernelService } from '../services/WebKernelService';
import { AppContext } from '../utils/AppContext';
import { displayHost, isHomeUrl, isTrackerUrl, normalizeAddress } from '../utils/UrlUtils';
import { Logger } from '../utils/Logger';
import { BrowserViewModel } from '../viewmodels/BrowserViewModel';

const TAG: string = 'Index';

enum Overlay {
  None = 0,
  Actions = 1,
  Address = 2,
  Tabs = 3,
  Block = 4,
  Settings = 5,
  Security = 6,
  NavigationHistory = 7
}

/** Shape of the JSON the injected cleanup/tracker passes hand back. */
interface CleanupResult {
  ads?: number;
  trackers?: number;
  popups?: number;
  cookieBanners?: number;
}

interface ReaderPalette {
  background: string;
  body: string;
  title: string;
}

const READER_PALETTES: ReaderPalette[] = [
  { background: '#FFFFFF', body: '#3A3934', title: '#1A1A18' },
  { background: '#F1EFEA', body: '#3A3934', title: '#1A1A18' },
  { background: '#26251F', body: '#C9C6BE', title: '#F5F3EE' }
];

const ACCENT_HEX: string = '#2E6B5C';

@Entry
@Component
struct Index {
  private viewModel: BrowserViewModel = new BrowserViewModel();
  private controllers: Map<string, webview.WebviewController> = new Map();
  @State private isReady: boolean = false;
  @State private hasError: boolean = false;
  @State private tabs: BrowserTab[] = [];
  @State private activeTabId: string = '';
  @State private settings: BrowserSettings = defaultBrowserSettings();
  @State private sheet: Overlay = Overlay.None;
  @State private isCapsuleHidden: boolean = false;
  @State private suggestions: Suggestion[] = [];
  @State private quickSites: QuickSite[] = [];
  @State private weeklyBlocked: number = 0;
  @State private siteStats: BlockStats = emptyBlockStats();
  @State private isSiteAllowed: boolean = false;
  @State private isActiveBookmarked: boolean = false;
  @State private thumbnails: TabThumbnail[] = [];
  @State private backHistory: WebHistoryEntry[] = [];
  private pageScrollOffsets: Map<string, number> = new Map();

  async aboutToAppear(): Promise<void> {
    try {
      await this.viewModel.initialize(AppContext.getContext());
      ThemeService.apply(AppContext.getContext(), this.viewModel.settings.appearance);
      this.syncState();
      this.isReady = true;
    } catch (error) {
      Logger.error(TAG, `Failed to initialize browser: ${String(error)}`);
      this.hasError = true;
    }
  }

  onBackPress(): boolean {
    if (this.sheet !== Overlay.None) {
      this.sheet = Overlay.None;
      return true;
    }
    const tab: BrowserTab | undefined = this.activeTab();
    if (tab !== undefined && tab.isReader) {
      void this.exitReader(tab.id);
      return true;
    }
    if (tab !== undefined && tab.canGoBack) {
      this.runOnActive((controller: webview.WebviewController) => controller.backward());
      return true;
    }
    if (tab !== undefined && !isHomeUrl(tab.url)) {
      this.goHome(tab.id);
      return true;
    }
    return false;
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      this.ContentLayer()

      if (this.isReady && !this.hasError) {
        this.CapsuleLayer()
        this.OverlayLayer()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }

  // ---------------------------------------------------------------- content

  @Builder
  private ContentLayer() {
    Column() {
      this.ProgressBar()

      if (this.hasError) {
        this.ErrorView()
      } else if (!this.isReady) {
        this.LoadingView()
      } else {
        if (this.isActiveReader()) {
          ReaderBar({
            paper: this.settings.readerPaper,
            canShrink: this.settings.readerFontSize > READER_FONT_MIN,
            canGrow: this.settings.readerFontSize < READER_FONT_MAX,
            onShrink: (): void => this.stepReaderFont(-READER_FONT_STEP),
            onGrow: (): void => this.stepReaderFont(READER_FONT_STEP),
            onCycleLineHeight: (): void => this.cycleReaderLineHeight(),
            onPickPaper: (paper: ReaderPaper): void => this.pickReaderPaper(paper),
            onDone: (): void => { void this.exitReader(this.activeTabId); }
          })
        }
        if (this.activeTab()?.loadError !== LoadErrorKind.None) {
          this.PageErrorView()
        } else {
          this.TabStack()
        }
      }
    }
    .width('100%')
    .height('100%')
  }

  /** Two vertical pixels of ink green under the status bar — nothing else. */
  @Builder
  private ProgressBar() {
    Row() {
      Row()
        .width(`${this.activeTab()?.progress ?? 0}%`)
        .height(2)
        .backgroundColor($r('app.color.accent'))
        .borderRadius({ topRight: 1, bottomRight: 1 })
    }
    .width('100%')
    .height(2)
    .visibility(this.activeTab()?.isLoading === true ? Visibility.Visible : Visibility.Hidden)
  }

  /**
   * Every tab stays mounted and is merely hidden, so switching keeps scroll
   * position and page state — and so a snapshot can be taken on the way out.
   */
  @Builder
  private TabStack() {
    Stack({ alignContent: Alignment.TopEnd }) {
      ForEach(this.tabs, (tab: BrowserTab) => {
        Column() {
          if (isHomeUrl(tab.url)) {
            StartPage({
              quickSites: this.quickSites,
              weeklyBlocked: this.weeklyBlocked,
              onOpenAddress: (): void => this.openAddress(),
              onOpenSite: (url: string): void => this.navigateTo(url),
              onOpenStats: (): void => { this.sheet = Overlay.Settings; }
            })
          } else {
            BrowserWebView({
              tab: tab,
              blockAds: this.settings.blockAds && !this.viewModel.isHostAllowed(tab.url),
              controller: this.controllerFor(tab.id),
              onPageBegin: (url: string): void => this.handlePageBegin(tab.id, url),
              onPageEnd: (url: string): void => { this.handlePageEnd(tab.id, url); },
              onTitleReceive: (title: string): void => this.handleTitle(tab.id, title),
              onProgressChange: (progress: number): void => this.handleProgress(tab.id, progress),
              onScroll: (offsetY: number): void => this.handlePageScroll(tab.id, offsetY),
              onKeyboardAttach: (): void => { this.showCapsule(); },
              onAdsBlocked: (urls: string[]): void => { this.handleAdsBlocked(tab.id, urls); },
              onError: (code: number, message: string): void => this.handleLoadError(tab.id, code, message)
            })
          }
        }
        .id(`tab-view-${tab.id}`)
        .width('100%')
        .height('100%')
        .padding({ bottom: isHomeUrl(tab.url) ? 0 : TAB_WEB_BOTTOM_INSET })
        .visibility(tab.id === this.activeTabId ? Visibility.Visible : Visibility.Hidden)
      }, (tab: BrowserTab) => `${tab.id}-${isHomeUrl(tab.url) ? 'home' : 'web'}`)

      if (this.sheet === Overlay.None && this.isActiveHome()) {
        TabLauncher({
          count: this.tabs.length,
          onOpen: (): void => { this.openTabs(); }
        })
          .margin({ top: TAB_LAUNCHER_TOP_MARGIN, right: TAB_LAUNCHER_RIGHT_MARGIN })
      }
    }
    .layoutWeight(1)
    .width('100%')
  }

  @Builder
  private LoadingView() {
    Column() {
      LoadingProgress()
        .width(38)
        .height(38)
        .color($r('app.color.text_secondary'))
    }
    .layoutWeight(1)
    .width('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  private ErrorView() {
    Column({ space: 16 }) {
      Text($r('app.string.initialization_error'))
        .fontSize(16)
        .fontColor($r('app.color.text_primary'))
      Text($r('app.string.retry'))
        .fontSize(15)
        .fontColor($r('app.color.accent'))
        .onClick(() => this.retry())
    }
    .layoutWeight(1)
    .width('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  private PageErrorView() {
    Column({ space: 16 }) {
      Text(this.errorTitle())
        .fontSize(19)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
      Text(this.errorMessage())
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
        .padding({ left: 28, right: 28 })
      Row({ space: 12 }) {
        Text($r('app.string.retry'))
          .fontSize(15)
          .fontColor($r('app.color.accent'))
          .onClick(() => this.retryPage())
        if (this.activeTab()?.loadError === LoadErrorKind.Certificate) {
          Text($r('app.string.certificate_details'))
            .fontSize(15)
            .fontColor($r('app.color.text_secondary'))
            .onClick(() => this.openSecurityDetails())
        }
      }
    }
    .layoutWeight(1)
    .width('100%')
    .justifyContent(FlexAlign.Center)
  }

  // ---------------------------------------------------------------- capsule

  @Builder
  private CapsuleLayer() {
    if (this.sheet === Overlay.None && this.isActiveHome()) {
      // The start page shows no capsule, but it keeps its bottom-edge gesture so
      // the tab overview stays reachable from a freshly opened tab.
      Row()
        .width('100%')
        .height(28)
        .gesture(
          PanGesture({ direction: PanDirection.Up, distance: 12 })
            .onActionEnd(() => { this.openTabs(); })
        )
    } else if (this.sheet === Overlay.None) {
      if (this.isCapsuleHidden && this.activeTab()?.isLoading !== true) {
        // Swipe up from the bottom edge to bring the capsule back.
        Row()
          .width('100%')
          .height(28)
          .gesture(
            PanGesture({ direction: PanDirection.Up, distance: 8 })
              .onActionEnd(() => { this.isCapsuleHidden = false; })
          )
      } else {
        Row({ space: 8 }) {
          TabLauncher({
            count: this.tabs.length,
            onOpen: (): void => { this.openTabs(); }
          })
          OmniCapsule({
            host: displayHost(this.activeTab()?.url ?? ''),
            blockedCount: totalBlocked(this.activeTab()?.blocked ?? emptyBlockStats()),
            isPrivate: this.activeTab()?.isPrivate === true,
            securityState: this.activeTab()?.securityState ?? SecurityState.Unknown,
            gesturesEnabled: this.settings.gesturesEnabled,
            actionsGestureEnabled: this.settings.gesturesEnabled && this.settings.gestureActionsEnabled,
            tabSwitchGestureEnabled: this.settings.gesturesEnabled && this.settings.gestureTabSwitchEnabled,
            blockingGestureEnabled: this.settings.gesturesEnabled && this.settings.gestureBlockingEnabled,
            onTap: (): void => this.openAddress(),
            onSecurityTap: (): void => this.openSecurityDetails(),
            onLongPress: (): void => this.openBlockPanel(),
            onSwipeUp: (): void => { this.sheet = Overlay.Actions; },
            onSwipeDown: (): void => {
              if (this.settings.autoHideToolbarEnabled) {
                this.isCapsuleHidden = true;
              }
            },
            onSwipeLeft: (): void => { this.switchNeighbour(1); },
            onSwipeRight: (): void => { this.switchNeighbour(-1); }
          })
        }
          .margin({ bottom: 46 })
          .transition(TransitionEffect.OPACITY.animation({ duration: 200 })
            .combine(TransitionEffect.translate({ y: 40 })))
      }
    }
  }

  // --------------------------------------------------------------- overlays

  @Builder
  private OverlayLayer() {
    if (this.sheet === Overlay.Actions) {
      ActionSheet({
        host: displayHost(this.activeTab()?.url ?? ''),
        blockedCount: totalBlocked(this.activeTab()?.blocked ?? emptyBlockStats()),
        canGoBack: this.activeTab()?.canGoBack === true,
        canGoForward: this.activeTab()?.canGoForward === true,
        isLoading: this.activeTab()?.isLoading === true,
        isBookmarked: this.isActiveBookmarked,
        isReader: this.isActiveReader(),
        isDesktop: this.activeTab()?.isDesktop === true,
        onDismiss: (): void => { this.sheet = Overlay.None; },
        onEscalate: (): void => { this.openTabs(); },
        onBackLongPress: (): void => { this.openBackHistory(); },
        onReloadLongPress: (): void => { this.forceReload(); },
        onAction: (key: string): void => { this.performAction(key); }
      })
        .transition(this.sheetTransition())
    } else if (this.sheet === Overlay.Address) {
      AddressSheet({
        suggestions: this.suggestions,
        currentHost: displayHost(this.activeTab()?.url ?? ''),
        initialText: this.isActiveHome() ? '' : (this.activeTab()?.url ?? ''),
        onQueryChange: (query: string): void => this.updateSuggestions(query),
        onSubmit: (query: string): void => this.submitAddress(query),
        onPick: (url: string): void => this.submitAddress(url),
        onDismiss: (): void => { this.sheet = Overlay.None; }
      })
        .transition(this.sheetTransition())
    } else if (this.sheet === Overlay.Tabs) {
      TabOverview({
        tabs: this.tabs,
        activeTabId: this.activeTabId,
        thumbnails: this.thumbnails,
        onSelect: (id: string): void => { this.selectTab(id); },
        onClose: (id: string): void => this.closeTab(id),
        onCloseAll: (): void => this.closeAllTabs(),
        onNewTab: (): void => this.createTab(false),
        onNewPrivateTab: (): void => this.createTab(true)
      })
        .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
    } else if (this.sheet === Overlay.Block) {
      BlockPanel({
        host: displayHost(this.activeTab()?.url ?? ''),
        stats: this.siteStats,
        isDisabledForSite: this.isSiteAllowed,
        onDismiss: (): void => { this.sheet = Overlay.None; },
        onToggleSite: (): void => { this.toggleSiteBlocking(); },
        onOpenSettings: (): void => { this.sheet = Overlay.Settings; }
      })
        .transition(this.sheetTransition())
    } else if (this.sheet === Overlay.Settings) {
      SettingsPage({
        settings: this.settings,
        allowedHosts: this.viewModel.getAllowedHosts(),
        onChange: (settings: BrowserSettings): void => { this.applySettings(settings); },
        onResetGestures: (): void => { this.resetGestures(); },
        onClearData: (): void => { this.clearBrowsingData(); },
        onRemoveAllowedHost: (host: string): void => { void this.removeAllowedHost(host); },
        onBack: (): void => { this.sheet = Overlay.None; }
      })
        .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
    } else if (this.sheet === Overlay.Security) {
      SecurityPanel({
        host: displayHost(this.activeTab()?.url ?? ''),
        url: this.activeTab()?.url ?? '',
        state: this.activeTab()?.securityState ?? SecurityState.Unknown,
        onDismiss: (): void => { this.sheet = Overlay.None; }
      })
        .transition(this.sheetTransition())
    } else if (this.sheet === Overlay.NavigationHistory) {
      NavigationHistorySheet({
        entries: this.backHistory,
        onDismiss: (): void => { this.sheet = Overlay.None; },
        onSelect: (step: number): void => { this.selectBackHistory(step); }
      })
        .transition(this.sheetTransition())
    }
  }

  private sheetTransition(): TransitionEffect {
    return TransitionEffect.OPACITY
      .animation({ duration: 260, curve: Curve.FastOutSlowIn })
      .combine(TransitionEffect.move(TransitionEdge.BOTTOM));
  }

  // ------------------------------------------------------------- navigation

  private activeTab(): BrowserTab | undefined {
    return this.tabs.find((tab: BrowserTab) => tab.id === this.activeTabId);
  }

  private isActiveHome(): boolean {
    return isHomeUrl(this.activeTab()?.url ?? HOME_URL);
  }

  private isActiveReader(): boolean {
    return this.activeTab()?.isReader === true;
  }

  private controllerFor(id: string): webview.WebviewController {
    const existing: webview.WebviewController | undefined = this.controllers.get(id);
    if (existing !== undefined) {
      return existing;
    }
    const controller: webview.WebviewController = new webview.WebviewController();
    this.controllers.set(id, controller);
    return controller;
  }

  private runOnActive(action: (controller: webview.WebviewController) => void): void {
    const controller: webview.WebviewController | undefined = this.controllers.get(this.activeTabId);
    if (controller === undefined) {
      return;
    }
    try {
      action(controller);
    } catch (error) {
      Logger.warn(TAG, `Web action failed: ${String(error)}`);
    }
  }

  private navigateTo(url: string): void {
    const tab: BrowserTab | undefined = this.activeTab();
    if (tab === undefined) {
      return;
    }
    this.sheet = Overlay.None;
    this.isCapsuleHidden = false;
    if (isHomeUrl(tab.url)) {
      // The Web component is created lazily, with the target as its initial src.
      this.viewModel.updateTab(tab.id, { url: url, isLoading: true, progress: 0 });
      this.syncState();
      return;
    }
    this.runOnActive((controller: webview.WebviewController) => controller.loadUrl(url));
  }

  private goHome(id: string): void {
    this.viewModel.updateTab(id, {
      url: HOME_URL,
      title: '',
      isLoading: false,
      progress: 0,
      isReader: false,
      canGoBack: false,
      canGoForward: false
    });
    this.controllers.delete(id);
    this.viewModel.persistSession();
    this.syncState();
  }

  private submitAddress(query: string): void {
    const target: string = normalizeAddress(
      query,
      this.settings.searchEngine,
      this.settings.customSearchTemplate
    );
    if (isHomeUrl(target)) {
      this.sheet = Overlay.None;
      return;
    }
    this.navigateTo(target);
  }

  private openAddress(): void {
    this.showCapsule();
    this.updateSuggestions(this.isActiveHome() ? '' : (this.activeTab()?.url ?? ''));
    this.sheet = Overlay.Address;
  }

  private updateSuggestions(query: string): void {
    this.suggestions = this.viewModel.getSuggestions(query);
  }

  private openBlockPanel(): void {
    const url: string = this.activeTab()?.url ?? '';
    this.siteStats = this.viewModel.getSiteBlocked(url);
    this.isSiteAllowed = this.viewModel.isHostAllowed(url);
    this.sheet = Overlay.Block;
  }

  private async openTabs(): Promise<void> {
    await this.captureThumbnail(this.activeTabId);
    this.sheet = Overlay.Tabs;
  }

  private async switchNeighbour(offset: number): Promise<void> {
    const next: string = this.viewModel.neighbourTabId(offset);
    if (next !== this.activeTabId) {
      await this.captureScrollPosition(this.activeTabId);
      await this.captureThumbnail(this.activeTabId);
      this.viewModel.selectTab(next);
      this.syncState();
    }
  }

  private async selectTab(id: string): Promise<void> {
    await this.captureScrollPosition(this.activeTabId);
    await this.captureThumbnail(this.activeTabId);
    this.viewModel.selectTab(id);
    this.sheet = Overlay.None;
    this.isCapsuleHidden = false;
    this.syncState();
  }

  private createTab(isPrivate: boolean): void {
    if (this.viewModel.isTabSoftLimitReached()) {
      try {
        this.getUIContext().getPromptAction().showToast({ message: $r('app.string.tab_soft_limit_message') });
      } catch (error) {
        Logger.warn(TAG, `Tab limit toast unavailable: ${String(error)}`);
      }
    }
    this.viewModel.addTab(HOME_URL, isPrivate);
    this.sheet = Overlay.None;
    this.isCapsuleHidden = false;
    this.syncState();
  }

  private closeTab(id: string): void {
    void this.captureScrollPosition(id);
    this.viewModel.closeTab(id);
    this.controllers.delete(id);
    this.thumbnails = this.thumbnails.filter((item: TabThumbnail) => item.id !== id);
    if (this.settings.clearCookiesOnTabClose) {
      PrivacyService.clearCookies();
    }
    this.syncState();
  }

  private closeAllTabs(): void {
    void this.captureScrollPosition(this.activeTabId);
    this.viewModel.closeAllTabs();
    this.controllers.clear();
    this.thumbnails = [];
    if (this.settings.clearCookiesOnTabClose) {
      PrivacyService.clearCookies();
    }
    this.syncState();
  }

  /** Snapshots the tab that is about to leave the screen, for the overview. */
  private async captureThumbnail(id: string): Promise<void> {
    if (id.length === 0) {
      return;
    }
    try {
      const shot: image.PixelMap =
        await this.getUIContext().getComponentSnapshot().get(`tab-view-${id}`);
      this.thumbnails = this.thumbnails
        .filter((item: TabThumbnail) => item.id !== id)
        .concat([{ id: id, shot: shot }]);
    } catch (error) {
      Logger.warn(TAG, `Snapshot unavailable for ${id}: ${String(error)}`);
    }
  }

  // ----------------------------------------------------------- sheet action

  private async performAction(key: string): Promise<void> {
    const tab: BrowserTab | undefined = this.activeTab();
    if (tab === undefined) {
      return;
    }
    if (key === 'back') {
      this.sheet = Overlay.None;
      this.runOnActive((controller: webview.WebviewController) => WebKernelService.goBack(controller));
      return;
    }
    if (key === 'forward') {
      this.sheet = Overlay.None;
      this.runOnActive((controller: webview.WebviewController) => WebKernelService.goForward(controller));
      return;
    }
    if (key === 'reload') {
      this.sheet = Overlay.None;
      this.runOnActive((controller: webview.WebviewController) =>
        tab.isLoading ? WebKernelService.stop(controller) : WebKernelService.reload(controller));
      return;
    }
    if (key === 'share') {
      this.sheet = Overlay.None;
      const outcome: ShareOutcome =
        await ShareService.share(AppContext.getContext(), tab.url, tab.title);
      if (outcome === ShareOutcome.Copied) {
        try {
          this.getUIContext().getPromptAction().showToast({ message: $r('app.string.copied_link') });
        } catch (error) {
          Logger.warn(TAG, `Toast unavailable: ${String(error)}`);
        }
      }
      return;
    }
    if (key === 'bookmark') {
      await this.viewModel.toggleBookmark(tab);
      this.isActiveBookmarked = this.viewModel.isBookmarked(tab.url);
      return;
    }
    if (key === 'reader') {
      this.sheet = Overlay.None;
      if (tab.isReader) {
        await this.exitReader(tab.id);
      } else {
        await this.enterReader(tab.id);
      }
      return;
    }
    if (key === 'desktop') {
      this.sheet = Overlay.None;
      const isDesktop: boolean = !tab.isDesktop;
      this.viewModel.updateTab(tab.id, { isDesktop: isDesktop });
      this.syncState();
      this.runOnActive((controller: webview.WebviewController) => {
        WebKernelService.applyUserAgent(controller, isDesktop);
        WebKernelService.reload(controller);
      });
    }
  }

  // ------------------------------------------------------------------ reader

  private async enterReader(id: string): Promise<void> {
    const controller: webview.WebviewController | undefined = this.controllers.get(id);
    if (controller === undefined) {
      return;
    }
    const applied: string = await this.runScript(controller, this.readerScript());
    if (applied.includes('no-article')) {
      Logger.info(TAG, 'Reader mode found no article to reflow');
      return;
    }
    this.viewModel.updateTab(id, { isReader: true });
    const tab: BrowserTab | undefined = this.viewModel.getTab(id);
    if (tab !== undefined && tab.readerScrollY > 0) {
      await this.runScript(controller, restoreScrollPositionScript(tab.readerScrollY));
    }
    this.syncState();
  }

  private async exitReader(id: string): Promise<void> {
    const controller: webview.WebviewController | undefined = this.controllers.get(id);
    if (controller !== undefined) {
      await this.captureScrollPosition(id);
      await this.runScript(controller, READER_EXIT_SCRIPT);
    }
    this.viewModel.updateTab(id, { isReader: false });
    const tab: BrowserTab | undefined = this.viewModel.getTab(id);
    if (controller !== undefined && tab !== undefined && tab.scrollY > 0) {
      await this.runScript(controller, restoreScrollPositionScript(tab.scrollY));
    }
    this.syncState();
  }

  private readerScript(): string {
    const palette: ReaderPalette = READER_PALETTES[this.settings.readerPaper as number];
    return readerApplyScript(
      this.settings.readerFontSize,
      this.settings.readerLineHeight,
      palette.background,
      palette.body,
      palette.title,
      ACCENT_HEX
    );
  }

  private stepReaderFont(delta: number): void {
    const next: BrowserSettings = cloneSettings(this.settings);
    next.readerFontSize = Math.min(READER_FONT_MAX, Math.max(READER_FONT_MIN, next.readerFontSize + delta));
    this.applyReaderSettings(next);
  }

  private cycleReaderLineHeight(): void {
    const next: BrowserSettings = cloneSettings(this.settings);
    next.readerLineHeight = nextLineHeight(next.readerLineHeight);
    this.applyReaderSettings(next);
  }

  private pickReaderPaper(paper: ReaderPaper): void {
    const next: BrowserSettings = cloneSettings(this.settings);
    next.readerPaper = paper;
    this.applyReaderSettings(next);
  }

  private async applyReaderSettings(next: BrowserSettings): Promise<void> {
    await this.viewModel.updateSettings(next);
    this.settings = cloneSettings(next);
    const controller: webview.WebviewController | undefined = this.controllers.get(this.activeTabId);
    if (controller !== undefined) {
      await this.runScript(controller, this.readerScript());
    }
  }

  // ---------------------------------------------------------------- settings

  private async applySettings(next: BrowserSettings): Promise<void> {
    const appearanceChanged: boolean = next.appearance !== this.settings.appearance;
    await this.viewModel.updateSettings(next);
    this.settings = cloneSettings(next);
    if (appearanceChanged) {
      ThemeService.apply(AppContext.getContext(), next.appearance);
    }
    this.reconfigureBlocking();
  }

  private resetGestures(): void {
    const next: BrowserSettings = cloneSettings(this.settings);
    next.gesturesEnabled = true;
    next.gestureActionsEnabled = true;
    next.gestureTabSwitchEnabled = true;
    next.gestureBlockingEnabled = true;
    void this.applySettings(next);
  }

  private async toggleSiteBlocking(): Promise<void> {
    const url: string = this.activeTab()?.url ?? '';
    const allowed: boolean = !this.isSiteAllowed;
    await this.viewModel.setHostAllowed(url, allowed);
    this.isSiteAllowed = allowed;
    this.reconfigureBlocking();
    this.runOnActive((controller: webview.WebviewController) => controller.refresh());
  }

  private async removeAllowedHost(host: string): Promise<void> {
    await this.viewModel.removeAllowedHost(host);
    this.isSiteAllowed = this.viewModel.isHostAllowed(this.activeTab()?.url ?? '');
    this.syncState();
  }

  /** Pushes the current blocking policy into every live web view. */
  private reconfigureBlocking(): void {
    for (const tab of this.tabs) {
      const controller: webview.WebviewController | undefined = this.controllers.get(tab.id);
      if (controller !== undefined) {
        const enabled: boolean = this.settings.blockAds && !this.viewModel.isHostAllowed(tab.url);
        this.viewModel.adsBlockService.configure(controller, enabled);
      }
    }
  }

  private async clearBrowsingData(): Promise<void> {
    const controllers: webview.WebviewController[] = [];
    this.controllers.forEach((controller: webview.WebviewController) => controllers.push(controller));
    PrivacyService.clearSiteData(controllers);
    await this.viewModel.clearBrowsingData();
    this.syncState();
  }

  // ------------------------------------------------------------- web events

  private handlePageBegin(id: string, url: string): void {
    this.pageScrollOffsets.set(id, 0);
    this.showCapsule();
    const current: BrowserTab | undefined = this.viewModel.getTab(id);
    const progress: number = current?.isLoading === true && current.progress > 0
      ? current.progress
      : 0;
    this.viewModel.updateTab(id, {
      url: url,
      isLoading: true,
      progress: progress,
      isReader: false,
      loadError: LoadErrorKind.None,
      securityState: Index.securityStateForUrl(url),
      lastVisitedAt: Date.now()
    });
    this.syncTab(id);
  }

  private async handlePageEnd(id: string, url: string): Promise<void> {
    this.viewModel.updateTab(id, {
      url: url,
      isLoading: false,
      progress: 100,
      loadError: LoadErrorKind.None,
      securityState: Index.securityStateForUrl(url),
      lastVisitedAt: Date.now()
    });
    this.refreshNavigationState(id);
    const tab: BrowserTab | undefined = this.viewModel.getTab(id);
    if (tab !== undefined) {
      await this.viewModel.recordPageVisit(tab);
      this.viewModel.persistSession();
      await this.restoreScrollPosition(tab);
    }
    await this.enhancePage(id);
    this.syncState();
  }

  private handleTitle(id: string, title: string): void {
    const tab: BrowserTab | undefined = this.viewModel.getTab(id);
    const fallback: string = tab === undefined ? '' : displayHost(tab.url);
    this.viewModel.updateTab(id, { title: title.length > 0 ? title : fallback });
    this.syncTab(id);
  }

  private handleProgress(id: string, progress: number): void {
    this.viewModel.updateTab(id, {
      progress: Math.min(100, Math.max(0, progress)),
      isLoading: progress < 100,
      loadError: LoadErrorKind.None
    });
    this.syncTab(id);
  }

  private handlePageScroll(id: string, offsetY: number): void {
    const tab: BrowserTab | undefined = this.viewModel.getTab(id);
    if (tab === undefined || id !== this.activeTabId || tab.isLoading ||
      !this.settings.autoHideToolbarEnabled || this.sheet !== Overlay.None) {
      return;
    }
    const previous: number = this.pageScrollOffsets.get(id) ?? offsetY;
    this.pageScrollOffsets.set(id, offsetY);
    const delta: number = offsetY - previous;
    if (offsetY <= 8 || delta < -4) {
      this.showCapsule();
    } else if (offsetY > 36 && delta > 4) {
      this.isCapsuleHidden = true;
    }
  }

  private showCapsule(): void {
    this.isCapsuleHidden = false;
  }

  private handleLoadError(id: string, code: number, message: string): void {
    const kind: LoadErrorKind = Index.errorKindFor(code, message);
    this.viewModel.updateTab(id, {
      isLoading: false,
      loadError: kind,
      securityState: kind === LoadErrorKind.Certificate
        ? SecurityState.CertificateError
        : this.viewModel.getTab(id)?.securityState ?? SecurityState.Unknown
    });
    this.syncTab(id);
  }

  private retryPage(): void {
    const tab: BrowserTab | undefined = this.activeTab();
    if (tab === undefined) {
      return;
    }
    this.viewModel.updateTab(tab.id, { loadError: LoadErrorKind.None, isLoading: true, progress: 0 });
    this.syncTab(tab.id);
    this.runOnActive((controller: webview.WebviewController) => WebKernelService.reload(controller, true));
  }

  private openSecurityDetails(): void {
    this.sheet = Overlay.Security;
  }

  private openBackHistory(): void {
    const controller: webview.WebviewController | undefined = this.controllers.get(this.activeTabId);
    if (controller === undefined) {
      return;
    }
    this.backHistory = WebKernelService.getBackHistory(controller);
    if (this.backHistory.length > 0) {
      this.sheet = Overlay.NavigationHistory;
    }
  }

  private selectBackHistory(step: number): void {
    this.sheet = Overlay.None;
    this.runOnActive((controller: webview.WebviewController) =>
      WebKernelService.goBackBySteps(controller, step));
  }

  private forceReload(): void {
    const tab: BrowserTab | undefined = this.activeTab();
    if (tab === undefined || tab.isLoading) {
      return;
    }
    this.sheet = Overlay.None;
    this.runOnActive((controller: webview.WebviewController) =>
      WebKernelService.reload(controller, true));
  }

  private errorTitle(): Resource {
    const kind: LoadErrorKind = this.activeTab()?.loadError ?? LoadErrorKind.Unknown;
    if (kind === LoadErrorKind.Offline) {
      return $r('app.string.error_offline_title');
    }
    if (kind === LoadErrorKind.Timeout) {
      return $r('app.string.error_timeout_title');
    }
    if (kind === LoadErrorKind.Dns) {
      return $r('app.string.error_dns_title');
    }
    if (kind === LoadErrorKind.Certificate) {
      return $r('app.string.error_certificate_title');
    }
    return $r('app.string.error_unknown_title');
  }

  private errorMessage(): Resource {
    const kind: LoadErrorKind = this.activeTab()?.loadError ?? LoadErrorKind.Unknown;
    if (kind === LoadErrorKind.Offline) {
      return $r('app.string.error_offline_message');
    }
    if (kind === LoadErrorKind.Timeout) {
      return $r('app.string.error_timeout_message');
    }
    if (kind === LoadErrorKind.Dns) {
      return $r('app.string.error_dns_message');
    }
    if (kind === LoadErrorKind.Certificate) {
      return $r('app.string.error_certificate_message');
    }
    return $r('app.string.error_unknown_message');
  }

  private static errorKindFor(code: number, message: string): LoadErrorKind {
    const value: string = message.toLowerCase();
    if (value.includes('certificate') || value.includes('ssl')) {
      return LoadErrorKind.Certificate;
    }
    if (value.includes('dns') || value.includes('resolve')) {
      return LoadErrorKind.Dns;
    }
    if (value.includes('timeout') || value.includes('timed out')) {
      return LoadErrorKind.Timeout;
    }
    if (value.includes('offline') || value.includes('network')) {
      return LoadErrorKind.Offline;
    }
    if (code === -7 || code === -21) {
      return LoadErrorKind.Offline;
    }
    return LoadErrorKind.Unknown;
  }

  private static securityStateForUrl(url: string): SecurityState {
    if (url.toLowerCase().startsWith('https://')) {
      return SecurityState.Secure;
    }
    if (url.toLowerCase().startsWith('http://')) {
      return SecurityState.Insecure;
    }
    return SecurityState.Unknown;
  }

  /**
   * ArkWeb reports which requests its rule engine stopped. Splitting them into
   * ads and trackers is a URL-pattern judgement — the engine itself keeps one
   * combined list — so this labels what was blocked rather than changing it.
   */
  private async handleAdsBlocked(id: string, urls: string[]): Promise<void> {
    let ads: number = 0;
    let trackers: number = 0;
    for (const url of urls) {
      if (isTrackerUrl(url)) {
        trackers += 1;
      } else {
        ads += 1;
      }
    }
    await this.viewModel.recordBlocked(id, {
      ads: ads,
      trackers: trackers,
      popups: 0,
      cookieBanners: 0
    });
    this.syncTab(id);
    if (id === this.activeTabId) {
      this.weeklyBlocked = this.viewModel.getWeeklyBlocked();
    }
  }

  private refreshNavigationState(id: string): void {
    const controller: webview.WebviewController | undefined = this.controllers.get(id);
    if (controller === undefined) {
      return;
    }
    try {
      this.viewModel.updateTab(id, {
        canGoBack: controller.accessBackward(),
        canGoForward: controller.accessForward()
      });
    } catch (error) {
      Logger.warn(TAG, `Navigation state unavailable: ${String(error)}`);
    }
  }

  /** Everything that happens to a page once it has finished loading. */
  private async enhancePage(id: string): Promise<void> {
    const controller: webview.WebviewController | undefined = this.controllers.get(id);
    const tab: BrowserTab | undefined = this.viewModel.getTab(id);
    if (controller === undefined || tab === undefined) {
      return;
    }

    const faviconUrl: string = this.parseScriptString(
      await this.runScript(controller, READ_FAVICON_SCRIPT)
    );
    if (faviconUrl.length > 0 && faviconUrl !== tab.faviconUrl) {
      this.viewModel.updateTab(id, { faviconUrl: faviconUrl });
      this.syncTab(id);
      this.viewModel.persistSession();
    }

    if (this.viewModel.isHostAllowed(tab.url)) {
      await this.runScript(controller, RESTORE_HIDDEN_SCRIPT);
      return;
    }

    let delta: BlockStats = emptyBlockStats();
    if (this.settings.blockAds) {
      const raw: string = await this.runScript(
        controller,
        contentCleanupScript(this.settings.ruleStrength === RuleStrength.Strict)
      );
      delta = this.mergeCounts(delta, raw);
    }
    if (this.settings.blockTrackers) {
      const raw: string = await this.runScript(controller, TRACKER_BLOCK_SCRIPT);
      delta = this.mergeCounts(delta, raw);
    }
    if (tab.isDesktop) {
      await this.runScript(controller, DESKTOP_VIEWPORT_SCRIPT);
    }
    if (totalBlocked(delta) > 0) {
      await this.viewModel.recordBlocked(id, delta);
    }
  }

  private mergeCounts(base: BlockStats, raw: string): BlockStats {
    const parsed: CleanupResult | undefined = this.parseCounts(raw);
    if (parsed === undefined) {
      return base;
    }
    return {
      ads: base.ads + (parsed.ads ?? 0),
      trackers: base.trackers + (parsed.trackers ?? 0),
      popups: base.popups + (parsed.popups ?? 0),
      cookieBanners: base.cookieBanners + (parsed.cookieBanners ?? 0)
    };
  }

  /**
   * runJavaScript hands back the JS return value already JSON-encoded, so a
   * returned string arrives wrapped in quotes and needs unwrapping first.
   */
  private parseCounts(raw: string): CleanupResult | undefined {
    let value: string = raw.trim();
    if (value.length === 0) {
      return undefined;
    }
    if (value.startsWith('"') && value.endsWith('"')) {
      value = value
        .substring(1, value.length - 1)
        .replace(/\\"/g, '"')
        .replace(/\\\\/g, '\\');
    }
    if (!value.startsWith('{')) {
      return undefined;
    }
    try {
      return JSON.parse(value) as CleanupResult;
    } catch (error) {
      Logger.warn(TAG, `Unreadable script result: ${String(error)}`);
      return undefined;
    }
  }

  private parseScriptString(raw: string): string {
    const value: string = raw.trim();
    if (value.length === 0) {
      return '';
    }
    try {
      const decoded: string = JSON.parse(value) as string;
      return typeof decoded === 'string' ? decoded : '';
    } catch (error) {
      return value.replace(/^"|"$/g, '');
    }
  }

  private async runScript(controller: webview.WebviewController, script: string): Promise<string> {
    try {
      return await controller.runJavaScript(script);
    } catch (error) {
      Logger.warn(TAG, `Script execution failed: ${String(error)}`);
      return '';
    }
  }

  private async captureScrollPosition(id: string): Promise<void> {
    const controller: webview.WebviewController | undefined = this.controllers.get(id);
    const tab: BrowserTab | undefined = this.viewModel.getTab(id);
    if (controller === undefined || tab === undefined || isHomeUrl(tab.url)) {
      return;
    }
    const raw: string = await this.runScript(controller, READ_SCROLL_POSITION_SCRIPT);
    const position: number = Number(raw.replace(/[^0-9.-]/g, ''));
    if (Number.isNaN(position)) {
      return;
    }
    this.viewModel.updateTab(id, tab.isReader ? { readerScrollY: position } : { scrollY: position });
    this.viewModel.persistSession();
  }

  private async restoreScrollPosition(tab: BrowserTab): Promise<void> {
    const controller: webview.WebviewController | undefined = this.controllers.get(tab.id);
    const position: number = tab.isReader ? tab.readerScrollY : tab.scrollY;
    if (controller === undefined || position <= 0) {
      return;
    }
    await this.runScript(controller, restoreScrollPositionScript(position));
  }

  // ------------------------------------------------------------------ state

  private syncState(): void {
    this.tabs = this.viewModel.tabs.map((tab: BrowserTab) => cloneTab(tab));
    this.activeTabId = this.viewModel.activeTabId;
    this.settings = cloneSettings(this.viewModel.settings);
    this.quickSites = this.viewModel.getQuickSites();
    this.weeklyBlocked = this.viewModel.getWeeklyBlocked();
    const url: string = this.activeTab()?.url ?? '';
    this.isActiveBookmarked = this.viewModel.isBookmarked(url);
    this.isSiteAllowed = this.viewModel.isHostAllowed(url);
  }

  /** Cheaper path for high-frequency events like progress updates. */
  private syncTab(id: string): void {
    const source: BrowserTab | undefined = this.viewModel.getTab(id);
    if (source === undefined) {
      return;
    }
    this.tabs = this.tabs.map((tab: BrowserTab) => tab.id === id ? cloneTab(source) : tab);
  }

  private retry(): void {
    this.hasError = false;
    this.aboutToAppear();
  }
}
