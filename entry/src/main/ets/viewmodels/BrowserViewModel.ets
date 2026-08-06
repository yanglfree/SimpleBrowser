import { common } from '@kit.AbilityKit';
import {
  DEFAULT_QUICK_SITES,
  HOME_URL,
  MAX_SUGGESTION_COUNT,
  MAX_TAB_COUNT,
  QUICK_SITE_COUNT
} from '../constants/AppConstants';
import {
  BlockStats,
  Bookmark,
  BrowserSession,
  BrowserSettings,
  BrowserTab,
  BrowserTabUpdate,
  HistoryEntry,
  LoadErrorKind,
  QuickSite,
  Suggestion,
  SuggestionKind,
  addBlockStats,
  cloneBlockStats,
  cloneSettings,
  cloneTab,
  defaultBrowserSettings,
  emptyBlockStats
} from '../models/BrowserModels';
import { BrowserRepository } from '../repositories/BrowserRepository';
import { AdsBlockService } from '../services/AdsBlockService';
import { DownloadService } from '../services/DownloadService';
import { displayHost, isHomeUrl, looksLikeUrl, rawHost, searchUrl, siteBadge } from '../utils/UrlUtils';
import { Logger } from '../utils/Logger';

const TAG: string = 'BrowserViewModel';

interface HostTally {
  host: string;
  title: string;
  url: string;
  visits: number;
}

export class BrowserViewModel {
  readonly repository: BrowserRepository = new BrowserRepository();
  readonly adsBlockService: AdsBlockService = new AdsBlockService();
  tabs: BrowserTab[] = [];
  bookmarks: Bookmark[] = [];
  history: HistoryEntry[] = [];
  settings: BrowserSettings = defaultBrowserSettings();
  activeTabId: string = '';
  private tabSequence: number = 0;

  async initialize(context: common.UIAbilityContext): Promise<void> {
    await this.repository.initialize(context);
    this.bookmarks = this.repository.getBookmarks();
    this.history = this.repository.getHistory();
    this.settings = this.repository.getSettings();
    const session: BrowserSession | undefined = this.repository.getSession();
    if (session !== undefined && session.tabs.length > 0) {
      this.tabs = session.tabs.map((tab: BrowserTab) => cloneTab(tab));
      this.activeTabId = this.tabs.some((tab: BrowserTab) => tab.id === session.activeTabId)
        ? session.activeTabId
        : this.tabs[0].id;
      this.tabSequence = this.tabs.reduce((max: number, tab: BrowserTab): number => {
        const value: number = Number(tab.id.replace('tab-', ''));
        return Number.isNaN(value) ? max : Math.max(max, value);
      }, 0);
    } else {
      this.tabs = [this.createTab(HOME_URL, false)];
      this.activeTabId = this.tabs[0].id;
    }
    await this.adsBlockService.initialize(context);
    this.adsBlockService.applyAllowedHosts(this.repository.getAllowedHosts());
    DownloadService.configure();
  }

  persistSession(): void {
    const session: BrowserSession = {
      tabs: this.tabs,
      activeTabId: this.activeTabId
    };
    this.repository.saveSession(session).catch((error: Error): void => {
      Logger.warn(TAG, `Failed to persist browser session: ${String(error)}`);
    });
  }

  getActiveTab(): BrowserTab | undefined {
    return this.tabs.find((tab: BrowserTab) => tab.id === this.activeTabId);
  }

  getTab(id: string): BrowserTab | undefined {
    return this.tabs.find((tab: BrowserTab) => tab.id === id);
  }

  createTab(url: string, isPrivate: boolean): BrowserTab {
    this.tabSequence += 1;
    return {
      id: `tab-${this.tabSequence}`,
      url: url,
      title: '',
      isPrivate: isPrivate,
      isLoading: !isHomeUrl(url),
      progress: 0,
      isDesktop: false,
      isReader: false,
      canGoBack: false,
      canGoForward: false,
      blocked: emptyBlockStats(),
      faviconUrl: '',
      lastVisitedAt: Date.now(),
      scrollY: 0,
      loadError: LoadErrorKind.None
    };
  }

  addTab(url: string, isPrivate: boolean): BrowserTab | undefined {
    if (this.tabs.length >= MAX_TAB_COUNT) {
      Logger.warn(TAG, 'Tab limit reached');
      return undefined;
    }
    const tab: BrowserTab = this.createTab(url, isPrivate);
    this.tabs = this.tabs.concat([tab]);
    this.activeTabId = tab.id;
    this.persistSession();
    return tab;
  }

  /** Closing the last tab leaves a fresh start-page tab rather than an empty app. */
  closeTab(id: string): void {
    const index: number = this.tabs.findIndex((tab: BrowserTab) => tab.id === id);
    if (index < 0) {
      return;
    }
    this.tabs = this.tabs.filter((tab: BrowserTab) => tab.id !== id);
    if (this.tabs.length === 0) {
      const replacement: BrowserTab = this.createTab(HOME_URL, false);
      this.tabs = [replacement];
      this.activeTabId = replacement.id;
      return;
    }
    if (id === this.activeTabId) {
      this.activeTabId = this.tabs[Math.min(index, this.tabs.length - 1)].id;
    }
    this.persistSession();
  }

  closeAllTabs(): void {
    const replacement: BrowserTab = this.createTab(HOME_URL, false);
    this.tabs = [replacement];
    this.activeTabId = replacement.id;
    this.persistSession();
  }

  selectTab(id: string): void {
    if (this.tabs.some((tab: BrowserTab) => tab.id === id)) {
      this.activeTabId = id;
      this.persistSession();
    }
  }

  /** Capsule left/right swipe walks the tab strip. */
  neighbourTabId(offset: number): string {
    const index: number = this.tabs.findIndex((tab: BrowserTab) => tab.id === this.activeTabId);
    if (index < 0 || this.tabs.length < 2) {
      return this.activeTabId;
    }
    const next: number = (index + offset + this.tabs.length) % this.tabs.length;
    return this.tabs[next].id;
  }

  updateTab(id: string, update: BrowserTabUpdate): void {
    this.tabs = this.tabs.map((tab: BrowserTab) => {
      if (tab.id !== id) {
        return tab;
      }
      const updated: BrowserTab = cloneTab(tab);
      if (update.url !== undefined) {
        updated.url = update.url;
      }
      if (update.title !== undefined) {
        updated.title = update.title;
      }
      if (update.isLoading !== undefined) {
        updated.isLoading = update.isLoading;
      }
      if (update.progress !== undefined) {
        updated.progress = update.progress;
      }
      if (update.isDesktop !== undefined) {
        updated.isDesktop = update.isDesktop;
      }
      if (update.isReader !== undefined) {
        updated.isReader = update.isReader;
      }
      if (update.canGoBack !== undefined) {
        updated.canGoBack = update.canGoBack;
      }
      if (update.canGoForward !== undefined) {
        updated.canGoForward = update.canGoForward;
      }
      if (update.blocked !== undefined) {
        updated.blocked = cloneBlockStats(update.blocked);
      }
      if (update.faviconUrl !== undefined) {
        updated.faviconUrl = update.faviconUrl;
      }
      if (update.lastVisitedAt !== undefined) {
        updated.lastVisitedAt = update.lastVisitedAt;
      }
      if (update.scrollY !== undefined) {
        updated.scrollY = update.scrollY;
      }
      if (update.loadError !== undefined) {
        updated.loadError = update.loadError;
      }
      if (update.url !== undefined || update.title !== undefined || update.isDesktop !== undefined ||
        update.isReader !== undefined || update.scrollY !== undefined || update.lastVisitedAt !== undefined) {
        updated.lastVisitedAt = update.lastVisitedAt ?? updated.lastVisitedAt;
      }
      return updated;
    });
  }

  /** Folds a blocking delta into the tab counter and the persisted totals. */
  async recordBlocked(id: string, delta: BlockStats): Promise<void> {
    const tab: BrowserTab | undefined = this.getTab(id);
    if (tab === undefined) {
      return;
    }
    this.updateTab(id, { blocked: addBlockStats(tab.blocked, delta) });
    if (!tab.isPrivate) {
      await this.repository.recordBlocked(rawHost(tab.url), delta);
    }
  }

  getWeeklyBlocked(): number {
    return this.repository.getWeeklyBlocked();
  }

  getSiteBlocked(url: string): BlockStats {
    return this.repository.getSiteStats(rawHost(url));
  }

  isHostAllowed(url: string): boolean {
    return this.repository.isHostAllowed(rawHost(url));
  }

  async setHostAllowed(url: string, allowed: boolean): Promise<void> {
    await this.repository.setHostAllowed(rawHost(url), allowed);
    this.adsBlockService.applyAllowedHosts(this.repository.getAllowedHosts());
  }

  async recordPageVisit(tab: BrowserTab): Promise<void> {
    if (tab.isPrivate || isHomeUrl(tab.url)) {
      return;
    }
    await this.repository.recordHistory({
      id: `history-${Date.now()}`,
      title: tab.title.length > 0 ? tab.title : displayHost(tab.url),
      url: tab.url,
      visitedAt: Date.now(),
      visitCount: 0
    });
    this.history = this.repository.getHistory();
  }

  async toggleBookmark(tab: BrowserTab): Promise<boolean> {
    const existing: Bookmark | undefined = this.bookmarks.find((item: Bookmark) => item.url === tab.url);
    if (existing !== undefined) {
      await this.repository.removeBookmark(existing.id);
    } else {
      await this.repository.addBookmark({
        id: `bookmark-${Date.now()}`,
        title: tab.title.length > 0 ? tab.title : displayHost(tab.url),
        url: tab.url,
        createdAt: Date.now()
      });
    }
    this.bookmarks = this.repository.getBookmarks();
    return existing === undefined;
  }

  isBookmarked(url: string): boolean {
    return !isHomeUrl(url) && this.bookmarks.some((item: Bookmark) => item.url === url);
  }

  async updateSettings(settings: BrowserSettings): Promise<void> {
    this.settings = cloneSettings(settings);
    await this.repository.saveSettings(this.settings);
    Logger.info(TAG, 'Browser settings updated');
  }

  async clearBrowsingData(): Promise<void> {
    await this.repository.clearBrowsingData();
    this.history = [];
  }

  /**
   * Start-page tiles: the six most-visited hosts, topped up with the shipped
   * defaults so a fresh install still has somewhere to go.
   */
  getQuickSites(): QuickSite[] {
    const tallies: HostTally[] = [];
    for (const entry of this.history) {
      const host: string = rawHost(entry.url);
      if (host.length === 0) {
        continue;
      }
      const existing: HostTally | undefined = tallies.find((item: HostTally) => item.host === host);
      const visits: number = Math.max(1, entry.visitCount);
      if (existing === undefined) {
        tallies.push({ host: host, title: entry.title, url: entry.url, visits: visits });
      } else {
        existing.visits += visits;
      }
    }
    tallies.sort((left: HostTally, right: HostTally) => right.visits - left.visits);

    const sites: QuickSite[] = tallies
      .slice(0, QUICK_SITE_COUNT)
      .map((item: HostTally): QuickSite => ({
        title: displayHost(item.url),
        url: `https://${item.host}`,
        badge: siteBadge(item.title, item.url),
        colorIndex: BrowserViewModel.colorIndexFor(item.host)
      }));

    for (const fallback of DEFAULT_QUICK_SITES) {
      if (sites.length >= QUICK_SITE_COUNT) {
        break;
      }
      const host: string = rawHost(fallback.url);
      if (!sites.some((site: QuickSite) => rawHost(site.url) === host)) {
        sites.push(fallback);
      }
    }
    return sites;
  }

  /**
   * Address-bar suggestions, most relevant first. The sheet renders them bottom
   * -up so the best match sits against the input, closest to the thumb.
   */
  getSuggestions(query: string): Suggestion[] {
    const trimmed: string = query.trim();
    const results: Suggestion[] = [];

    if (trimmed.length === 0) {
      for (const entry of this.history) {
        if (results.length >= MAX_SUGGESTION_COUNT) {
          break;
        }
        results.push(BrowserViewModel.historySuggestion(entry));
      }
      for (const bookmark of this.bookmarks) {
        if (results.length >= MAX_SUGGESTION_COUNT) {
          break;
        }
        if (!results.some((item: Suggestion) => item.url === bookmark.url)) {
          results.push(BrowserViewModel.bookmarkSuggestion(bookmark));
        }
      }
      return results;
    }

    const needle: string = trimmed.toLowerCase();
    const matches = (title: string, url: string): boolean =>
      title.toLowerCase().includes(needle) || url.toLowerCase().includes(needle);

    for (const bookmark of this.bookmarks) {
      if (results.length >= MAX_SUGGESTION_COUNT) {
        break;
      }
      if (matches(bookmark.title, bookmark.url)) {
        results.push(BrowserViewModel.bookmarkSuggestion(bookmark));
      }
    }
    for (const entry of this.history) {
      if (results.length >= MAX_SUGGESTION_COUNT) {
        break;
      }
      if (matches(entry.title, entry.url) && !results.some((item: Suggestion) => item.url === entry.url)) {
        results.push(BrowserViewModel.historySuggestion(entry));
      }
    }
    if (results.length < MAX_SUGGESTION_COUNT && !looksLikeUrl(trimmed)) {
      results.push({
        id: `search-${trimmed}`,
        kind: SuggestionKind.Search,
        title: trimmed,
        subtitle: '',
        url: searchUrl(trimmed, this.settings.searchEngine)
      });
    }
    return results;
  }

  private static historySuggestion(entry: HistoryEntry): Suggestion {
    return {
      id: `history-${entry.id}`,
      kind: SuggestionKind.History,
      title: entry.title.length > 0 ? entry.title : displayHost(entry.url),
      subtitle: displayHost(entry.url),
      url: entry.url
    };
  }

  private static bookmarkSuggestion(bookmark: Bookmark): Suggestion {
    return {
      id: `bookmark-${bookmark.id}`,
      kind: SuggestionKind.Bookmark,
      title: bookmark.title.length > 0 ? bookmark.title : displayHost(bookmark.url),
      subtitle: displayHost(bookmark.url),
      url: bookmark.url
    };
  }

  /** Stable per-host tile colour so a site keeps its swatch between launches. */
  private static colorIndexFor(host: string): number {
    let hash: number = 0;
    for (let index = 0; index < host.length; index++) {
      hash = (hash * 31 + host.charCodeAt(index)) % 100000;
    }
    return hash % 6;
  }
}
