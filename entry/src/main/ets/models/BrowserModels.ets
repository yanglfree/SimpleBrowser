/**
 * Data model for the minimal browser.
 *
 * ArkTS forbids untyped object literals and object spread, so every model is an
 * interface with an explicit `clone*` helper. State updates always publish fresh
 * objects so that @State / @Prop observe the change.
 */

export enum AppearanceMode {
  System = 0,
  Light = 1,
  Dark = 2
}

export enum WebDarkModePreference {
  System = 0,
  Light = 1,
  Dark = 2
}

export enum SitePermissionDecision {
  Prompt = 0,
  Allow = 1,
  Deny = 2
}

export enum RuleStrength {
  Standard = 0,
  Strict = 1
}

export enum SearchEngine {
  Bing = 0,
  Baidu = 1,
  Google = 2,
  DuckDuckGo = 3
}

export enum ReaderPaper {
  White = 0,
  Sepia = 1,
  Night = 2
}

export interface ReaderTheme {
  background: string;
  pillBackground: string;
  pillBorder: string;
  textPrimary: string;
  textSecondary: string;
  border: string;
  isDark: boolean;
  body: string;
  title: string;
}

export function getReaderTheme(paper: ReaderPaper): ReaderTheme {
  if (paper === ReaderPaper.White) {
    return {
      background: '#FFFFFF',
      pillBackground: '#F4F3EF',
      pillBorder: '#E6E3DC',
      textPrimary: '#1A1A18',
      textSecondary: '#7A7870',
      border: '#EAE7E1',
      isDark: false,
      body: '#3A3934',
      title: '#1A1A18'
    };
  }
  if (paper === ReaderPaper.Night) {
    return {
      background: '#26251F',
      pillBackground: '#33322B',
      pillBorder: '#424037',
      textPrimary: '#F5F3EE',
      textSecondary: '#8E8B82',
      border: '#383630',
      isDark: true,
      body: '#C9C6BE',
      title: '#F5F3EE'
    };
  }
  return {
    background: '#F1EFEA',
    pillBackground: '#E6E3DC',
    pillBorder: '#D8D4CA',
    textPrimary: '#1A1A18',
    textSecondary: '#7A7870',
    border: '#E2DDD5',
    isDark: false,
    body: '#3A3934',
    title: '#1A1A18'
  };
}

export enum StartPageBackgroundSource {
  BuiltIn = 0,
  Custom = 1
}

export const QUICK_SITE_LIMIT_MIN: number = 4;
export const QUICK_SITE_LIMIT_MAX: number = 8;
export const QUICK_SITE_LIMIT_DEFAULT: number = 6;

export enum SuggestionKind {
  History = 0,
  Bookmark = 1,
  Search = 2
}

export enum SavedItemState {
  Read = 0,
  Unread = 1
}

export enum LoadErrorKind {
  None = 0,
  Offline = 1,
  Timeout = 2,
  Dns = 3,
  Certificate = 4,
  Unknown = 5
}

export enum SecurityState {
  Unknown = 0,
  Secure = 1,
  Insecure = 2,
  CertificateError = 3
}

export enum UserAgentPreference {
  Default = 0,
  Mobile = 1,
  Desktop = 2
}

/** Parsed X.509 summary shown in the security panel. */
export interface CertificateSummary {
  subject: string;
  issuer: string;
  validFrom: string;
  validTo: string;
}

export enum TabExpiry {
  OneDay = 1,
  ThreeDays = 3,
  SevenDays = 7,
  Never = 0
}

/** Requests the blocker stopped, split by what they were. */
export interface BlockStats {
  ads: number;
  trackers: number;
  malicious: number;
  popups: number;
  cookieBanners: number;
}

export interface SiteBlockStats {
  host: string;
  stats: BlockStats;
}

export interface DailyBlockCount {
  /** `YYYY-MM-DD` in local time. */
  day: string;
  count: number;
}

export interface BrowserTab {
  id: string;
  url: string;
  title: string;
  isPrivate: boolean;
  isLoading: boolean;
  progress: number;
  isDesktop: boolean;
  isPinned: boolean;
  isReader: boolean;
  canGoBack: boolean;
  canGoForward: boolean;
  blocked: BlockStats;
  faviconUrl: string;
  lastVisitedAt: number;
  scrollY: number;
  readerScrollY: number;
  scrollSavedAt: number;
  readerScrollSavedAt: number;
  formDraft: string;
  loadError: LoadErrorKind;
  securityState: SecurityState;
  certificate?: CertificateSummary;
}

export interface BrowserTabUpdate {
  url?: string;
  title?: string;
  isLoading?: boolean;
  progress?: number;
  isDesktop?: boolean;
  isPinned?: boolean;
  isReader?: boolean;
  canGoBack?: boolean;
  canGoForward?: boolean;
  blocked?: BlockStats;
  faviconUrl?: string;
  lastVisitedAt?: number;
  scrollY?: number;
  readerScrollY?: number;
  scrollSavedAt?: number;
  readerScrollSavedAt?: number;
  formDraft?: string;
  loadError?: LoadErrorKind;
  securityState?: SecurityState;
  certificate?: CertificateSummary;
}

export interface BrowserSession {
  tabs: BrowserTab[];
  activeTabId: string;
}

/** Unified bookmark/read-later entry. `isRead` replaces separate collections. */
export interface SavedItem {
  id: string;
  title: string;
  url: string;
  createdAt: number;
  updatedAt: number;
  isRead: boolean;
  tags: string[];
}

export interface HistoryEntry {
  id: string;
  title: string;
  url: string;
  visitedAt: number;
  visitCount: number;
}

export interface BrowserSettings {
  blockAds: boolean;
  blockTrackers: boolean;
  ruleStrength: RuleStrength;
  searchEngine: SearchEngine;
  customSearchTemplate: string;
  searchSuggestionsEnabled: boolean;
  gesturesEnabled: boolean;
  gestureActionsEnabled: boolean;
  gestureTabSwitchEnabled: boolean;
  gestureBlockingEnabled: boolean;
  autoHideToolbarEnabled: boolean;
  quickSitesEnabled: boolean;
  quickSiteLimit: number;
  startPageBackgroundEnabled: boolean;
  startPageBackgroundSource: StartPageBackgroundSource;
  customStartPageBackgroundUri: string;
  tabExpiryDays: TabExpiry;
  historyRetentionDays: number;
  liveWebViewLimit: number;
  downloadConcurrency: number;
  largeDownloadThresholdMb: number;
  wifiOnlyDownloads: boolean;
  tabSoftLimit: number;
  minimumFontSize: number;
  siteZoomRatios: SiteZoomRatio[];
  defaultUserAgentPreference: UserAgentPreference;
  siteUserAgentPreferences: SiteUserAgentPreference[];
  onboardingCompleted: boolean;
  appearance: AppearanceMode;
  webDarkMode: WebDarkModePreference;
  webDarkModeExcludedHosts: string[];
  sitePermissions: SitePermission[];
  clearCookiesOnTabClose: boolean;
  telemetryEnabled: boolean;
  readerFontSize: number;
  readerLineHeight: number;
  readerPaper: ReaderPaper;
}

/** Persisted page scale in percent, keyed by the normalized host. */
export interface SiteZoomRatio {
  host: string;
  percent: number;
}

export interface SiteUserAgentPreference {
  host: string;
  preference: UserAgentPreference;
}

export interface SitePermission {
  origin: string;
  camera: SitePermissionDecision;
  microphone: SitePermissionDecision;
  location: SitePermissionDecision;
  notifications: SitePermissionDecision;
}

/** A tile on the start page. `colorIndex` is 0-5 and maps to `site_tile_*` colors. */
export interface QuickSite {
  title: string;
  url: string;
  badge: string;
  colorIndex: number;
}

export interface Suggestion {
  id: string;
  kind: SuggestionKind;
  title: string;
  subtitle: string;
  url: string;
}

export function emptyBlockStats(): BlockStats {
  return { ads: 0, trackers: 0, malicious: 0, popups: 0, cookieBanners: 0 };
}

export function cloneBlockStats(stats: BlockStats): BlockStats {
  return {
    ads: stats.ads,
    trackers: stats.trackers,
    malicious: stats.malicious ?? 0,
    popups: stats.popups,
    cookieBanners: stats.cookieBanners
  };
}

export function addBlockStats(base: BlockStats, delta: BlockStats): BlockStats {
  return {
    ads: base.ads + delta.ads,
    trackers: base.trackers + delta.trackers,
    malicious: base.malicious + delta.malicious,
    popups: base.popups + delta.popups,
    cookieBanners: base.cookieBanners + delta.cookieBanners
  };
}

export function totalBlocked(stats: BlockStats): number {
  return stats.ads + stats.trackers + stats.malicious + stats.popups + stats.cookieBanners;
}

export function defaultBrowserSettings(): BrowserSettings {
  return {
    blockAds: true,
    blockTrackers: true,
    ruleStrength: RuleStrength.Standard,
    searchEngine: SearchEngine.Bing,
    customSearchTemplate: '',
    searchSuggestionsEnabled: false,
    gesturesEnabled: true,
    gestureActionsEnabled: true,
    gestureTabSwitchEnabled: true,
    gestureBlockingEnabled: true,
    autoHideToolbarEnabled: true,
    quickSitesEnabled: true,
    quickSiteLimit: QUICK_SITE_LIMIT_DEFAULT,
    startPageBackgroundEnabled: true,
    startPageBackgroundSource: StartPageBackgroundSource.BuiltIn,
    customStartPageBackgroundUri: '',
    tabExpiryDays: TabExpiry.SevenDays,
    historyRetentionDays: 30,
    liveWebViewLimit: 4,
    downloadConcurrency: 2,
    largeDownloadThresholdMb: 50,
    wifiOnlyDownloads: false,
    tabSoftLimit: 12,
    minimumFontSize: 14,
    siteZoomRatios: [],
    defaultUserAgentPreference: UserAgentPreference.Default,
    siteUserAgentPreferences: [],
    onboardingCompleted: false,
    appearance: AppearanceMode.System,
    webDarkMode: WebDarkModePreference.System,
    webDarkModeExcludedHosts: [],
    sitePermissions: [],
    clearCookiesOnTabClose: false,
    telemetryEnabled: false,
    readerFontSize: 17,
    readerLineHeight: 205,
    readerPaper: ReaderPaper.Sepia
  };
}

export function cloneTab(tab: BrowserTab): BrowserTab {
  return {
    id: tab.id,
    url: tab.url,
    title: tab.title,
    isPrivate: tab.isPrivate,
    isLoading: tab.isLoading,
    progress: tab.progress,
    isDesktop: tab.isDesktop,
    isPinned: tab.isPinned,
    isReader: tab.isReader,
    canGoBack: tab.canGoBack,
    canGoForward: tab.canGoForward,
    blocked: cloneBlockStats(tab.blocked),
    faviconUrl: tab.faviconUrl,
    lastVisitedAt: tab.lastVisitedAt,
    scrollY: tab.scrollY,
    readerScrollY: tab.readerScrollY,
    scrollSavedAt: tab.scrollSavedAt,
    readerScrollSavedAt: tab.readerScrollSavedAt,
    formDraft: tab.formDraft,
    loadError: tab.loadError,
    securityState: tab.securityState,
    certificate: tab.certificate
  };
}

export function cloneSavedItem(item: SavedItem): SavedItem {
  return {
    id: item.id,
    title: item.title,
    url: item.url,
    createdAt: item.createdAt,
    updatedAt: item.updatedAt,
    isRead: item.isRead,
    tags: item.tags.slice(0)
  };
}

export function cloneHistoryEntry(entry: HistoryEntry): HistoryEntry {
  return {
    id: entry.id,
    title: entry.title,
    url: entry.url,
    visitedAt: entry.visitedAt,
    visitCount: entry.visitCount
  };
}

export function normalizeBrowserSettings(settings: BrowserSettings): BrowserSettings {
  const isContentProtectionEnabled: boolean = settings.blockAds || settings.blockTrackers;
  return {
    blockAds: isContentProtectionEnabled,
    blockTrackers: isContentProtectionEnabled,
    ruleStrength: settings.ruleStrength,
    searchEngine: settings.searchEngine,
    customSearchTemplate: settings.customSearchTemplate,
    searchSuggestionsEnabled: settings.searchSuggestionsEnabled,
    gesturesEnabled: settings.gesturesEnabled,
    gestureActionsEnabled: settings.gestureActionsEnabled,
    gestureTabSwitchEnabled: settings.gestureTabSwitchEnabled,
    gestureBlockingEnabled: settings.gestureBlockingEnabled,
    autoHideToolbarEnabled: settings.autoHideToolbarEnabled,
    quickSitesEnabled: settings.quickSitesEnabled,
    quickSiteLimit: Math.min(QUICK_SITE_LIMIT_MAX, Math.max(QUICK_SITE_LIMIT_MIN, settings.quickSiteLimit)),
    startPageBackgroundEnabled: settings.startPageBackgroundEnabled,
    startPageBackgroundSource: settings.startPageBackgroundSource,
    customStartPageBackgroundUri: settings.customStartPageBackgroundUri,
    tabExpiryDays: settings.tabExpiryDays,
    historyRetentionDays: settings.historyRetentionDays,
    liveWebViewLimit: settings.liveWebViewLimit,
    downloadConcurrency: settings.downloadConcurrency,
    largeDownloadThresholdMb: settings.largeDownloadThresholdMb,
    wifiOnlyDownloads: settings.wifiOnlyDownloads,
    tabSoftLimit: settings.tabSoftLimit,
    minimumFontSize: settings.minimumFontSize,
    // ArkWeb scale callbacks include the device scale factor, so values saved
    // by older builds cannot be distinguished from deliberate page zoom.
    siteZoomRatios: [],
    defaultUserAgentPreference: settings.defaultUserAgentPreference ?? UserAgentPreference.Default,
    siteUserAgentPreferences: (settings.siteUserAgentPreferences ?? [])
      .map((entry: SiteUserAgentPreference): SiteUserAgentPreference => ({
        host: entry.host,
        preference: entry.preference
      })),
    onboardingCompleted: settings.onboardingCompleted,
    appearance: settings.appearance,
    webDarkMode: settings.webDarkMode,
    webDarkModeExcludedHosts: settings.webDarkModeExcludedHosts.slice(0),
    sitePermissions: settings.sitePermissions.map((entry: SitePermission): SitePermission => ({
      origin: entry.origin,
      camera: entry.camera,
      microphone: entry.microphone,
      location: entry.location,
      notifications: SitePermissionDecision.Deny
    })),
    clearCookiesOnTabClose: settings.clearCookiesOnTabClose,
    telemetryEnabled: settings.telemetryEnabled === true,
    readerFontSize: settings.readerFontSize,
    readerLineHeight: settings.readerLineHeight,
    readerPaper: settings.readerPaper
  };
}

export function cloneSettings(settings: BrowserSettings): BrowserSettings {
  return normalizeBrowserSettings(settings);
}

export function cloneSiteStats(entry: SiteBlockStats): SiteBlockStats {
  return { host: entry.host, stats: cloneBlockStats(entry.stats) };
}

export function cloneDailyCount(entry: DailyBlockCount): DailyBlockCount {
  return { day: entry.day, count: entry.count };
}

export function cloneQuickSite(site: QuickSite): QuickSite {
  return {
    title: site.title,
    url: site.url,
    badge: site.badge,
    colorIndex: site.colorIndex
  };
}

export function moveQuickSite(sites: QuickSite[], from: number, to: number): QuickSite[] {
  if (from < 0 || to < 0 || from >= sites.length || to >= sites.length || from === to) {
    return sites.map((site: QuickSite): QuickSite => cloneQuickSite(site));
  }
  const reordered: QuickSite[] = sites.map((site: QuickSite): QuickSite => cloneQuickSite(site));
  const moved: QuickSite[] = reordered.splice(from, 1);
  reordered.splice(to, 0, moved[0]);
  return reordered;
}

export function quickSiteDropTarget(count: number, insertIndex: number): number {
  if (count <= 0 || insertIndex < 0 || insertIndex > count) {
    return -1;
  }
  return Math.min(insertIndex, count - 1);
}

/**
 * Dragging must not smuggle a tab across a boundary the rest of the app treats as
 * fixed: pinned tabs lead the strip and private tabs never mix with normal ones.
 * The drop lands on the nearest index inside the dragged tab's own run instead of
 * being rejected, so a long drag still does the most it legally can.
 */
export function clampTabMoveTarget(tabs: BrowserTab[], from: number, to: number): number {
  if (from < 0 || from >= tabs.length || to < 0) {
    return -1;
  }
  const moving: BrowserTab = tabs[from];
  let first: number = from;
  while (first > 0 && sharesTabGroup(tabs[first - 1], moving)) {
    first -= 1;
  }
  let last: number = from;
  while (last < tabs.length - 1 && sharesTabGroup(tabs[last + 1], moving)) {
    last += 1;
  }
  const clamped: number = Math.min(Math.max(to, first), last);
  return clamped === from ? -1 : clamped;
}

function sharesTabGroup(left: BrowserTab, right: BrowserTab): boolean {
  return left.isPrivate === right.isPrivate && left.isPinned === right.isPinned;
}

/** Where the start page looks up the cached icon file for a tile. */
export interface QuickSiteIcon {
  host: string;
  path: string;
}

export function quickSiteIconPath(icons: QuickSiteIcon[], host: string): string {
  if (host.length === 0) {
    return '';
  }
  const match: QuickSiteIcon | undefined = icons.find(
    (icon: QuickSiteIcon): boolean => icon.host === host);
  return match !== undefined ? match.path : '';
}

export function withQuickSiteIcon(icons: QuickSiteIcon[], host: string, path: string): QuickSiteIcon[] {
  const next: QuickSiteIcon[] = icons
    .filter((icon: QuickSiteIcon): boolean => icon.host !== host)
    .map((icon: QuickSiteIcon): QuickSiteIcon => {
      return { host: icon.host, path: icon.path };
    });
  if (path.length > 0) {
    next.push({ host: host, path: path });
  }
  return next;
}

export function presetSiteIconResource(host: string): Resource | undefined {
  const clean: string = host.toLowerCase().replace(/^(https?:\/\/)?(www\.|m\.)?/, '').replace(/\/.*$/, '');
  if (clean.includes('zhihu.com')) {
    return $r('app.media.site_zhihu');
  }
  if (clean.includes('bilibili.com')) {
    return $r('app.media.site_bilibili');
  }
  if (clean.includes('sspai.com')) {
    return $r('app.media.site_sspai');
  }
  if (clean.includes('weibo.com') || clean.includes('weibo.cn')) {
    return $r('app.media.site_weibo');
  }
  if (clean.includes('douban.com')) {
    return $r('app.media.site_douban');
  }
  if (clean.includes('36kr.com')) {
    return $r('app.media.site_36kr');
  }
  return undefined;
}
