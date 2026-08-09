import { webview } from '@kit.ArkWeb';
import { abilityAccessCtrl, PermissionRequestResult, Permissions } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';

import { image } from '@kit.ImageKit';
import {
  DESKTOP_VIEWPORT_SCRIPT,
  FORCE_ZOOM_SCRIPT,
  LONG_PRESS_TARGET_SCRIPT,
  triggerDownloadScript,
  findCountScript,
  HOME_URL,
  READER_EXIT_SCRIPT,
  READ_FAVICON_SCRIPT,
  READ_FORM_DRAFT_SCRIPT,
  READ_SCROLL_POSITION_SCRIPT,
  RESUME_PROMPT_TIMEOUT_MS,
  RESUME_WINDOW_DAYS,
  READER_FONT_MAX,
  READER_FONT_MIN,
  READER_FONT_STEP,
  RESTORE_HIDDEN_SCRIPT,
  TRACKER_BLOCK_SCRIPT,
  PASSWORD_FIELD_WATCHER_SCRIPT,
  contentCleanupScript,
  readerApplyScript,
  restoreFormDraftScript,
  restoreScrollPositionScript
} from '../constants/AppConstants';
import {
  BlockStats,
  AppearanceMode,
  BrowserSettings,
  BrowserTab,
  HistoryEntry,
  QuickSite,
  ReaderPaper,
  RuleStrength,
  SearchEngine,
  Suggestion,
  LoadErrorKind,
  SecurityState,
  CertificateSummary,
  SitePermission,
  SitePermissionDecision,
  cloneSettings,
  cloneHistoryEntry,
  cloneTab,
  defaultBrowserSettings,
  emptyBlockStats,
  totalBlocked
} from '../models/BrowserModels';
import { ActionSheet } from '../components/ActionSheet';
import { AddressSheet } from '../components/AddressSheet';
import { AppIcon, IconName } from '../components/AppIcon';
import { BlockPanel } from '../components/BlockPanel';
import { BrowserWebView } from '../components/BrowserWebView';
import { DownloadSheet } from '../components/DownloadSheet';
import { FindSheet } from '../components/FindSheet';
import { BrowserDock } from '../components/BrowserDock';
import { NavigationHistorySheet } from '../components/NavigationHistorySheet';
import { HistorySheet } from '../components/HistorySheet';
import { LinkActionSheet } from '../components/LinkActionSheet';
import { OnboardingSheet } from '../components/OnboardingSheet';
import { PermissionSheet } from '../components/PermissionSheet';
import { PageSettingsPanel } from '../components/PageSettingsPanel';
import { ReaderBar, nextLineHeight } from '../components/ReaderBar';
import { RecentTabsDock } from '../components/RecentTabsDock';
import { ClearDataRange, ClearDataSelection, SettingsPage } from '../components/SettingsPage';
import { SecurityPanel } from '../components/SecurityPanel';
import { SharePanel } from '../components/SharePanel';
import { StartPage } from '../components/StartPage';
import { TabOverview, TabThumbnail } from '../components/TabOverview';
import {
  DOCK_COLLAPSED_HEIGHT,
  DOCK_HEIGHT,
  TAB_WEB_BOTTOM_INSET,
  TAB_WEB_BOTTOM_INSET_COMPACT,
  RECENT_TAB_LIMIT
} from '../components/TabTokens';
import { PrivacyService } from '../services/PrivacyService';
import { CertificateService } from '../services/CertificateService';
import { AdsBlockService } from '../services/AdsBlockService';
import { MemoryPressureService } from '../services/MemoryPressureService';
import { DownloadService, DownloadTask } from '../services/DownloadService';
import { BookmarkTransferService } from '../services/BookmarkTransferService';
import { ShareService, ShareOutcome } from '../services/ShareService';
import { ThemeService } from '../services/ThemeService';
import { TelemetryService } from '../services/TelemetryService';
import { WebHistoryEntry, WebKernelService, WebLongPressTarget } from '../services/WebKernelService';
import { AppContext } from '../utils/AppContext';
import { displayHost, isHomeUrl, isTrackerUrl, normalizeAddress, rawHost } from '../utils/UrlUtils';
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
  NavigationHistory = 7,
  History = 8,
  Share = 9,
  Downloads = 10,
  Find = 11,
  LinkActions = 12,
  Onboarding = 13,
  Permission = 14,
  PageSettings = 15,
  Favorites = 16,
  RecentTabs = 17
}

/** Shape of the JSON the injected cleanup/tracker passes hand back. */
interface CleanupResult {
  ads?: number;
  trackers?: number;
  malicious?: number;
  popups?: number;
  cookieBanners?: number;
}

interface ResumeRequest {
  tabId: string;
  position: number;
  isReader: boolean;
}

interface PendingSitePermission {
  origin: string;
  resources: string[];
  displayResources: Resource[];
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
const TAB_SWITCH_ANIMATION_DURATION: number = 220;
const TAB_SWITCH_ANIMATION_DISTANCE: number = 28;
const TAB_SWITCH_DOCK_DISTANCE: number = 10;

@Entry
@Component
struct Index {
  private viewModel: BrowserViewModel = new BrowserViewModel();
  private controllers: Map<string, webview.WebviewController> = new Map();
  private pageLoadStartedAt: Map<string, number> = new Map();
  @State private isReady: boolean = false;
  @State private hasError: boolean = false;
  @State private tabs: BrowserTab[] = [];
  @State private recentTabs: BrowserTab[] = [];
  @State private activeTabId: string = '';
  @State private settings: BrowserSettings = defaultBrowserSettings();
  @State private sheet: Overlay = Overlay.None;
  @State private isCapsuleHidden: boolean = false;
  @State private suggestions: Suggestion[] = [];
  @State private quickSites: QuickSite[] = [];
  @State private weeklyBlocked: number = 0;
  @State private cumulativeBlocked: number = 0;
  @State private isActivePageAtTop: boolean = true;
  @State private siteStats: BlockStats = emptyBlockStats();
  @State private isSiteAllowed: boolean = false;
  @State private isActiveBookmarked: boolean = false;
  @State private isActiveSavedForLater: boolean = false;
  @State private downloadTasks: DownloadTask[] = [];
  @State private rulesLastUpdatedAt: number = 0;
  @State private findQuery: string = '';
  @State private findCurrent: number = 0;
  @State private findTotal: number = 0;
  @State private longPressTarget: WebLongPressTarget | undefined = undefined;
  @State private pendingSitePermission: PendingSitePermission | undefined = undefined;
  @State private thumbnails: TabThumbnail[] = [];
  @State private backHistory: WebHistoryEntry[] = [];
  @State private history: HistoryEntry[] = [];
  @State private liveTabIds: string[] = [];
  @State private swipePreviewHost: string = '';
  @State private isSwipeBoundary: boolean = false;
  @State private tabSwitchOffset: number = 0;
  /** Status bar height in vp; the browser draws behind the system bars. */
  @State private topInset: number = 0;
  private isTabSoftLimitPromptVisible: boolean = false;
  private pendingPermissionRequest: PermissionRequest | undefined = undefined;
  private pendingGeolocation: OnGeolocationShowEvent | undefined = undefined;
  private pageScrollOffsets: Map<string, number> = new Map();
  private persistedPageScrollOffsets: Map<string, number> = new Map();
  @State private resumeRequest: ResumeRequest | undefined = undefined;
  private resumeToken: number = 0;
  private downloadListener: (tasks: DownloadTask[]) => void = (tasks: DownloadTask[]): void => {
    this.downloadTasks = tasks;
  };

  async aboutToAppear(): Promise<void> {
    try {
      await this.measureTopInset();
      await this.viewModel.initialize(AppContext.getContext());
      ThemeService.apply(AppContext.getContext(), this.viewModel.settings.appearance);
      TelemetryService.setEnabled(this.viewModel.settings.telemetryEnabled);
      this.syncState();
      this.rulesLastUpdatedAt = this.viewModel.adsBlockService.lastUpdatedAt;
      this.liveTabIds = this.initialLiveTabIds();
      MemoryPressureService.register((level: number): void => {
        if (level >= 1) {
          void this.reclaimForMemory(level);
        }
      });
      DownloadService.configurePolicy(
        this.settings.largeDownloadThresholdMb,
        this.settings.wifiOnlyDownloads,
        (task: DownloadTask): void => this.promptDownloadPolicy(task)
      );
      DownloadService.subscribe(this.downloadListener);
      this.isReady = true;
      this.promptExpiredTabs();
      if (!this.settings.onboardingCompleted) {
        this.sheet = Overlay.Onboarding;
      }
    } catch (error) {
      Logger.error(TAG, `Failed to initialize browser: ${String(error)}`);
      this.hasError = true;
    }
  }

  /**
   * Fullscreen surfaces (the tab overview) sit behind the status bar, so they
   * need its height to keep their header clear of the clock and indicators.
   */
  private async measureTopInset(): Promise<void> {
    try {
      const mainWindow: window.Window = await window.getLastWindow(AppContext.getContext());
      const area: window.AvoidArea = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      this.topInset = px2vp(area.topRect.height);
    } catch (error) {
      Logger.warn(TAG, `Failed to read the status bar height: ${String(error)}`);
    }
  }

  aboutToDisappear(): void {
    DownloadService.unsubscribe(this.downloadListener);
    MemoryPressureService.unregister();
    PrivacyService.clearPrivateSiteData(this.privateControllers(this.tabs));
  }

  private promptExpiredTabs(): void {
    if (this.viewModel.expiredTabCount === 0) {
      return;
    }
    try {
      this.getUIContext().showAlertDialog({
        title: $r('app.string.expired_tabs_title'),
        message: $r('app.string.expired_tabs_message'),
        primaryButton: {
          value: $r('app.string.expired_tabs_restore'),
          action: (): void => {
            this.viewModel.restoreExpiredTabs().then((): void => this.syncState());
          }
        },
        secondaryButton: {
          value: $r('app.string.expired_tabs_archive'),
          action: (): void => {
            this.viewModel.archiveExpiredTabs();
          }
        }
      });
    } catch (error) {
      Logger.warn(TAG, `Expired tab prompt unavailable: ${String(error)}`);
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
        this.ErrorLayer()
        this.ResumeLayer()
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
        this.TabStack()
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

  /** Keeps only the configured live WebView set mounted; the rest are restorable shells. */
  @Builder
  private TabStack() {
    Stack({ alignContent: Alignment.TopEnd }) {
      ForEach(this.tabs, (tab: BrowserTab) => {
        Column() {
          if (isHomeUrl(tab.url)) {
            StartPage({
              quickSites: this.quickSites,
              quickSitesEnabled: this.settings.quickSitesEnabled,
              backgroundEnabled: this.settings.startPageBackgroundEnabled,
              onOpenAddress: (): void => this.openAddress(),
              onOpenSite: (url: string): void => this.navigateTo(url),
              onRemoveSite: (url: string): void => { void this.removeQuickSite(url); },
              onOpenPageSettings: (): void => { this.sheet = Overlay.PageSettings; }
            })
          } else if (this.isTabLive(tab.id)) {
            BrowserWebView({
              tab: tab,
              blockAds: this.settings.blockAds && !this.viewModel.isHostAllowed(tab.url),
              minimumFontSize: this.settings.minimumFontSize,
              initialZoomPercent: this.viewModel.siteZoomPercent(tab.url),
              webDarkMode: this.settings.webDarkMode,
              darkModeExcluded: this.isDarkModeExcluded(tab.url),
              controller: this.controllerFor(tab.id),
              kernelCallbacks: {
                onPageBegin: (url: string): void => this.handlePageBegin(tab.id, url),
                onPageEnd: (url: string): void => { this.handlePageEnd(tab.id, url); },
                onProgressChange: (progress: number): void => this.handleProgress(tab.id, progress),
                onError: (code: number, message: string): void =>
                  this.handleLoadError(tab.id, code, message),
                onSslError: (code: SslError, chain: Array<Uint8Array>): void => {
                  void this.handleSslError(tab.id, code, chain);
                }
              },
              onTitleReceive: (title: string): void => this.handleTitle(tab.id, title),
              onScroll: (offsetY: number): void => this.handlePageScroll(tab.id, offsetY),
              onKeyboardAttach: (): void => { this.showCapsule(); },
              isAtTop: tab.id === this.activeTabId && this.isActivePageAtTop,
              gesturesEnabled: this.settings.gesturesEnabled,
              onPullRefresh: (): void => { this.pullRefresh(tab.id); },
              onEdgeBack: (): void => { this.edgeNavigate(tab.id, true); },
              onEdgeForward: (): void => { this.edgeNavigate(tab.id, false); },
              onAdsBlocked: (urls: string[]): void => { this.handleAdsBlocked(tab.id, urls); },
              onScaleChange: (scale: number): void => { void this.handleScaleChange(tab.id, scale); },
              onLongPress: (): void => { void this.openLongPressActions(tab.id); },
              onPermissionRequest: (event: OnPermissionRequestEvent): void =>
                this.handlePermissionRequest(event),
              onGeolocationShow: (event: OnGeolocationShowEvent): void =>
                this.handleGeolocationShow(event),
              onPasswordFieldFocus: (): void => { void this.handlePasswordFocusOnInsecurePage(tab.id); }
            })
          } else {
            this.HibernatedTab(tab)
          }
        }
        .id(`tab-view-${tab.id}`)
        .width('100%')
        .height('100%')
        .padding({ bottom: isHomeUrl(tab.url) ? 0 : this.webBottomInset() })
        .opacity(tab.id === this.activeTabId ? 1 : 0)
        .translate({ x: this.tabTransitionOffset(tab.id) })
        .zIndex(tab.id === this.activeTabId ? 1 : 0)
        .hitTestBehavior(tab.id === this.activeTabId ? HitTestMode.Default : HitTestMode.None)
      }, (tab: BrowserTab) =>
        `${tab.id}-${isHomeUrl(tab.url) ? 'home' : (this.isTabLive(tab.id) ? 'live' : 'sleep')}`)
    }
    .layoutWeight(1)
    .width('100%')
  }

  @Builder
  private HibernatedTab(tab: BrowserTab) {
    Column({ space: 12 }) {
      Text(tab.title.length > 0 ? tab.title : displayHost(tab.url))
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text($r('app.string.tab_hibernated'))
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
      Text($r('app.string.tab_hibernated_restore'))
        .fontSize(14)
        .fontColor($r('app.color.accent'))
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.page_background'))
    .onClick(() => { void this.selectTab(tab.id); })
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

  /**
   * Covers the failed page rather than unmounting it. Replacing the tab stack
   * tore down every live kernel, which is what left a failed tab unable to load
   * the next address until the user hit retry. It also has to live outside the
   * tab ForEach: those items are keyed and reused, so a change of error state
   * inside one would never be drawn.
   */
  @Builder
  private ErrorLayer() {
    if (!this.isActiveHome() && this.activeErrorKind() !== LoadErrorKind.None) {
      Column({ space: 16 }) {
        Text(this.errorTitle(this.activeErrorKind()))
          .fontSize(19)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Text(this.errorMessage(this.activeErrorKind()))
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .textAlign(TextAlign.Center)
          .padding({ left: 28, right: 28 })
        Row({ space: 12 }) {
          Text($r('app.string.retry'))
            .fontSize(15)
            .fontColor($r('app.color.accent'))
            .onClick(() => this.retryPage())
          if (this.activeErrorKind() === LoadErrorKind.Certificate) {
            Text($r('app.string.certificate_details'))
              .fontSize(15)
              .fontColor($r('app.color.text_secondary'))
              .onClick(() => this.openSecurityDetails())
          }
        }
      }
      .width('100%')
      .height('100%')
      .padding({ bottom: this.webBottomInset() })
      .backgroundColor($r('app.color.page_background'))
      .justifyContent(FlexAlign.Center)
    }
  }

  /**
   * A snackbar riding just above the dock rather than a band stacked into the page:
   * it offers the one action worth a tap, dismisses itself, and never competes with
   * the toolbar for space.
   */
  @Builder
  private ResumeLayer() {
    if (this.sheet === Overlay.None && this.resumeRequest !== undefined &&
      this.resumeRequest.tabId === this.activeTabId) {
      this.ResumePrompt(this.resumeRequest)
    }
  }

  @Builder
  private ResumePrompt(request: ResumeRequest) {
    Row({ space: 10 }) {
      Text($r('app.string.resume_reading_title'))
        .fontSize(13.5)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text($r('app.string.resume_reading_continue'))
        .fontSize(13.5)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.accent'))
        .padding({ left: 6, right: 6 })
        .onClick(() => this.continueResume(request))
      AppIcon({ name: IconName.Close, glyphSize: 15, color: $r('app.color.text_secondary') })
        .width(24)
        .accessibilityText($r('app.string.resume_reading_start_over'))
        .onClick(() => this.startResumeFromTop(request))
    }
    .height(44)
    .margin({ left: 14, right: 14, bottom: this.dockHeight() + 8 })
    .padding({ left: 16, right: 12 })
    .borderRadius(22)
    .backgroundColor($r('app.color.surface_panel'))
    .backdropBlur(24)
    .border({ width: 1, color: $r('app.color.border') })
    .shadow({ radius: 16, color: $r('app.color.shadow_soft'), offsetY: 3 })
    .transition(TransitionEffect.OPACITY.animation({ duration: 180 })
      .combine(TransitionEffect.translate({ y: 16 })))
  }

  // ---------------------------------------------------------------- capsule

  @Builder
  private CapsuleLayer() {
    if (this.sheet === Overlay.None) {
      BrowserDock({
        isHome: this.isActiveHome(),
        collapsed: this.isDockCollapsed(),
        host: displayHost(this.activeTab()?.url ?? ''),
        tabCount: this.tabs.length,
        activeTabIndex: this.tabs.findIndex((tab: BrowserTab) => tab.id === this.activeTabId),
        blockedCount: totalBlocked(this.activeTab()?.blocked ?? emptyBlockStats()),
        isLoading: this.activeTab()?.isLoading === true,
        canGoBack: this.activeTab()?.canGoBack === true,
        canGoForward: this.activeTab()?.canGoForward === true,
        gesturesEnabled: this.settings.gesturesEnabled,
        actionsGestureEnabled: this.settings.gestureActionsEnabled,
        tabSwitchGestureEnabled: this.settings.gestureTabSwitchEnabled,
        blockingGestureEnabled: this.settings.gestureBlockingEnabled,
        onOpenAddress: (): void => this.openAddress(),
        onBack: (): void => { void this.performAction('back'); },
        onForward: (): void => { void this.performAction('forward'); },
        onOpenTabs: (): void => { void this.openTabs(); },
        onOpenRecentTabs: (): void => { this.sheet = Overlay.RecentTabs; },
        onOpenMenu: (): void => { this.sheet = Overlay.Actions; },
        onOpenBlocking: (): void => this.openBlockPanel(),
        onReload: (): void => { void this.performAction('reload'); },
        onHide: (): void => {
          if (this.settings.autoHideToolbarEnabled && !this.isActiveHome()) {
            this.setCapsuleHidden(true);
          }
        },
        onShow: (): void => this.showCapsule(),
        onSwitchPrevious: (): void => { void this.switchNeighbour(-1); },
        onSwitchNext: (): void => { void this.switchNeighbour(1); }
      })
        .translate({ x: this.tabSwitchOffset })
        .transition(TransitionEffect.OPACITY.animation({ duration: 180 })
          .combine(TransitionEffect.translate({ y: 24 })))
    }
  }

  /** Home never collapses — there is no page to give the height back to. */
  private isDockCollapsed(): boolean {
    return this.isCapsuleHidden && !this.isActiveHome();
  }

  private dockHeight(): number {
    return this.isDockCollapsed() ? DOCK_COLLAPSED_HEIGHT : DOCK_HEIGHT;
  }

  private webBottomInset(): number {
    return this.settings.autoHideToolbarEnabled ? TAB_WEB_BOTTOM_INSET_COMPACT : TAB_WEB_BOTTOM_INSET;
  }

  // --------------------------------------------------------------- overlays

  @Builder
  private OverlayLayer() {
    if (this.sheet === Overlay.RecentTabs) {
      RecentTabsDock({
        tabs: this.recentTabs,
        activeTabId: this.activeTabId,
        onDismiss: (): void => { this.sheet = Overlay.None; },
        onSelect: (id: string): void => { void this.selectTab(id); },
        onOpenAll: (): void => { void this.openTabs(); },
        onNewTab: (): void => this.createTab(this.activeTab()?.isPrivate === true)
      })
        .transition(TransitionEffect.OPACITY.animation({ duration: 180 }))
    } else if (this.sheet === Overlay.Actions) {
      ActionSheet({
        host: displayHost(this.activeTab()?.url ?? ''),
        blockedCount: totalBlocked(this.activeTab()?.blocked ?? emptyBlockStats()),
        isHome: this.isActiveHome(),
        isBookmarked: this.isActiveBookmarked,
        isReader: this.isActiveReader(),
        isDesktop: this.activeTab()?.isDesktop === true,
        onDismiss: (): void => { this.sheet = Overlay.None; },
        onAction: (key: string): void => { this.performAction(key); }
      })
        .transition(this.sheetTransition())
    } else if (this.sheet === Overlay.PageSettings) {
      PageSettingsPanel({
        quickSitesEnabled: this.settings.quickSitesEnabled,
        backgroundEnabled: this.settings.startPageBackgroundEnabled,
        appearanceLabel: this.appearanceLabel(),
        onToggleQuickSites: (): void => { void this.toggleQuickSites(); },
        onToggleBackground: (): void => { void this.toggleStartPageBackground(); },
        onOpenSettings: (): void => { this.sheet = Overlay.Settings; },
        onDismiss: (): void => { this.sheet = Overlay.None; }
      })
        .transition(TransitionEffect.OPACITY.animation({ duration: 180 }))
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
        tabs: this.normalTabs(),
        privateTabs: this.privateTabs(),
        activeTabId: this.activeTabId,
        topInset: this.topInset,
        thumbnails: this.thumbnails,
        onSelect: (id: string): void => { this.selectTab(id); },
        onSwitch: (direction: number): void => { this.switchOverviewTab(direction); },
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
        cumulativeBlockedCount: this.cumulativeBlocked,
        isDisabledForSite: this.isSiteAllowed,
        onDismiss: (): void => { this.sheet = Overlay.None; },
        onToggleSite: (): void => { this.toggleSiteBlocking(); },
        onOpenSettings: (): void => { this.sheet = Overlay.Settings; }
      })
        .transition(this.sheetTransition())
    } else if (this.sheet === Overlay.Settings) {
      SettingsPage({
        settings: this.settings,
        topInset: this.topInset,
        allowedHosts: this.viewModel.getAllowedHosts(),
        sitePermissions: this.settings.sitePermissions,
        currentHost: displayHost(this.activeTab()?.url ?? ''),
        currentHostDarkModeEnabled: !this.isDarkModeExcluded(this.activeTab()?.url ?? ''),
        rulesLastUpdatedAt: this.rulesLastUpdatedAt,
        onChange: (settings: BrowserSettings): void => { this.applySettings(settings); },
        onResetGestures: (): void => { this.resetGestures(); },
        onClearData: (selection: ClearDataSelection): void => { this.clearBrowsingData(selection); },
        onImportBookmarks: (): void => { void this.importBookmarks(); },
        onExportBookmarks: (): void => { void this.exportBookmarks(); },
        onRemoveAllowedHost: (host: string): void => { void this.removeAllowedHost(host); },
        onRemoveSitePermission: (origin: string): void => { void this.removeSitePermission(origin); },
        onUpdateSitePermission: (origin: string, kind: string, decision: SitePermissionDecision): void => {
          void this.toggleSitePermissionDecision(origin, kind, decision);
        },
        onToggleCurrentSiteDarkMode: (): void => { void this.toggleCurrentSiteDarkMode(); },
        onUpdateRules: (): void => { void this.updateRules(); },
        onBack: (): void => { this.sheet = Overlay.None; }
      })
        .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
    } else if (this.sheet === Overlay.Permission && this.pendingSitePermission !== undefined) {
      PermissionSheet({
        origin: this.pendingSitePermission.origin,
        resources: this.pendingSitePermission.displayResources,
        onAllow: (): void => { void this.allowPendingPermission(); },
        onDeny: (): void => { void this.denyPendingPermission(); }
      })
        .transition(this.sheetTransition())
    } else if (this.sheet === Overlay.Security) {
      SecurityPanel({
        host: displayHost(this.activeTab()?.url ?? ''),
        url: this.activeTab()?.url ?? '',
        state: this.activeTab()?.securityState ?? SecurityState.Unknown,
        certificate: this.activeTab()?.certificate ?? null,
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
    } else if (this.sheet === Overlay.History) {
      HistorySheet({
        entries: this.history,
        savedItems: this.viewModel.savedItems,
        usesFullscreenBars: this.isActiveHome(),
        onDismiss: (): void => { this.sheet = Overlay.None; },
        onSelect: (url: string): void => this.navigateTo(url),
        onDelete: (id: string): void => { this.deleteHistory(id); },
        onDeleteSite: (host: string): void => { this.deleteHistorySite(host); }
      })
        .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
    } else if (this.sheet === Overlay.Favorites) {
      HistorySheet({
        entries: [],
        savedItems: this.viewModel.savedItems,
        favoritesOnly: true,
        usesFullscreenBars: this.isActiveHome(),
        onDismiss: (): void => { this.sheet = Overlay.None; },
        onSelect: (url: string): void => this.navigateTo(url)
      })
        .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
    } else if (this.sheet === Overlay.Downloads) {
      DownloadSheet({
        tasks: this.downloadTasks,
        onDismiss: (): void => { this.sheet = Overlay.None; },
        onPause: (id: string): void => DownloadService.pause(id),
        onResume: (id: string): void => DownloadService.resume(id),
        onRetry: (id: string): void => DownloadService.retry(id),
        onOpen: (task: DownloadTask): void => { void this.openDownload(task); },
        onShare: (task: DownloadTask): void => { void this.shareDownload(task); },
        onDeleteFile: (id: string): void => DownloadService.remove(id, true),
        onDeleteRecord: (id: string): void => DownloadService.remove(id, false)
      })
        .transition(this.sheetTransition())
    } else if (this.sheet === Overlay.Find) {
      FindSheet({
        query: this.findQuery,
        current: this.findCurrent,
        total: this.findTotal,
        onQueryChange: (query: string): void => { void this.updateFindQuery(query); },
        onPrevious: (): void => { void this.findNextMatch(false); },
        onNext: (): void => { void this.findNextMatch(true); },
        onDismiss: (): void => { this.closeFind(); }
      })
    } else if (this.sheet === Overlay.LinkActions && this.longPressTarget !== undefined) {
      LinkActionSheet({
        target: this.longPressTarget,
        isPrivate: this.activeTab()?.isPrivate === true,
        onDismiss: (): void => this.closeLongPressActions(),
        onAction: (key: string): void => { void this.performLongPressAction(key); }
      })
    } else if (this.sheet === Overlay.Onboarding) {
      OnboardingSheet({
        searchEngine: this.settings.searchEngine,
        onSearchEngineChange: (engine: SearchEngine): void => this.setOnboardingSearchEngine(engine),
        onFinish: (): void => { void this.finishOnboarding(); },
        onSkip: (): void => { void this.finishOnboarding(); }
      })
    } else if (this.sheet === Overlay.Share) {
      SharePanel({
        title: this.activeTab()?.title ?? '',
        host: displayHost(this.activeTab()?.url ?? ''),
        onDismiss: (): void => { this.sheet = Overlay.None; },
        onSystemShare: (): void => { void this.shareActivePage(); },
        onScreenshotShare: (): void => { void this.shareActiveScreenshot(); },
        onCopy: (): void => { void this.copyActiveLink(); },
        onSaveLater: (): void => { void this.saveActiveForLater(); }
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

  private appearanceLabel(): Resource {
    if (this.settings.appearance === AppearanceMode.Light) {
      return $r('app.string.appearance_light');
    }
    if (this.settings.appearance === AppearanceMode.Dark) {
      return $r('app.string.appearance_dark');
    }
    return $r('app.string.appearance_system');
  }

  private isActiveReader(): boolean {
    return this.activeTab()?.isReader === true;
  }

  private normalTabs(): BrowserTab[] {
    return this.tabs.filter((tab: BrowserTab) => !tab.isPrivate);
  }

  private privateTabs(): BrowserTab[] {
    return this.tabs.filter((tab: BrowserTab) => tab.isPrivate);
  }

  private privateControllers(tabs: BrowserTab[]): webview.WebviewController[] {
    const privateControllers: webview.WebviewController[] = [];
    for (const tab of tabs) {
      if (!tab.isPrivate) {
        continue;
      }
      const controller: webview.WebviewController | undefined = this.controllers.get(tab.id);
      if (controller !== undefined) {
        privateControllers.push(controller);
      }
    }
    return privateControllers;
  }

  private initialLiveTabIds(): string[] {
    const ordered: BrowserTab[] = this.tabs.slice(0).sort(
      (left: BrowserTab, right: BrowserTab): number => right.lastVisitedAt - left.lastVisitedAt
    );
    const live: string[] = [];
    const limit: number = this.liveWebViewLimit();
    const active: BrowserTab | undefined = this.tabs.find((tab: BrowserTab) => tab.id === this.activeTabId);
    if (active !== undefined && !isHomeUrl(active.url)) {
      live.push(active.id);
    }
    for (const tab of ordered) {
      if (isHomeUrl(tab.url) || live.includes(tab.id)) {
        continue;
      }
      if (live.length >= limit) {
        break;
      }
      live.push(tab.id);
    }
    return live;
  }

  private isTabLive(id: string): boolean {
    const tab: BrowserTab | undefined = this.tabs.find((item: BrowserTab) => item.id === id);
    return tab !== undefined && (isHomeUrl(tab.url) || this.liveTabIds.includes(id));
  }

  private liveWebViewLimit(): number {
    return Math.max(1, Math.round(this.settings.liveWebViewLimit));
  }

  private async activateTab(id: string): Promise<void> {
    const tab: BrowserTab | undefined = this.tabs.find((item: BrowserTab) => item.id === id);
    if (tab === undefined || isHomeUrl(tab.url) || this.liveTabIds.includes(id)) {
      return;
    }
    while (this.liveTabIds.length >= this.liveWebViewLimit()) {
      const candidate: string = this.leastRecentLiveTab(id);
      if (candidate.length === 0) {
        break;
      }
      await this.hibernateTab(candidate);
    }
    if (!this.liveTabIds.includes(id)) {
      this.liveTabIds = this.liveTabIds.concat([id]);
    }
  }

  private leastRecentLiveTab(excludedId: string): string {
    let candidate: BrowserTab | undefined;
    for (const tab of this.tabs) {
      if (tab.id === excludedId || !this.liveTabIds.includes(tab.id) || isHomeUrl(tab.url)) {
        continue;
      }
      if (candidate === undefined || tab.lastVisitedAt < candidate.lastVisitedAt) {
        candidate = tab;
      }
    }
    return candidate?.id ?? '';
  }

  private async hibernateTab(id: string): Promise<void> {
    const controller: webview.WebviewController | undefined = this.controllers.get(id);
    if (controller !== undefined) {
      await this.captureScrollPosition(id);
      await this.captureFormDraft(id);
      this.controllers.delete(id);
    }
    this.liveTabIds = this.liveTabIds.filter((tabId: string) => tabId !== id);
  }

  private async enforceLiveWebViewLimit(limit: number): Promise<void> {
    const target: number = Math.max(1, Math.round(limit));
    while (this.liveTabIds.length > target) {
      const candidate: string = this.leastRecentLiveTab(this.activeTabId);
      if (candidate.length === 0) {
        break;
      }
      await this.hibernateTab(candidate);
    }
  }

  private async reclaimForMemory(level: number): Promise<void> {
    const target: number = level >= 2 ? 1 : Math.max(1, this.liveWebViewLimit() - 1);
    await this.enforceLiveWebViewLimit(target);
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
      // Leaving the start page also takes the tab out of the "home is always
      // live" case, so it has to join the live set in the same frame or it
      // renders as hibernated instead of loading.
      this.viewModel.updateTab(tab.id, { url: url, isLoading: true, progress: 0 });
      if (!this.liveTabIds.includes(tab.id)) {
        this.liveTabIds = this.liveTabIds.concat([tab.id]);
      }
      this.syncState();
      void this.enforceLiveWebViewLimit(this.liveWebViewLimit());
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
    this.liveTabIds = this.liveTabIds.filter((tabId: string) => tabId !== id);
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
    this.clearSwipePreview();
    if (next !== this.activeTabId) {
      await this.captureScrollPosition(this.activeTabId);
      await this.captureThumbnail(this.activeTabId);
      await this.activateTab(next);
      this.dismissResumePrompt();
      await this.animateTabSwitch(next, offset);
      const selected: BrowserTab | undefined = this.viewModel.getActiveTab();
      if (selected !== undefined) {
        await this.prepareScrollResume(selected);
      }
    }
  }

  private async animateTabSwitch(next: string, direction: number): Promise<void> {
    this.getUIContext().animateTo({
      duration: TAB_SWITCH_ANIMATION_DURATION,
      curve: Curve.FastOutSlowIn
    }, (): void => {
      this.viewModel.selectTab(next);
      this.viewModel.updateTab(next, { lastVisitedAt: Date.now() });
      this.syncState();
      this.tabSwitchOffset = -direction * TAB_SWITCH_DOCK_DISTANCE;
    });
    await this.waitForAnimation();
    this.getUIContext().animateTo({
      duration: 120,
      curve: Curve.EaseOut
    }, (): void => {
      this.tabSwitchOffset = 0;
    });
  }

  private waitForAnimation(): Promise<void> {
    return new Promise<void>((resolve: () => void): void => {
      setTimeout(resolve, TAB_SWITCH_ANIMATION_DURATION);
    });
  }

  private tabTransitionOffset(id: string): number {
    const activeIndex: number = this.tabs.findIndex((tab: BrowserTab) => tab.id === this.activeTabId);
    const tabIndex: number = this.tabs.findIndex((tab: BrowserTab) => tab.id === id);
    if (activeIndex < 0 || tabIndex === activeIndex) {
      return 0;
    }
    return tabIndex < activeIndex ? -TAB_SWITCH_ANIMATION_DISTANCE : TAB_SWITCH_ANIMATION_DISTANCE;
  }

  private previewNeighbour(direction: number): void {
    if (direction === 0) {
      this.clearSwipePreview();
      return;
    }
    const next: string = this.viewModel.neighbourTabId(direction);
    if (next === this.activeTabId) {
      this.swipePreviewHost = displayHost(this.activeTab()?.url ?? '');
      this.isSwipeBoundary = true;
      return;
    }
    const tab: BrowserTab | undefined = this.viewModel.getTab(next);
    this.swipePreviewHost = tab === undefined
      ? ''
      : (tab.title.length > 0 ? tab.title : displayHost(tab.url));
    this.isSwipeBoundary = false;
  }

  private clearSwipePreview(): void {
    this.swipePreviewHost = '';
    this.isSwipeBoundary = false;
  }

  private async selectTab(id: string): Promise<void> {
    this.dismissResumePrompt();
    await this.activateTab(id);
    await this.captureScrollPosition(this.activeTabId);
    await this.captureThumbnail(this.activeTabId);
    this.viewModel.selectTab(id);
    this.viewModel.updateTab(id, { lastVisitedAt: Date.now() });
    this.sheet = Overlay.None;
    this.isCapsuleHidden = false;
    this.syncState();
    const selected: BrowserTab | undefined = this.viewModel.getActiveTab();
    if (selected !== undefined) {
      await this.prepareScrollResume(selected);
    }
  }

  private switchOverviewTab(direction: number): void {
    if (this.tabs.length < 2) {
      return;
    }
    const currentIndex: number = this.tabs.findIndex((tab: BrowserTab) => tab.id === this.activeTabId);
    if (currentIndex < 0) {
      return;
    }
    const nextIndex: number = (currentIndex + direction + this.tabs.length) % this.tabs.length;
    void this.selectTab(this.tabs[nextIndex].id);
  }

  private createTab(isPrivate: boolean): void {
    if (this.viewModel.isTabSoftLimitReached()) {
      this.promptTabSoftLimit();
    }
    this.viewModel.addTab(HOME_URL, isPrivate);
    void this.activateTab(this.viewModel.activeTabId);
    this.sheet = Overlay.None;
    this.isCapsuleHidden = false;
    this.syncState();
  }

  private promptTabSoftLimit(): void {
    if (this.isTabSoftLimitPromptVisible) {
      return;
    }
    this.isTabSoftLimitPromptVisible = true;
    try {
      this.getUIContext().showAlertDialog({
        title: $r('app.string.tab_soft_limit_title'),
        message: $r('app.string.tab_soft_limit_message'),
        primaryButton: {
          value: $r('app.string.tab_soft_limit_cleanup'),
          action: (): void => {
            this.isTabSoftLimitPromptVisible = false;
            this.cleanupSoftLimitTabs();
          }
        },
        secondaryButton: {
          value: $r('app.string.tab_soft_limit_continue'),
          action: (): void => {
            this.isTabSoftLimitPromptVisible = false;
          }
        }
      });
    } catch (error) {
      this.isTabSoftLimitPromptVisible = false;
      Logger.warn(TAG, `Tab limit prompt unavailable: ${String(error)}`);
    }
  }

  private cleanupSoftLimitTabs(): void {
    const candidates: string[] = this.viewModel.softLimitCleanupCandidates();
    for (const id of candidates) {
      this.closeTab(id);
    }
    if (candidates.length > 0) {
      try {
        this.getUIContext().getPromptAction().showToast({
          message: `${candidates.length}${$r('app.string.tab_soft_limit_cleaned')}`
        });
      } catch (error) {
        Logger.warn(TAG, `Tab cleanup toast unavailable: ${String(error)}`);
      }
    }
  }

  private closeTab(id: string): void {
    void this.captureScrollPosition(id);
    const tab: BrowserTab | undefined = this.tabs.find((item: BrowserTab) => item.id === id);
    if (tab?.isPrivate === true) {
      PrivacyService.clearPrivateSiteData(this.privateControllers([tab]));
    }
    this.viewModel.closeTab(id);
    this.controllers.delete(id);
    this.liveTabIds = this.liveTabIds.filter((tabId: string) => tabId !== id);
    this.thumbnails = this.thumbnails.filter((item: TabThumbnail) => item.id !== id);
    if (this.settings.clearCookiesOnTabClose) {
      PrivacyService.clearCookies();
    }
    this.syncState();
  }

  private closeAllTabs(): void {
    void this.captureScrollPosition(this.activeTabId);
    PrivacyService.clearPrivateSiteData(this.privateControllers(this.tabs));
    this.viewModel.closeAllTabs();
    this.controllers.clear();
    this.liveTabIds = [];
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
      this.sheet = Overlay.Share;
      return;
    }
    if (key === 'favorites') {
      this.sheet = Overlay.Favorites;
      return;
    }
    if (key === 'history') {
      this.sheet = Overlay.History;
      return;
    }
    if (key === 'settings') {
      this.sheet = Overlay.Settings;
      return;
    }
    if (key === 'blocking') {
      this.openBlockPanel();
      return;
    }
    if (key === 'home') {
      this.goHome(tab.id);
      this.sheet = Overlay.None;
      return;
    }
    if (key === 'private') {
      this.createTab(true);
      return;
    }
    if (key === 'tabs') {
      await this.openTabs();
      return;
    }
    if (key === 'bookmark') {
      await this.viewModel.toggleSaved(tab);
      this.isActiveBookmarked = this.viewModel.isSaved(tab.url);
      this.isActiveSavedForLater = this.viewModel.isSavedForLater(tab.url);
      return;
    }
    if (key === 'save_later') {
      await this.viewModel.saveForLater(tab);
      this.isActiveBookmarked = this.viewModel.isSaved(tab.url);
      this.isActiveSavedForLater = this.viewModel.isSavedForLater(tab.url);
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
      return;
    }
    if (key === 'downloads') {
      this.sheet = Overlay.Downloads;
      return;
    }
    if (key === 'find') {
      this.findQuery = '';
      this.findCurrent = 0;
      this.findTotal = 0;
      this.sheet = Overlay.Find;
    }
  }

  private async updateFindQuery(query: string): Promise<void> {
    this.findQuery = query;
    this.findCurrent = 0;
    this.findTotal = 0;
    const controller: webview.WebviewController | undefined = this.controllers.get(this.activeTabId);
    if (controller === undefined || query.trim().length === 0) {
      if (controller !== undefined) {
        WebKernelService.clearFind(controller);
      }
      return;
    }
    const raw: string = await this.runScript(controller, findCountScript(query));
    if (query !== this.findQuery) {
      return;
    }
    const count: number = Number(this.parseScriptString(raw));
    this.findTotal = Number.isNaN(count) ? 0 : count;
    if (this.findTotal > 0) {
      WebKernelService.findAll(controller, query.trim());
      this.findCurrent = 1;
    }
  }

  private findNextMatch(forward: boolean): void {
    if (this.findTotal === 0) {
      return;
    }
    const controller: webview.WebviewController | undefined = this.controllers.get(this.activeTabId);
    if (controller === undefined) {
      return;
    }
    WebKernelService.findNext(controller, forward);
    this.findCurrent = forward
      ? (this.findCurrent >= this.findTotal ? 1 : this.findCurrent + 1)
      : (this.findCurrent <= 1 ? this.findTotal : this.findCurrent - 1);
  }

  private closeFind(): void {
    const controller: webview.WebviewController | undefined = this.controllers.get(this.activeTabId);
    if (controller !== undefined) {
      WebKernelService.clearFind(controller);
    }
    this.findQuery = '';
    this.findCurrent = 0;
    this.findTotal = 0;
    this.sheet = Overlay.None;
  }

  private async shareActivePage(): Promise<void> {
    const tab: BrowserTab | undefined = this.activeTab();
    if (tab === undefined) {
      return;
    }
    const outcome: ShareOutcome = await ShareService.share(AppContext.getContext(), tab.url, tab.title);
    if (outcome === ShareOutcome.Shared) {
      this.sheet = Overlay.None;
    }
  }

  private async copyActiveLink(): Promise<void> {
    const tab: BrowserTab | undefined = this.activeTab();
    if (tab === undefined) {
      return;
    }
    const outcome: ShareOutcome = await ShareService.copy(tab.url);
    if (outcome === ShareOutcome.Copied) {
      this.showCopyToast();
      this.sheet = Overlay.None;
    }
  }

  private async shareActiveScreenshot(): Promise<void> {
    const tab: BrowserTab | undefined = this.activeTab();
    if (tab === undefined) {
      return;
    }
    try {
      const shot: image.PixelMap =
        await this.getUIContext().getComponentSnapshot().get(`tab-view-${tab.id}`);
      const outcome: ShareOutcome = await ShareService.shareImage(
        AppContext.getContext(), shot, tab.title);
      if (outcome === ShareOutcome.Shared) {
        this.sheet = Overlay.None;
      }
    } catch (error) {
      Logger.warn(TAG, `Page screenshot unavailable: ${String(error)}`);
    }
  }

  private async openDownload(task: DownloadTask): Promise<void> {
    await DownloadService.open(AppContext.getContext(), task);
  }

  private async shareDownload(task: DownloadTask): Promise<void> {
    await DownloadService.share(AppContext.getContext(), task);
  }

  private promptDownloadPolicy(task: DownloadTask): void {
    try {
      this.getUIContext().showAlertDialog({
        title: $r('app.string.download_policy_title'),
        message: `${task.fileName}${$r('app.string.download_policy_message')}`,
        primaryButton: {
          value: $r('app.string.download_policy_continue'),
          action: (): void => DownloadService.approve(task.id)
        },
        secondaryButton: {
          value: $r('app.string.cancel'),
          action: (): void => DownloadService.cancelByPolicy(task.id)
        }
      });
    } catch (error) {
      Logger.warn(TAG, `Download policy prompt unavailable: ${String(error)}`);
      DownloadService.cancelByPolicy(task.id);
    }
  }

  private showCopyToast(): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.copied_link') });
    } catch (error) {
      Logger.warn(TAG, `Toast unavailable: ${String(error)}`);
    }
  }

  private async saveActiveForLater(): Promise<void> {
    const tab: BrowserTab | undefined = this.activeTab();
    if (tab === undefined) {
      return;
    }
    await this.viewModel.saveForLater(tab);
    this.isActiveBookmarked = this.viewModel.isSaved(tab.url);
    this.isActiveSavedForLater = this.viewModel.isSavedForLater(tab.url);
    this.sheet = Overlay.None;
  }

  private async deleteHistory(id: string): Promise<void> {
    await this.viewModel.removeHistoryEntry(id);
    this.syncState();
  }

  private async deleteHistorySite(host: string): Promise<void> {
    if (host.length === 0) {
      return;
    }
    await this.viewModel.removeHistoryForHost(host);
    this.syncState();
  }

  // ------------------------------------------------------------------ reader

  private async enterReader(id: string): Promise<void> {
    const controller: webview.WebviewController | undefined = this.controllers.get(id);
    if (controller === undefined) {
      return;
    }
    const applied: string = await this.runScript(controller, this.readerScript());
    if (applied.includes('no-article') || !applied.includes('reader')) {
      Logger.info(TAG, 'Reader mode found no article to reflow');
      TelemetryService.reportReaderExtraction(false);
      try {
        this.getUIContext().getPromptAction().showToast({ message: $r('app.string.reader_mode_unavailable') });
      } catch (error) {
        Logger.warn(TAG, `Reader mode toast unavailable: ${String(error)}`);
      }
      return;
    }
    TelemetryService.reportReaderExtraction(true);
    this.viewModel.updateTab(id, { isReader: true });
    const tab: BrowserTab | undefined = this.viewModel.getTab(id);
    if (tab !== undefined && tab.readerScrollY > 0) {
      await this.prepareScrollResume(tab);
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
    TelemetryService.setEnabled(next.telemetryEnabled);
    await this.viewModel.updateSettings(next);
    this.settings = cloneSettings(next);
    DownloadService.configurePolicy(
      next.largeDownloadThresholdMb,
      next.wifiOnlyDownloads,
      (task: DownloadTask): void => this.promptDownloadPolicy(task)
    );
    if (appearanceChanged) {
      ThemeService.apply(AppContext.getContext(), next.appearance);
    }
    ThemeService.applySurface(
      AppContext.getContext(),
      next.appearance,
      this.isActiveHome(),
      next.startPageBackgroundEnabled
    );
    await this.enforceLiveWebViewLimit(this.liveWebViewLimit());
    this.reconfigureBlocking();
  }

  private isDarkModeExcluded(url: string): boolean {
    const host: string = rawHost(url);
    return host.length > 0 && this.settings.webDarkModeExcludedHosts.includes(host);
  }

  private handlePermissionRequest(event: OnPermissionRequestEvent): void {
    const request: PermissionRequest = event.request;
    const origin: string = request.getOrigin();
    const resources: string[] = request.getAccessibleResource();
    if (origin.length === 0 || resources.length === 0) {
      request.deny();
      return;
    }
    if (resources.some((resource: string): boolean => !this.isSupportedPermissionResource(resource))) {
      request.deny();
      return;
    }
    const decision: SitePermissionDecision = this.sitePermissionDecision(origin, resources);
    if (decision === SitePermissionDecision.Allow) {
      void this.grantPermissionRequest(origin, resources, request, undefined);
    } else if (decision === SitePermissionDecision.Deny) {
      request.deny();
    } else {
      this.pendingPermissionRequest = request;
      this.pendingGeolocation = undefined;
      this.pendingSitePermission = {
        origin: origin,
        resources: resources,
        displayResources: resources.map((resource: string): Resource => this.permissionResourceLabel(resource))
      };
      this.sheet = Overlay.Permission;
    }
  }

  private handleGeolocationShow(event: OnGeolocationShowEvent): void {
    const decision: SitePermissionDecision =
      this.sitePermissionDecision(event.origin, ['LOCATION']);
    if (decision === SitePermissionDecision.Allow) {
      event.geolocation.invoke(event.origin, true, true);
    } else if (decision === SitePermissionDecision.Deny) {
      event.geolocation.invoke(event.origin, false, false);
    } else {
      this.pendingPermissionRequest = undefined;
      this.pendingGeolocation = event;
      this.pendingSitePermission = {
        origin: event.origin,
        resources: ['LOCATION'],
        displayResources: [$r('app.string.site_permission_location')]
      };
      this.sheet = Overlay.Permission;
    }
  }

  private permissionResourceLabel(resource: string): Resource {
    if (resource === 'TYPE_VIDEO_CAPTURE') {
      return $r('app.string.site_permission_camera');
    }
    if (resource === 'TYPE_AUDIO_CAPTURE') {
      return $r('app.string.site_permission_microphone');
    }
    if (resource === 'LOCATION') {
      return $r('app.string.site_permission_location');
    }
    return $r('app.string.site_permission_notifications');
  }

  private isSupportedPermissionResource(resource: string): boolean {
    return resource === 'TYPE_VIDEO_CAPTURE' || resource === 'TYPE_AUDIO_CAPTURE';
  }

  private sitePermissionDecision(origin: string, resources: string[]): SitePermissionDecision {
    const stored: SitePermission | undefined = this.settings.sitePermissions.find(
      (entry: SitePermission): boolean => entry.origin === origin);
    if (stored === undefined) {
      return SitePermissionDecision.Prompt;
    }
    let result: SitePermissionDecision = SitePermissionDecision.Allow;
    for (const resource of resources) {
      let decision: SitePermissionDecision;
      if (resource === 'TYPE_VIDEO_CAPTURE') {
        decision = stored.camera;
      } else if (resource === 'TYPE_AUDIO_CAPTURE') {
        decision = stored.microphone;
      } else if (resource === 'LOCATION') {
        decision = stored.location;
      } else {
        return SitePermissionDecision.Deny;
      }
      if (decision === SitePermissionDecision.Deny) {
        return SitePermissionDecision.Deny;
      }
      if (decision === SitePermissionDecision.Prompt) {
        result = SitePermissionDecision.Prompt;
      }
    }
    return result;
  }

  private async grantPermissionRequest(
    origin: string,
    resources: string[],
    request: PermissionRequest | undefined,
    geolocation: OnGeolocationShowEvent | undefined
  ): Promise<void> {
    const nativePermissions: Permissions[] = [];
    if (resources.includes('TYPE_VIDEO_CAPTURE')) {
      nativePermissions.push('ohos.permission.CAMERA');
    }
    if (resources.includes('TYPE_AUDIO_CAPTURE')) {
      nativePermissions.push('ohos.permission.MICROPHONE');
    }
    if (resources.includes('LOCATION')) {
      nativePermissions.push('ohos.permission.LOCATION');
    }
    const nativeAllowed: boolean = await this.requestNativePermissions(nativePermissions);
    if (!nativeAllowed) {
      request?.deny();
      geolocation?.geolocation.invoke(origin, false, false);
      await this.updateSitePermission(origin, resources, SitePermissionDecision.Deny);
      return;
    }
    if (request !== undefined) {
      request.grant(resources);
    }
    geolocation?.geolocation.invoke(origin, true, true);
    await this.updateSitePermission(origin, resources, SitePermissionDecision.Allow);
  }

  private async requestNativePermissions(permissions: Permissions[]): Promise<boolean> {
    if (permissions.length === 0) {
      return true;
    }
    try {
      const manager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
      const result: PermissionRequestResult =
        await manager.requestPermissionsFromUser(AppContext.getContext(), permissions);
      return result.authResults.length === permissions.length &&
        result.authResults.every((status: number): boolean =>
          status === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED);
    } catch (error) {
      Logger.warn(TAG, `Native site permission request failed: ${String(error)}`);
      return false;
    }
  }

  private async allowPendingPermission(): Promise<void> {
    const pending: PendingSitePermission | undefined = this.pendingSitePermission;
    if (pending === undefined) {
      return;
    }
    const request: PermissionRequest | undefined = this.pendingPermissionRequest;
    const geolocation: OnGeolocationShowEvent | undefined = this.pendingGeolocation;
    this.clearPendingPermission();
    await this.grantPermissionRequest(pending.origin, pending.resources, request, geolocation);
  }

  private async denyPendingPermission(): Promise<void> {
    const pending: PendingSitePermission | undefined = this.pendingSitePermission;
    if (pending === undefined) {
      return;
    }
    const request: PermissionRequest | undefined = this.pendingPermissionRequest;
    const geolocation: OnGeolocationShowEvent | undefined = this.pendingGeolocation;
    this.clearPendingPermission();
    request?.deny();
    geolocation?.geolocation.invoke(pending.origin, false, false);
    await this.updateSitePermission(pending.origin, pending.resources, SitePermissionDecision.Deny);
  }

  private clearPendingPermission(): void {
    this.pendingPermissionRequest = undefined;
    this.pendingGeolocation = undefined;
    this.pendingSitePermission = undefined;
    this.sheet = Overlay.None;
  }

  private async updateSitePermission(
    origin: string,
    resources: string[],
    decision: SitePermissionDecision
  ): Promise<void> {
    const next: BrowserSettings = cloneSettings(this.settings);
    let stored: SitePermission | undefined = next.sitePermissions.find(
      (entry: SitePermission): boolean => entry.origin === origin);
    if (stored === undefined) {
      stored = {
        origin: origin,
        camera: SitePermissionDecision.Prompt,
        microphone: SitePermissionDecision.Prompt,
        location: SitePermissionDecision.Prompt,
        notifications: SitePermissionDecision.Deny
      };
      next.sitePermissions.push(stored);
    }
    if (resources.includes('TYPE_VIDEO_CAPTURE')) {
      stored.camera = decision;
    }
    if (resources.includes('TYPE_AUDIO_CAPTURE')) {
      stored.microphone = decision;
    }
    if (resources.includes('LOCATION')) {
      stored.location = decision;
    }
    stored.notifications = SitePermissionDecision.Deny;
    await this.applySettings(next);
  }

  private async removeSitePermission(origin: string): Promise<void> {
    const next: BrowserSettings = cloneSettings(this.settings);
    next.sitePermissions = next.sitePermissions.filter(
      (entry: SitePermission): boolean => entry.origin !== origin);
    await this.applySettings(next);
  }

  /**
   * Cycles a single permission in the settings list. The stored decision is
   * passed in as the *current* value so tapping always moves to the next one.
   */
  private async toggleSitePermissionDecision(
    origin: string,
    kind: string,
    current: SitePermissionDecision
  ): Promise<void> {
    const nextDecision: SitePermissionDecision = current === SitePermissionDecision.Allow
      ? SitePermissionDecision.Deny
      : SitePermissionDecision.Allow;
    const next: BrowserSettings = cloneSettings(this.settings);
    const stored: SitePermission | undefined = next.sitePermissions.find(
      (entry: SitePermission): boolean => entry.origin === origin);
    if (stored === undefined) {
      return;
    }
    if (kind === 'camera') {
      stored.camera = nextDecision;
    } else if (kind === 'microphone') {
      stored.microphone = nextDecision;
    } else if (kind === 'location') {
      stored.location = nextDecision;
    } else if (kind === 'notifications') {
      stored.notifications = nextDecision;
    }
    await this.applySettings(next);
  }

  private async toggleCurrentSiteDarkMode(): Promise<void> {
    const host: string = rawHost(this.activeTab()?.url ?? '');
    if (host.length === 0) {
      return;
    }
    const next: BrowserSettings = cloneSettings(this.settings);
    const index: number = next.webDarkModeExcludedHosts.indexOf(host);
    if (index >= 0) {
      next.webDarkModeExcludedHosts.splice(index, 1);
    } else {
      next.webDarkModeExcludedHosts.push(host);
    }
    await this.applySettings(next);
    this.runOnActive((controller: webview.WebviewController): void => controller.refresh());
  }

  private async updateRules(): Promise<void> {
    const updated: boolean = await this.viewModel.adsBlockService.updateRules(true);
    try {
      if (updated) {
        this.rulesLastUpdatedAt = this.viewModel.adsBlockService.lastUpdatedAt;
        this.getUIContext().getPromptAction().showToast({ message: $r('app.string.rules_update_success') });
      } else {
        this.getUIContext().getPromptAction().showToast({ message: $r('app.string.rules_update_failed') });
      }
    } catch (error) {
      Logger.warn(TAG, `Rules update toast unavailable: ${String(error)}`);
    }
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

  private async removeQuickSite(url: string): Promise<void> {
    await this.viewModel.setQuickSiteHidden(url, true);
    this.syncState();
  }

  private async importBookmarks(): Promise<void> {
    const importedItems = await BookmarkTransferService.importFromPicker(AppContext.getContext());
    if (importedItems.length === 0) {
      return;
    }
    const imported: number = await this.viewModel.importSavedItems(importedItems);
    this.syncState();
    try {
      this.getUIContext().getPromptAction().showToast({
        message: `${imported}${$r('app.string.bookmark_imported_suffix')}`
      });
    } catch (error) {
      Logger.warn(TAG, `Bookmark import toast unavailable: ${String(error)}`);
    }
  }

  private setOnboardingSearchEngine(engine: SearchEngine): void {
    const next: BrowserSettings = cloneSettings(this.settings);
    next.searchEngine = engine;
    this.settings = next;
  }

  private async finishOnboarding(): Promise<void> {
    const next: BrowserSettings = cloneSettings(this.settings);
    next.onboardingCompleted = true;
    await this.viewModel.updateSettings(next);
    this.settings = cloneSettings(next);
    this.sheet = Overlay.None;
  }

  private async exportBookmarks(): Promise<void> {
    const exported: boolean = await BookmarkTransferService.exportToPicker(
      AppContext.getContext(), this.viewModel.savedItems);
    if (!exported) {
      return;
    }
    try {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.bookmark_exported') });
    } catch (error) {
      Logger.warn(TAG, `Bookmark export toast unavailable: ${String(error)}`);
    }
  }

  private async toggleQuickSites(): Promise<void> {
    const next: BrowserSettings = cloneSettings(this.settings);
    next.quickSitesEnabled = !next.quickSitesEnabled;
    await this.applySettings(next);
  }

  private async toggleStartPageBackground(): Promise<void> {
    const next: BrowserSettings = cloneSettings(this.settings);
    next.startPageBackgroundEnabled = !next.startPageBackgroundEnabled;
    await this.applySettings(next);
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

  private async clearBrowsingData(selection: ClearDataSelection): Promise<void> {
    const controllers: webview.WebviewController[] = [];
    this.controllers.forEach((controller: webview.WebviewController) => controllers.push(controller));
    if (selection.cookies) {
      PrivacyService.clearCookiesAndStorage();
    }
    if (selection.cache) {
      PrivacyService.clearCache(controllers);
    }
    if (selection.history) {
      await this.viewModel.clearHistory(this.clearDataCutoff(selection.range));
    }
    if (selection.permissions) {
      await this.viewModel.clearAllowedHosts();
      await this.viewModel.clearSitePermissions();
      this.viewModel.adsBlockService.applyAllowedHosts(this.viewModel.getAllowedHosts());
    }
    this.syncState();
    try {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.clear_data_completed') });
    } catch (error) {
      Logger.warn(TAG, `Clear data toast unavailable: ${String(error)}`);
    }
  }

  private clearDataCutoff(range: ClearDataRange): number {
    if (range === ClearDataRange.All) {
      return 0;
    }
    return Date.now() - Number(range) * 24 * 60 * 60 * 1000;
  }

  // ------------------------------------------------------------- web events

  private handlePageBegin(id: string, url: string): void {
    this.dismissResumePrompt();
    this.pageScrollOffsets.set(id, 0);
    this.pageLoadStartedAt.set(id, Date.now());
    if (id === this.activeTabId) {
      this.isActivePageAtTop = true;
    }
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
      // The badge counts what was stopped on the page in front of the user, so
      // it starts again with the document. Per-site totals live in the panel.
      blocked: emptyBlockStats(),
      securityState: Index.securityStateForUrl(url),
      lastVisitedAt: Date.now()
    });
    this.syncTab(id);
    // Element hiding follows the same policy as the network blocker: a site the
    // user allow-listed gets neither.
    if (this.settings.blockAds && !this.viewModel.isHostAllowed(url)) {
      void this.injectCosmeticRules(id, url);
    }
  }

  private async handlePageEnd(id: string, url: string): Promise<void> {
    const startedAt: number | undefined = this.pageLoadStartedAt.get(id);
    if (startedAt !== undefined) {
      TelemetryService.recordPageLoad(displayHost(url), Date.now() - startedAt);
    }
    // Chromium commits an error page like any other document, so this fires
    // after a failure too. Clearing the error here would wipe what the kernel
    // just reported; the start of the next navigation is what clears it.
    this.viewModel.updateTab(id, {
      url: url,
      isLoading: false,
      progress: 100,
      securityState: Index.securityStateForUrl(url),
      lastVisitedAt: Date.now()
    });
    this.refreshNavigationState(id);
    const tab: BrowserTab | undefined = this.viewModel.getTab(id);
    if (tab !== undefined) {
      await this.viewModel.recordPageVisit(tab);
      this.viewModel.persistSession();
      await this.prepareScrollResume(tab);
      if (tab.formDraft.length > 0) {
        const controller: webview.WebviewController | undefined = this.controllers.get(id);
        if (controller !== undefined) {
          await this.runScript(controller, restoreFormDraftScript(tab.formDraft));
        }
      }
    }
    await this.enhancePage(id);
    if (Index.securityStateForUrl(url) === SecurityState.Insecure) {
      const controller: webview.WebviewController | undefined = this.controllers.get(id);
      if (controller !== undefined) {
        await this.runScript(controller, PASSWORD_FIELD_WATCHER_SCRIPT);
      }
    }
    this.syncState();
  }

  /**
   * Insecure pages can still contain password fields (login forms behind HTTP).
   * When the user focuses one, ArkWeb raises our JS proxy and we warn once.
   */
  private async handlePasswordFocusOnInsecurePage(id: string): Promise<void> {
    const tab: BrowserTab | undefined = this.viewModel.getTab(id);
    if (tab === undefined || id !== this.activeTabId ||
      tab.securityState !== SecurityState.Insecure) {
      return;
    }
    try {
      await this.getUIContext().getPromptAction().showToast({
        message: $r('app.string.security_password_warning')
      });
    } catch (error) {
      Logger.warn(TAG, `Password warning toast unavailable: ${String(error)}`);
    }
  }

  private async handleScaleChange(id: string, scale: number): Promise<void> {
    if (id !== this.activeTabId) {
      return;
    }
    const tab: BrowserTab | undefined = this.viewModel.getTab(id);
    if (tab !== undefined && !tab.isPrivate) {
      await this.viewModel.rememberSiteZoom(tab.url, scale);
      this.settings = cloneSettings(this.viewModel.settings);
    }
  }

  private async openLongPressActions(id: string): Promise<void> {
    if (id !== this.activeTabId) {
      return;
    }
    const controller: webview.WebviewController | undefined = this.controllers.get(id);
    if (controller === undefined) {
      return;
    }
    const target: WebLongPressTarget | undefined = await WebKernelService.getLongPressTarget(controller);
    if (target === undefined) {
      return;
    }
    this.longPressTarget = target;
    this.sheet = Overlay.LinkActions;
  }

  private closeLongPressActions(): void {
    this.longPressTarget = undefined;
    this.sheet = Overlay.None;
  }

  private async performLongPressAction(key: string): Promise<void> {
    const target: WebLongPressTarget | undefined = this.longPressTarget;
    if (target === undefined) {
      return;
    }
    if (key === 'link_open_background') {
      const tab: BrowserTab | undefined = this.viewModel.addBackgroundTab(target.url, false);
      if (tab !== undefined) {
        // syncState first: activateTab looks the tab up in the synced list.
        this.syncState();
        void this.activateTab(tab.id);
      }
      this.closeLongPressActions();
      return;
    }
    if (key === 'link_copy') {
      const outcome: ShareOutcome = await ShareService.copy(target.url);
      if (outcome === ShareOutcome.Copied) {
        this.showCopyToast();
      }
      this.closeLongPressActions();
      return;
    }
    if (key === 'link_share' || key === 'image_share') {
      await ShareService.share(AppContext.getContext(), target.url, target.title);
      this.closeLongPressActions();
      return;
    }
    if (key === 'link_save_later') {
      await this.viewModel.saveUrlForLater(target.url, target.title);
      this.syncState();
      this.closeLongPressActions();
      return;
    }
    if (key === 'image_save') {
      const controller: webview.WebviewController | undefined = this.controllers.get(this.activeTabId);
      if (controller !== undefined) {
        await this.runScript(controller, triggerDownloadScript(target.url));
      }
      this.closeLongPressActions();
    }
  }

  private async injectCosmeticRules(id: string, pageUrl: string): Promise<void> {
    const script: string = AdsBlockService.cosmeticScriptFor(pageUrl);
    const controller: webview.WebviewController | undefined = this.controllers.get(id);
    if (script.length === 0 || controller === undefined) {
      return;
    }
    await this.runScript(controller, script);
  }

  private edgeNavigate(id: string, isBack: boolean): void {
    if (id !== this.activeTabId) {
      return;
    }
    this.runOnActive((controller: webview.WebviewController) => {
      if (isBack) {
        WebKernelService.goBack(controller);
      } else {
        WebKernelService.goForward(controller);
      }
    });
  }

  private handleTitle(id: string, title: string): void {
    const tab: BrowserTab | undefined = this.viewModel.getTab(id);
    const fallback: string = tab === undefined ? '' : displayHost(tab.url);
    this.viewModel.updateTab(id, { title: title.length > 0 ? title : fallback });
    this.syncTab(id);
  }

  private handleProgress(id: string, progress: number): void {
    // Progress keeps ticking while the kernel commits its own error page, so
    // this must not clear the error the kernel just reported. Only the start of
    // a navigation clears it.
    this.viewModel.updateTab(id, {
      progress: WebKernelService.clampProgress(progress),
      isLoading: progress < 100
    });
    this.syncTab(id);
  }

  private pullRefresh(id: string): void {
    if (id !== this.activeTabId || !this.isActivePageAtTop) {
      return;
    }
    const tab: BrowserTab | undefined = this.viewModel.getTab(id);
    const controller: webview.WebviewController | undefined = this.controllers.get(id);
    if (tab === undefined || controller === undefined || tab.isLoading) {
      return;
    }
    this.dismissResumePrompt();
    this.isActivePageAtTop = true;
    this.viewModel.updateTab(id, { isLoading: true, progress: 0, loadError: LoadErrorKind.None });
    this.syncTab(id);
    WebKernelService.reload(controller);
  }

  private handlePageScroll(id: string, offsetY: number): void {
    if (id === this.activeTabId) {
      const isAtTop: boolean = offsetY <= 8;
      if (isAtTop !== this.isActivePageAtTop) {
        this.isActivePageAtTop = isAtTop;
      }
    }
    const tab: BrowserTab | undefined = this.viewModel.getTab(id);
    if (tab === undefined || id !== this.activeTabId || tab.isLoading || this.sheet !== Overlay.None) {
      return;
    }
    const previous: number = this.pageScrollOffsets.get(id) ?? offsetY;
    this.pageScrollOffsets.set(id, offsetY);
    const lastPersisted: number = this.persistedPageScrollOffsets.get(id) ?? 0;
    if (Math.abs(offsetY - lastPersisted) >= 120 || offsetY <= 8) {
      const savedAt: number = Date.now();
      if (tab.isReader) {
        this.viewModel.updateTab(id, { readerScrollY: offsetY, readerScrollSavedAt: savedAt });
      } else {
        this.viewModel.updateTab(id, { scrollY: offsetY, scrollSavedAt: savedAt });
      }
      this.persistedPageScrollOffsets.set(id, offsetY);
      this.viewModel.persistSession();
    }
    if (!this.settings.autoHideToolbarEnabled) {
      return;
    }
    const delta: number = offsetY - previous;
    if (offsetY <= 8 || delta < -4) {
      this.showCapsule();
    } else if (offsetY > 36 && delta > 4) {
      this.setCapsuleHidden(true);
    }
  }

  private showCapsule(): void {
    this.setCapsuleHidden(false);
  }

  /** Collapse and expand are the same motion in both directions, so animate both. */
  private setCapsuleHidden(hidden: boolean): void {
    if (this.isCapsuleHidden === hidden) {
      return;
    }
    this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseOut }, (): void => {
      this.isCapsuleHidden = hidden;
    });
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

  /**
   * ArkWeb reports certificate problems separately from page load errors, with
   * the DER certificate chain available so the panel can show a real summary.
   */
  private async handleSslError(id: string, code: SslError, chain: Array<Uint8Array>): Promise<void> {
    if (code === SslError.Invalid) {
      return;
    }
    Logger.warn(TAG, `SSL ${code} for tab ${id}`);
    const summary: CertificateSummary | undefined = await CertificateService.summarizeChain(chain);
    this.viewModel.updateTab(id, {
      loadError: LoadErrorKind.Certificate,
      securityState: SecurityState.CertificateError,
      certificate: summary
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

  private activeErrorKind(): LoadErrorKind {
    return this.activeTab()?.loadError ?? LoadErrorKind.None;
  }

  private errorTitle(kind: LoadErrorKind): Resource {
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

  private errorMessage(kind: LoadErrorKind): Resource {
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
    let malicious: number = 0;
    for (const url of urls) {
      if (Index.isMaliciousUrl(url)) {
        malicious += 1;
      } else if (isTrackerUrl(url)) {
        trackers += 1;
      } else {
        ads += 1;
      }
    }
    await this.viewModel.recordBlocked(id, {
      ads: ads,
      trackers: trackers,
      malicious: malicious,
      popups: 0,
      cookieBanners: 0
    });
    this.syncTab(id);
    if (id === this.activeTabId) {
      this.weeklyBlocked = this.viewModel.getWeeklyBlocked();
      this.cumulativeBlocked = this.viewModel.getCumulativeBlocked();
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

    await this.runScript(controller, FORCE_ZOOM_SCRIPT);
    await this.runScript(controller, LONG_PRESS_TARGET_SCRIPT);

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
      malicious: base.malicious + (parsed.malicious ?? 0),
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
    const savedAt: number = Date.now();
    if (tab.isReader) {
      this.viewModel.updateTab(id, { readerScrollY: position, readerScrollSavedAt: savedAt });
    } else {
      this.viewModel.updateTab(id, { scrollY: position, scrollSavedAt: savedAt });
    }
    this.persistedPageScrollOffsets.set(id, position);
    this.viewModel.persistSession();
  }

  private async captureFormDraft(id: string): Promise<void> {
    const controller: webview.WebviewController | undefined = this.controllers.get(id);
    const tab: BrowserTab | undefined = this.viewModel.getTab(id);
    if (controller === undefined || tab === undefined || isHomeUrl(tab.url)) {
      return;
    }
    const raw: string = await this.runScript(controller, READ_FORM_DRAFT_SCRIPT);
    const draft: string = this.parseScriptString(raw);
    if (draft.length > 0) {
      this.viewModel.updateTab(id, { formDraft: draft });
      this.viewModel.persistSession();
    }
  }

  private async prepareScrollResume(tab: BrowserTab): Promise<void> {
    const controller: webview.WebviewController | undefined = this.controllers.get(tab.id);
    const position: number = tab.isReader ? tab.readerScrollY : tab.scrollY;
    const savedAt: number = tab.isReader ? tab.readerScrollSavedAt : tab.scrollSavedAt;
    if (controller === undefined || position <= 0) {
      return;
    }
    const windowMs: number = RESUME_WINDOW_DAYS * 24 * 60 * 60 * 1000;
    if (savedAt <= 0 || Date.now() - savedAt > windowMs) {
      this.clearScrollPosition(tab);
      return;
    }
    if (tab.id === this.activeTabId) {
      this.resumeRequest = { tabId: tab.id, position: position, isReader: tab.isReader };
      this.scheduleResumeDismissal(tab.id);
      return;
    }
    await this.applyScrollPosition(tab.id, position);
  }

  private async continueResume(request: ResumeRequest): Promise<void> {
    this.dismissResumePrompt();
    await this.applyScrollPosition(request.tabId, request.position);
  }

  private startResumeFromTop(request: ResumeRequest): void {
    const tab: BrowserTab | undefined = this.viewModel.getTab(request.tabId);
    if (tab !== undefined) {
      this.clearScrollPosition(tab);
    }
    this.dismissResumePrompt();
  }

  private async applyScrollPosition(id: string, position: number): Promise<void> {
    const controller: webview.WebviewController | undefined = this.controllers.get(id);
    if (controller !== undefined && position > 0) {
      await this.runScript(controller, restoreScrollPositionScript(position));
    }
  }

  private clearScrollPosition(tab: BrowserTab): void {
    if (tab.isReader) {
      this.viewModel.updateTab(tab.id, { readerScrollY: 0, readerScrollSavedAt: 0 });
    } else {
      this.viewModel.updateTab(tab.id, { scrollY: 0, scrollSavedAt: 0 });
    }
    this.viewModel.persistSession();
  }

  private dismissResumePrompt(): void {
    this.resumeToken += 1;
    this.resumeRequest = undefined;
  }

  /** Ignoring the snackbar keeps the saved position; only the close button drops it. */
  private scheduleResumeDismissal(tabId: string): void {
    this.resumeToken += 1;
    const token: number = this.resumeToken;
    setTimeout((): void => {
      if (token === this.resumeToken && this.resumeRequest?.tabId === tabId) {
        this.resumeRequest = undefined;
      }
    }, RESUME_PROMPT_TIMEOUT_MS);
  }

  // ------------------------------------------------------------------ state

  private syncState(): void {
    this.tabs = this.viewModel.tabs.map((tab: BrowserTab) => cloneTab(tab));
    this.activeTabId = this.viewModel.activeTabId;
    this.recentTabs = this.viewModel.recentTabs(RECENT_TAB_LIMIT);
    this.settings = cloneSettings(this.viewModel.settings);
    this.history = this.viewModel.history.map((entry: HistoryEntry) => cloneHistoryEntry(entry));
    this.quickSites = this.viewModel.getQuickSites();
    this.weeklyBlocked = this.viewModel.getWeeklyBlocked();
    this.cumulativeBlocked = this.viewModel.getCumulativeBlocked();
    const url: string = this.activeTab()?.url ?? '';
    this.isActiveBookmarked = this.viewModel.isSaved(url);
    this.isActiveSavedForLater = this.viewModel.isSavedForLater(url);
    this.isSiteAllowed = this.viewModel.isHostAllowed(url);
    ThemeService.applySurface(
      AppContext.getContext(),
      this.settings.appearance,
      isHomeUrl(url),
      this.settings.startPageBackgroundEnabled
    );
  }

  private static isMaliciousUrl(url: string): boolean {
    const value: string = url.toLowerCase();
    const patterns: string[] = [
      'malware', 'phishing', 'phish', 'trojan', 'ransom', 'exploit',
      'cryptominer', 'coinhive', 'malvertising'
    ];
    return patterns.some((pattern: string) => value.includes(pattern));
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
