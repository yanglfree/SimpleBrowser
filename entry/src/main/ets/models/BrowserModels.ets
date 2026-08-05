export interface BrowserTab {
  id: string;
  url: string;
  title: string;
  isPrivate: boolean;
  isLoading: boolean;
  progress: number;
  blockedCount: number;
}

export interface BrowserTabUpdate {
  url?: string;
  title?: string;
  isLoading?: boolean;
  progress?: number;
  blockedCount?: number;
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
}

export interface BrowserSettings {
  isAdsBlockingEnabled: boolean;
  isDarkModeEnabled: boolean;
  isDesktopModeEnabled: boolean;
}

export function defaultBrowserSettings(): BrowserSettings {
  return {
    isAdsBlockingEnabled: true,
    isDarkModeEnabled: false,
    isDesktopModeEnabled: false
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
    blockedCount: tab.blockedCount
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
    visitedAt: entry.visitedAt
  };
}

export function cloneSettings(settings: BrowserSettings): BrowserSettings {
  return {
    isAdsBlockingEnabled: settings.isAdsBlockingEnabled,
    isDarkModeEnabled: settings.isDarkModeEnabled,
    isDesktopModeEnabled: settings.isDesktopModeEnabled
  };
}
