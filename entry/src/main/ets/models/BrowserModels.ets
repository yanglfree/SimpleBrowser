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

export enum SuggestionKind {
  History = 0,
  Bookmark = 1,
  Search = 2
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
  isReader: boolean;
  canGoBack: boolean;
  canGoForward: boolean;
  blocked: BlockStats;
  faviconUrl: string;
  lastVisitedAt: number;
  scrollY: number;
  readerScrollY: number;
  loadError: LoadErrorKind;
  securityState: SecurityState;
}

export interface BrowserTabUpdate {
  url?: string;
  title?: string;
  isLoading?: boolean;
  progress?: number;
  isDesktop?: boolean;
  isReader?: boolean;
  canGoBack?: boolean;
  canGoForward?: boolean;
  blocked?: BlockStats;
  faviconUrl?: string;
  lastVisitedAt?: number;
  scrollY?: number;
  readerScrollY?: number;
  loadError?: LoadErrorKind;
  securityState?: SecurityState;
}

export interface BrowserSession {
  tabs: BrowserTab[];
  activeTabId: string;
}

export interface Bookmark {
  id: string;
  title: string;
  url: string;
  createdAt: number;
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
  tabExpiryDays: TabExpiry;
  tabSoftLimit: number;
  appearance: AppearanceMode;
  clearCookiesOnTabClose: boolean;
  readerFontSize: number;
  readerLineHeight: number;
  readerPaper: ReaderPaper;
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
  return { ads: 0, trackers: 0, popups: 0, cookieBanners: 0 };
}

export function cloneBlockStats(stats: BlockStats): BlockStats {
  return {
    ads: stats.ads,
    trackers: stats.trackers,
    popups: stats.popups,
    cookieBanners: stats.cookieBanners
  };
}

export function addBlockStats(base: BlockStats, delta: BlockStats): BlockStats {
  return {
    ads: base.ads + delta.ads,
    trackers: base.trackers + delta.trackers,
    popups: base.popups + delta.popups,
    cookieBanners: base.cookieBanners + delta.cookieBanners
  };
}

export function totalBlocked(stats: BlockStats): number {
  return stats.ads + stats.trackers + stats.popups + stats.cookieBanners;
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
    tabExpiryDays: TabExpiry.SevenDays,
    tabSoftLimit: 12,
    appearance: AppearanceMode.System,
    clearCookiesOnTabClose: false,
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
    isReader: tab.isReader,
    canGoBack: tab.canGoBack,
    canGoForward: tab.canGoForward,
    blocked: cloneBlockStats(tab.blocked),
    faviconUrl: tab.faviconUrl,
    lastVisitedAt: tab.lastVisitedAt,
    scrollY: tab.scrollY,
    readerScrollY: tab.readerScrollY,
    loadError: tab.loadError,
    securityState: tab.securityState
  };
}

export function cloneBookmark(bookmark: Bookmark): Bookmark {
  return {
    id: bookmark.id,
    title: bookmark.title,
    url: bookmark.url,
    createdAt: bookmark.createdAt
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

export function cloneSettings(settings: BrowserSettings): BrowserSettings {
  return {
    blockAds: settings.blockAds,
    blockTrackers: settings.blockTrackers,
    ruleStrength: settings.ruleStrength,
    searchEngine: settings.searchEngine,
    customSearchTemplate: settings.customSearchTemplate,
    searchSuggestionsEnabled: settings.searchSuggestionsEnabled,
    gesturesEnabled: settings.gesturesEnabled,
    gestureActionsEnabled: settings.gestureActionsEnabled,
    gestureTabSwitchEnabled: settings.gestureTabSwitchEnabled,
    gestureBlockingEnabled: settings.gestureBlockingEnabled,
    autoHideToolbarEnabled: settings.autoHideToolbarEnabled,
    tabExpiryDays: settings.tabExpiryDays,
    tabSoftLimit: settings.tabSoftLimit,
    appearance: settings.appearance,
    clearCookiesOnTabClose: settings.clearCookiesOnTabClose,
    readerFontSize: settings.readerFontSize,
    readerLineHeight: settings.readerLineHeight,
    readerPaper: settings.readerPaper
  };
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
