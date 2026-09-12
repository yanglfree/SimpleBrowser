/**
 * Contract for tab, session, and settings fields.
 * Harmony owns the runtime types in `entry/src/main/ets/models/BrowserModels.ets`.
 * Other clients must persist the same JSON keys. Adding a settings field still
 * requires the Harmony four-file set (interface, default, clone/normalize, decoder)
 * plus this spec.
 */

export type AppearanceMode = 0 | 1 | 2;
export type WebDarkModePreference = 0 | 1 | 2;
export type SitePermissionDecision = 0 | 1 | 2;
export type RuleStrength = 0 | 1;
export type SearchEngine = 0 | 1 | 2 | 3;
export type ReaderPaper = 0 | 1 | 2;
export type StartPageBackgroundSource = 0 | 1 | 2;
export type SuggestionKind = 0 | 1 | 2;
export type LoadErrorKind = 0 | 1 | 2 | 3 | 4 | 5;
export type SecurityState = 0 | 1 | 2 | 3;
export type UserAgentPreference = 0 | 1 | 2;
export type TabExpiry = 0 | 1 | 3 | 7;

export interface BlockStats {
  ads: number;
  trackers: number;
  malicious: number;
  popups: number;
  cookieBanners: number;
}

export interface CertificateSummary {
  subject: string;
  issuer: string;
  validFrom: string;
  validTo: string;
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

export interface BrowserSession {
  tabs: BrowserTab[];
  activeTabId: string;
}

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
  startPagePresetPortraitId: string;
  startPagePresetLandscapeId: string;
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
  privacyConsentAccepted: boolean;
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

export const HOME_URL = 'browser://home';
export const MAX_TAB_COUNT = 100;
export const LIVE_WEBVIEW_LIMIT_DEFAULT = 4;
