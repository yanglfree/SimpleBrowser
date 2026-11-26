/**
 * Canonical cross-platform account, region-auth, and scoped cloud-sync contracts.
 * All timestamps across the wire protocol are UTC milliseconds (Int64).
 */

export type AuthProviderId = 'email_otp' | 'email_password' | 'apple' | 'huawei' | 'google';

export type SyncPlatform = 'harmony' | 'ios' | 'macos' | 'android';

export type EncryptionMode = 'none' | 'e2ee-v1';

export type SyncScopeName =
  | 'bookmarks'
  | 'settings'
  | 'site_controls'
  | 'device_tabs'
  | 'articles_meta';

export interface AuthProviderDescriptor {
  id: AuthProviderId;
  enabled: boolean;
  configured: boolean;
  reason?: string;
}

export interface SyncBookmarkFolder {
  id: string;
  name: string;
  iconName: string;
  createdAt: number;
  updatedAt: number;
  sortOrder: number;
  isPinnedToStartPage: boolean;
}

export interface SyncBookmarkItem {
  id: string;
  title: string;
  shortTitle?: string;
  url: string;
  folderId: string | null;
  createdAt: number;
  updatedAt: number;
  isRead: boolean;
  tags: string[];
  isPinnedToStartPage: boolean;
  iconName: string;
  iconLetter: string;
  colorHex: string;
  sortOrder: number;
}

export interface SyncBookmarkTombstone {
  id: string;
  url?: string;
  isFolder: boolean;
  deletedAt: number;
}

export interface SyncBookmarksScopePayload {
  version: number;
  folders: SyncBookmarkFolder[];
  items: SyncBookmarkItem[];
  tombstones: SyncBookmarkTombstone[];
  updatedAt: number;
}

/**
 * Cross-device user-intent preference allowlist.
 * Device-specific parameters (liveWebViewLimit, liveWebViewBudget,
 * autoHideToolbarEnabled, onboardingCompleted, etc.) are intentionally excluded.
 */
export interface SyncCrossPlatformSettings {
  blockAds?: boolean;
  blockTrackers?: boolean;
  ruleStrength?: 0 | 1;
  searchEngine?: 0 | 1 | 2 | 3;
  customSearchTemplate?: string;
  searchSuggestionsEnabled?: boolean;
  appearance?: 0 | 1 | 2;
  webDarkMode?: 0 | 1 | 2;
  webDarkModeExcludedHosts?: string[];
  minimumFontSize?: number;
  readerFontSize?: number;
  readerLineHeight?: number;
  readerPaper?: 0 | 1 | 2;
  updatedAt: number;
}

export interface SyncSiteControlRecord {
  host: string;
  networkBlocking: 0 | 1 | 2;
  trackerBlocking: 0 | 1 | 2;
  cosmeticCleanup: 0 | 1 | 2;
  autoReader: 0 | 1 | 2;
  darkMode: 0 | 1 | 2;
  desktopUserAgent: 0 | 1 | 2;
  updatedAt: number;
}

export interface SyncHostTombstone {
  host: string;
  deletedAt: number;
}

export interface SyncSiteControlsScopePayload {
  controls: SyncSiteControlRecord[];
  tombstones: SyncHostTombstone[];
  updatedAt: number;
}

export interface SyncDeviceTabEntry {
  id: string;
  title: string;
  url: string;
  lastVisitedAt: number;
}

export interface SyncDeviceTabSnapshot {
  deviceId: string;
  deviceName: string;
  platform: SyncPlatform;
  updatedAt: number;
  tabs: SyncDeviceTabEntry[];
}

export interface SyncArticleHighlightRecord {
  id: string;
  quote: string;
  prefixContext: string;
  suffixContext: string;
  color: string;
  createdAt: number;
  updatedAt: number;
}

export interface SyncArticleNoteRecord {
  id: string;
  highlightId?: string;
  content: string;
  createdAt: number;
  updatedAt: number;
}

export interface SyncArticleMetaRecord {
  id: string;
  sourceUrl: string;
  canonicalUrl: string;
  title: string;
  author: string;
  excerpt: string;
  createdAt: number;
  updatedAt: number;
  readingPosition: number;
  tags: string[];
  topics: string[];
  isArchived: boolean;
  quality: string;
  bundleSha256?: string;
  highlights: SyncArticleHighlightRecord[];
  notes: SyncArticleNoteRecord[];
}

export interface SyncArticleTombstone {
  id: string;
  canonicalUrl?: string;
  deletedAt: number;
}

export interface SyncArticlesMetaScopePayload {
  articles: SyncArticleMetaRecord[];
  tombstones: SyncArticleTombstone[];
  updatedAt: number;
}
