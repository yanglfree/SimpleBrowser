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
  SavedItem,
  BrowserSession,
  BrowserSettings,
  BrowserTab,
  BrowserTabUpdate,
  HistoryEntry,
  LoadErrorKind,
  SecurityState,
  SiteZoomRatio,
  SiteBlockStats,
  QuickSite,
  Suggestion,
  SuggestionKind,
  TabExpiry,
  addBlockStats,
  cloneBlockStats,
  cloneSettings,
  cloneTab,
  defaultBrowserSettings,
  emptyBlockStats,
  totalBlocked
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
  savedItems: SavedItem[] = [];
  history: HistoryEntry[] = [];
  expiredTabs: BrowserTab[] = [];
  settings: BrowserSettings = defaultBrowserSettings();
  activeTabId: string = '';
  private tabSequence: number = 0;

  async initialize(context: common.UIAbilityContext): Promise<void> {
    await this.repository.initialize(context);
    this.savedItems = this.repository.getSavedItems();
    this.history = this.repository.getHistory();
    this.settings = this.repository.getSettings();
    const session: BrowserSession | undefined = this.repository.getSession();
    if (session !== undefined && session.tabs.length > 0) {
      const expiryDays: TabExpiry = this.settings.tabExpiryDays;
      const cutoff: number = expiryDays === TabExpiry.Never
        ? 0
        : Date.now() - Number(expiryDays) * 24 * 60 * 60 * 1000;
      const sessionTabs: BrowserTab[] = session.tabs.map((tab: BrowserTab) => cloneTab(tab));
      this.expiredTabs = cutoff === 0
        ? []
        : sessionTabs.filter((tab: BrowserTab): boolean => tab.lastVisitedAt < cutoff);
      if (this.expiredTabs.length > 0) {
        await this.repository.archiveTabs(this.expiredTabs);
      }
      this.tabs = sessionTabs.filter((tab: BrowserTab): boolean =>
        cutoff === 0 || tab.lastVisitedAt >= cutoff);
      if (this.tabs.length === 0) {
        this.tabs = [this.createTab(HOME_URL, false)];
      }
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
    DownloadService.setConcurrencyLimit(this.settings.downloadConcurrency);
    this.persistSession();
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
      readerScrollY: 0,
      scrollSavedAt: 0,
      readerScrollSavedAt: 0,
      formDraft: '',
      loadError: LoadErrorKind.None,
      securityState: SecurityState.Unknown
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

  addBackgroundTab(url: string, isPrivate: boolean): BrowserTab | undefined {
    if (this.tabs.length >= MAX_TAB_COUNT) {
      Logger.warn(TAG, 'Tab limit reached');
      return undefined;
    }
    const previousActiveTabId: string = this.activeTabId;
    const tab: BrowserTab = this.createTab(url, isPrivate);
    this.tabs = this.tabs.concat([tab]);
    this.activeTabId = previousActiveTabId;
    this.persistSession();
    return tab;
  }

  async saveUrlForLater(url: string, title: string): Promise<void> {
    if (url.length === 0 || isHomeUrl(url)) {
      return;
    }
    const existing: SavedItem | undefined = this.savedItems.find((item: SavedItem) => item.url === url);
    const now: number = Date.now();
    if (existing === undefined) {
      await this.repository.addSavedItem({
        id: `saved-${now}`,
        title: title.length > 0 ? title : displayHost(url),
        url: url,
        createdAt: now,
        updatedAt: now,
        isRead: false,
        tags: []
      });
    } else {
      await this.repository.updateSavedItem({
        id: existing.id,
        title: existing.title,
        url: existing.url,
        createdAt: existing.createdAt,
        updatedAt: now,
        isRead: false,
        tags: existing.tags.slice(0)
      });
    }
    this.savedItems = this.repository.getSavedItems();
  }

  async importSavedItems(items: SavedItem[]): Promise<number> {
    const imported: number = await this.repository.mergeSavedItems(items);
    this.savedItems = this.repository.getSavedItems();
    return imported;
  }

  isTabSoftLimitReached(): boolean {
    return this.tabs.length >= this.settings.tabSoftLimit;
  }

  siteZoomPercent(url: string): number {
    if (url.length === 0 || isHomeUrl(url)) {
      return 100;
    }
    const host: string = rawHost(url);
    const entry: SiteZoomRatio | undefined = this.settings.siteZoomRatios.find(
      (item: SiteZoomRatio): boolean => item.host === host);
    return entry === undefined ? 100 : BrowserViewModel.clampZoomPercent(entry.percent);
  }

  async rememberSiteZoom(url: string, scale: number): Promise<void> {
    if (url.length === 0 || isHomeUrl(url) || Number.isNaN(scale) || scale <= 0) {
      return;
    }
    const host: string = rawHost(url);
    if (host.length === 0) {
      return;
    }
    const percent: number = BrowserViewModel.clampZoomPercent(Math.round(scale * 100));
    const next: BrowserSettings = cloneSettings(this.settings);
    const existing: SiteZoomRatio | undefined = next.siteZoomRatios.find(
      (item: SiteZoomRatio): boolean => item.host === host);
    if (existing === undefined) {
      next.siteZoomRatios = next.siteZoomRatios.concat([{ host: host, percent: percent }]);
    } else if (existing.percent === percent) {
      return;
    } else {
      next.siteZoomRatios = next.siteZoomRatios.map((item: SiteZoomRatio): SiteZoomRatio =>
        item.host === host ? { host: host, percent: percent } : item);
    }
    await this.updateSettings(next);
  }

  /** Returns the oldest disposable tabs needed to get back below the soft limit. */
  softLimitCleanupCandidates(): string[] {
    const targetCount: number = Math.max(1, Math.floor(this.settings.tabSoftLimit) - 1);
    const removeCount: number = Math.max(0, this.tabs.length - targetCount);
    if (removeCount === 0) {
      return [];
    }

    const stale: BrowserTab[] = this.tabs
      .filter((tab: BrowserTab): boolean => tab.id !== this.activeTabId &&
        (isHomeUrl(tab.url) || tab.isLoading))
      .sort((left: BrowserTab, right: BrowserTab): number => left.lastVisitedAt - right.lastVisitedAt);
    const remaining: BrowserTab[] = this.tabs
      .filter((tab: BrowserTab): boolean => tab.id !== this.activeTabId &&
        !stale.some((candidate: BrowserTab): boolean => candidate.id === tab.id))
      .sort((left: BrowserTab, right: BrowserTab): number => left.lastVisitedAt - right.lastVisitedAt);
    return stale.concat(remaining)
      .slice(0, removeCount)
      .map((tab: BrowserTab): string => tab.id);
  }

  get expiredTabCount(): number {
    return this.expiredTabs.length;
  }

  async archiveExpiredTabs(): Promise<void> {
    this.expiredTabs = [];
  }

  async restoreExpiredTabs(): Promise<void> {
    if (this.expiredTabs.length === 0) {
      return;
    }
    const restored: BrowserTab[] = this.expiredTabs.map((tab: BrowserTab) => cloneTab(tab));
    await this.repository.removeArchivedTabs(restored.map((tab: BrowserTab) => tab.id));
    this.tabs = this.tabs.concat(restored);
    this.expiredTabs = [];
    this.persistSession();
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
    const next: number = index + offset;
    if (next < 0 || next >= this.tabs.length) {
      return this.activeTabId;
    }
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
      if (update.readerScrollY !== undefined) {
        updated.readerScrollY = update.readerScrollY;
      }
      if (update.scrollSavedAt !== undefined) {
        updated.scrollSavedAt = update.scrollSavedAt;
      }
      if (update.readerScrollSavedAt !== undefined) {
        updated.readerScrollSavedAt = update.readerScrollSavedAt;
      }
      if (update.formDraft !== undefined) {
        updated.formDraft = update.formDraft;
      }
      if (update.loadError !== undefined) {
        updated.loadError = update.loadError;
      }
      if (update.securityState !== undefined) {
        updated.securityState = update.securityState;
      }
      if (update.url !== undefined || update.title !== undefined || update.isDesktop !== undefined ||
        update.isReader !== undefined || update.scrollY !== undefined || update.readerScrollY !== undefined ||
        update.lastVisitedAt !== undefined) {
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

  getCumulativeBlocked(): number {
    return this.repository.getSiteStatsSnapshot()
      .reduce((sum: number, item: SiteBlockStats): number => sum + totalBlocked(item.stats), 0);
  }

  getSiteBlocked(url: string): BlockStats {
    return this.repository.getSiteStats(rawHost(url));
  }

  isHostAllowed(url: string): boolean {
    return this.repository.isHostAllowed(rawHost(url));
  }

  getAllowedHosts(): string[] {
    return this.repository.getAllowedHosts();
  }

  async setQuickSiteHidden(url: string, hidden: boolean): Promise<void> {
    await this.repository.setQuickHostHidden(rawHost(url), hidden);
  }

  async setHostAllowed(url: string, allowed: boolean): Promise<void> {
    await this.repository.setHostAllowed(rawHost(url), allowed);
    this.adsBlockService.applyAllowedHosts(this.repository.getAllowedHosts());
  }

  async removeAllowedHost(host: string): Promise<void> {
    await this.repository.setHostAllowed(host, false);
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
    await this.markSavedItemRead(tab.url);
  }

  async toggleSaved(tab: BrowserTab): Promise<boolean> {
    const existing: SavedItem | undefined = this.savedItems.find((item: SavedItem) => item.url === tab.url);
    if (existing !== undefined) {
      await this.repository.removeSavedItem(existing.id);
    } else {
      const now: number = Date.now();
      await this.repository.addSavedItem({
        id: `saved-${now}`,
        title: tab.title.length > 0 ? tab.title : displayHost(tab.url),
        url: tab.url,
        createdAt: now,
        updatedAt: now,
        isRead: true,
        tags: []
      });
    }
    this.savedItems = this.repository.getSavedItems();
    return existing === undefined;
  }

  async saveForLater(tab: BrowserTab): Promise<void> {
    await this.saveUrlForLater(tab.url, tab.title);
  }

  isSaved(url: string): boolean {
    return !isHomeUrl(url) && this.savedItems.some((item: SavedItem) => item.url === url);
  }

  isSavedForLater(url: string): boolean {
    return !isHomeUrl(url) && this.savedItems.some((item: SavedItem) =>
      item.url === url && !item.isRead);
  }

  async setSavedItemTags(url: string, tags: string[]): Promise<void> {
    const existing: SavedItem | undefined = this.savedItems.find((item: SavedItem) => item.url === url);
    if (existing === undefined) {
      return;
    }
    const updated: SavedItem = {
      id: existing.id,
      title: existing.title,
      url: existing.url,
      createdAt: existing.createdAt,
      updatedAt: Date.now(),
      isRead: existing.isRead,
      tags: tags.filter((tag: string) => tag.trim().length > 0).map((tag: string) => tag.trim())
    };
    await this.repository.updateSavedItem(updated);
    this.savedItems = this.repository.getSavedItems();
  }

  private async markSavedItemRead(url: string): Promise<void> {
    const existing: SavedItem | undefined = this.savedItems.find((item: SavedItem) => item.url === url);
    if (existing === undefined || existing.isRead) {
      return;
    }
    const updated: SavedItem = {
      id: existing.id,
      title: existing.title,
      url: existing.url,
      createdAt: existing.createdAt,
      updatedAt: Date.now(),
      isRead: true,
      tags: existing.tags.slice(0)
    };
    await this.repository.updateSavedItem(updated);
    this.savedItems = this.repository.getSavedItems();
  }

  private static clampZoomPercent(percent: number): number {
    return Math.min(300, Math.max(50, percent));
  }

  async updateSettings(settings: BrowserSettings): Promise<void> {
    this.settings = cloneSettings(settings);
    await this.repository.saveSettings(this.settings);
    DownloadService.setConcurrencyLimit(this.settings.downloadConcurrency);
    await this.repository.applyHistoryRetention(this.settings.historyRetentionDays);
    this.history = this.repository.getHistory();
    Logger.info(TAG, 'Browser settings updated');
  }

  async clearHistory(before: number = 0): Promise<void> {
    await this.repository.clearHistory(before);
    this.history = this.repository.getHistory();
  }

  async removeHistoryEntry(id: string): Promise<void> {
    await this.repository.removeHistoryEntry(id);
    this.history = this.repository.getHistory();
  }

  async removeHistoryForHost(host: string): Promise<void> {
    await this.repository.removeHistoryForHost(host);
    this.history = this.repository.getHistory();
  }

  async clearAllowedHosts(): Promise<void> {
    await this.repository.clearAllowedHosts();
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
    const hiddenHosts: string[] = this.repository.getHiddenQuickHosts();
    const visibleSites: QuickSite[] = sites.filter((site: QuickSite): boolean =>
      !hiddenHosts.includes(rawHost(site.url)));

    for (const fallback of DEFAULT_QUICK_SITES) {
      if (visibleSites.length >= QUICK_SITE_COUNT) {
        break;
      }
      const host: string = rawHost(fallback.url);
      if (!hiddenHosts.includes(host) && !visibleSites.some((site: QuickSite) => rawHost(site.url) === host)) {
        visibleSites.push(fallback);
      }
    }
    return visibleSites;
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
      for (const bookmark of this.savedItems) {
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

    for (const entry of this.history) {
      if (results.length >= MAX_SUGGESTION_COUNT) {
        break;
      }
      if (matches(entry.title, entry.url)) {
        results.push(BrowserViewModel.historySuggestion(entry));
      }
    }
    for (const bookmark of this.savedItems) {
      if (results.length >= MAX_SUGGESTION_COUNT) {
        break;
      }
      if (matches(bookmark.title, bookmark.url) && !results.some((item: Suggestion) => item.url === bookmark.url)) {
        results.push(BrowserViewModel.bookmarkSuggestion(bookmark));
      }
    }
    if (this.settings.searchSuggestionsEnabled && results.length < MAX_SUGGESTION_COUNT && !looksLikeUrl(trimmed)) {
      results.push({
        id: `search-${trimmed}`,
        kind: SuggestionKind.Search,
        title: trimmed,
        subtitle: '',
        url: searchUrl(trimmed, this.settings.searchEngine, this.settings.customSearchTemplate)
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

  private static bookmarkSuggestion(bookmark: SavedItem): Suggestion {
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
