import { common } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';
import {
  MAX_BOOKMARK_COUNT,
  MAX_HISTORY_COUNT,
  STORE_NAME,
  WEEKLY_WINDOW_DAYS
} from '../constants/AppConstants';
import {
  BlockStats,
  Bookmark,
  BrowserSession,
  BrowserTab,
  BrowserSettings,
  DailyBlockCount,
  HistoryEntry,
  LoadErrorKind,
  SecurityState,
  SiteBlockStats,
  addBlockStats,
  cloneBlockStats,
  cloneBookmark,
  cloneDailyCount,
  cloneHistoryEntry,
  cloneSettings,
  cloneSiteStats,
  cloneTab,
  defaultBrowserSettings,
  emptyBlockStats,
  totalBlocked
} from '../models/BrowserModels';
import { SESSION_KEY } from '../constants/AppConstants';
import { recentDayKeys, todayKey } from '../utils/Formatting';
import { Logger } from '../utils/Logger';

const TAG: string = 'BrowserRepository';
const BOOKMARKS_KEY: string = 'bookmarks';
const HISTORY_KEY: string = 'history';
const SETTINGS_KEY: string = 'settings';
const SITE_STATS_KEY: string = 'site_stats';
const DAILY_STATS_KEY: string = 'daily_stats';
const ALLOWED_HOSTS_KEY: string = 'allowed_hosts';
const HIDDEN_QUICK_HOSTS_KEY: string = 'hidden_quick_hosts';

export class BrowserRepository {
  private store: preferences.Preferences | undefined;
  private bookmarks: Bookmark[] = [];
  private history: HistoryEntry[] = [];
  private settings: BrowserSettings = defaultBrowserSettings();
  private siteStats: SiteBlockStats[] = [];
  private dailyStats: DailyBlockCount[] = [];
  private allowedHosts: string[] = [];
  private hiddenQuickHosts: string[] = [];
  private session: BrowserSession | undefined;

  async initialize(context: common.UIAbilityContext): Promise<void> {
    try {
      this.store = await preferences.getPreferences(context, STORE_NAME);
      const store: preferences.Preferences = this.store;
      this.bookmarks = this.decode<Bookmark>(await store.get(BOOKMARKS_KEY, '[]'), BOOKMARKS_KEY);
      this.history = this.decode<HistoryEntry>(await store.get(HISTORY_KEY, '[]'), HISTORY_KEY);
      this.siteStats = this.decode<SiteBlockStats>(await store.get(SITE_STATS_KEY, '[]'), SITE_STATS_KEY);
      this.dailyStats = this.decode<DailyBlockCount>(await store.get(DAILY_STATS_KEY, '[]'), DAILY_STATS_KEY);
      this.allowedHosts = this.decode<string>(await store.get(ALLOWED_HOSTS_KEY, '[]'), ALLOWED_HOSTS_KEY);
      this.hiddenQuickHosts = this.decode<string>(await store.get(HIDDEN_QUICK_HOSTS_KEY, '[]'), HIDDEN_QUICK_HOSTS_KEY);
      this.session = this.decodeSession(await store.get(SESSION_KEY, ''));
      this.settings = this.decodeSettings(await store.get(SETTINGS_KEY, ''));
      this.pruneDailyStats();
    } catch (error) {
      this.store = undefined;
      Logger.error(TAG, `Failed to initialize preferences: ${String(error)}`);
    }
  }

  getBookmarks(): Bookmark[] {
    return this.bookmarks.map((item: Bookmark) => cloneBookmark(item));
  }

  getHistory(): HistoryEntry[] {
    return this.history.map((item: HistoryEntry) => cloneHistoryEntry(item));
  }

  getSettings(): BrowserSettings {
    return cloneSettings(this.settings);
  }

  getSession(): BrowserSession | undefined {
    if (this.session === undefined) {
      return undefined;
    }
    return {
      tabs: this.session.tabs.map((tab: BrowserTab) => cloneTab(tab)),
      activeTabId: this.session.activeTabId
    };
  }

  async saveSession(session: BrowserSession): Promise<void> {
    this.session = {
      tabs: session.tabs
        .filter((tab: BrowserTab) => !tab.isPrivate)
        .map((tab: BrowserTab) => cloneTab(tab)),
      activeTabId: session.activeTabId
    };
    await this.save(SESSION_KEY, JSON.stringify(this.session));
  }

  getAllowedHosts(): string[] {
    return this.allowedHosts.slice(0);
  }

  getHiddenQuickHosts(): string[] {
    return this.hiddenQuickHosts.slice(0);
  }

  async setQuickHostHidden(host: string, hidden: boolean): Promise<void> {
    const without: string[] = this.hiddenQuickHosts.filter((item: string) => item !== host);
    this.hiddenQuickHosts = hidden ? without.concat([host]) : without;
    await this.save(HIDDEN_QUICK_HOSTS_KEY, JSON.stringify(this.hiddenQuickHosts));
  }

  async addBookmark(bookmark: Bookmark): Promise<void> {
    const filtered: Bookmark[] = this.bookmarks.filter((item: Bookmark) => item.url !== bookmark.url);
    this.bookmarks = [bookmark].concat(filtered).slice(0, MAX_BOOKMARK_COUNT);
    await this.save(BOOKMARKS_KEY, JSON.stringify(this.bookmarks));
  }

  async removeBookmark(id: string): Promise<void> {
    this.bookmarks = this.bookmarks.filter((item: Bookmark) => item.id !== id);
    await this.save(BOOKMARKS_KEY, JSON.stringify(this.bookmarks));
  }

  /** Re-visiting a URL bumps its counter instead of adding a duplicate row. */
  async recordHistory(entry: HistoryEntry): Promise<void> {
    const previous: HistoryEntry | undefined =
      this.history.find((item: HistoryEntry) => item.url === entry.url);
    const merged: HistoryEntry = cloneHistoryEntry(entry);
    merged.visitCount = (previous?.visitCount ?? 0) + 1;
    const filtered: HistoryEntry[] = this.history.filter((item: HistoryEntry) => item.url !== entry.url);
    this.history = [merged].concat(filtered).slice(0, MAX_HISTORY_COUNT);
    await this.save(HISTORY_KEY, JSON.stringify(this.history));
  }

  async clearHistory(before: number = 0): Promise<void> {
    this.history = before > 0
      ? this.history.filter((item: HistoryEntry) => item.visitedAt > before)
      : [];
    await this.save(HISTORY_KEY, JSON.stringify(this.history));
  }

  async saveSettings(settings: BrowserSettings): Promise<void> {
    this.settings = cloneSettings(settings);
    await this.save(SETTINGS_KEY, JSON.stringify(this.settings));
  }

  getSiteStats(host: string): BlockStats {
    const entry: SiteBlockStats | undefined =
      this.siteStats.find((item: SiteBlockStats) => item.host === host);
    return entry === undefined ? emptyBlockStats() : cloneBlockStats(entry.stats);
  }

  /** Folds a delta into both the per-site total and today's bucket. */
  async recordBlocked(host: string, delta: BlockStats): Promise<void> {
    const amount: number = totalBlocked(delta);
    if (amount === 0) {
      return;
    }
    if (host.length > 0) {
      const existing: SiteBlockStats | undefined =
        this.siteStats.find((item: SiteBlockStats) => item.host === host);
      if (existing === undefined) {
        this.siteStats = this.siteStats.concat([{ host: host, stats: cloneBlockStats(delta) }]);
      } else {
        existing.stats = addBlockStats(existing.stats, delta);
      }
      await this.save(SITE_STATS_KEY, JSON.stringify(this.siteStats));
    }

    const today: string = todayKey();
    const bucket: DailyBlockCount | undefined =
      this.dailyStats.find((item: DailyBlockCount) => item.day === today);
    if (bucket === undefined) {
      this.dailyStats = this.dailyStats.concat([{ day: today, count: amount }]);
    } else {
      bucket.count += amount;
    }
    this.pruneDailyStats();
    await this.save(DAILY_STATS_KEY, JSON.stringify(this.dailyStats));
  }

  /** Total shown at the bottom of the start page. */
  getWeeklyBlocked(): number {
    const window: string[] = recentDayKeys(WEEKLY_WINDOW_DAYS);
    return this.dailyStats
      .filter((item: DailyBlockCount) => window.includes(item.day))
      .reduce((sum: number, item: DailyBlockCount) => sum + item.count, 0);
  }

  isHostAllowed(host: string): boolean {
    return host.length > 0 && this.allowedHosts.includes(host);
  }

  async setHostAllowed(host: string, allowed: boolean): Promise<void> {
    if (host.length === 0) {
      return;
    }
    const without: string[] = this.allowedHosts.filter((item: string) => item !== host);
    this.allowedHosts = allowed ? without.concat([host]) : without;
    await this.save(ALLOWED_HOSTS_KEY, JSON.stringify(this.allowedHosts));
  }

  async clearBrowsingData(): Promise<void> {
    this.history = [];
    this.siteStats = [];
    this.dailyStats = [];
    await this.save(HISTORY_KEY, '[]');
    await this.save(SITE_STATS_KEY, '[]');
    await this.save(DAILY_STATS_KEY, '[]');
  }

  async clearAllowedHosts(): Promise<void> {
    this.allowedHosts = [];
    await this.save(ALLOWED_HOSTS_KEY, '[]');
  }

  private pruneDailyStats(): void {
    const window: string[] = recentDayKeys(WEEKLY_WINDOW_DAYS);
    this.dailyStats = this.dailyStats
      .filter((item: DailyBlockCount) => window.includes(item.day))
      .map((item: DailyBlockCount) => cloneDailyCount(item));
  }

  private async save(key: string, value: string): Promise<void> {
    if (this.store === undefined) {
      Logger.warn(TAG, `Skip save before initialization: ${key}`);
      return;
    }
    try {
      const store: preferences.Preferences = this.store;
      await store.put(key, value);
      await store.flush();
    } catch (error) {
      Logger.error(TAG, `Failed to save ${key}: ${String(error)}`);
    }
  }

  private decode<T>(value: preferences.ValueType, key: string): T[] {
    if (typeof value !== 'string' || value.length === 0) {
      return [];
    }
    try {
      const parsed: T[] = JSON.parse(value) as T[];
      return Array.isArray(parsed) ? parsed : [];
    } catch (error) {
      Logger.warn(TAG, `Invalid ${key} payload: ${String(error)}`);
      return [];
    }
  }

  /** Field-by-field so a payload written by an older build still loads. */
  private decodeSettings(value: preferences.ValueType): BrowserSettings {
    const fallback: BrowserSettings = defaultBrowserSettings();
    if (typeof value !== 'string' || value.length === 0) {
      return fallback;
    }
    try {
      const parsed: BrowserSettings = JSON.parse(value) as BrowserSettings;
      return {
        blockAds: parsed.blockAds ?? fallback.blockAds,
        blockTrackers: parsed.blockTrackers ?? fallback.blockTrackers,
        ruleStrength: parsed.ruleStrength ?? fallback.ruleStrength,
        searchEngine: parsed.searchEngine ?? fallback.searchEngine,
        customSearchTemplate: parsed.customSearchTemplate ?? fallback.customSearchTemplate,
        searchSuggestionsEnabled: parsed.searchSuggestionsEnabled ?? fallback.searchSuggestionsEnabled,
        gesturesEnabled: parsed.gesturesEnabled ?? fallback.gesturesEnabled,
        gestureActionsEnabled: parsed.gestureActionsEnabled ?? fallback.gestureActionsEnabled,
        gestureTabSwitchEnabled: parsed.gestureTabSwitchEnabled ?? fallback.gestureTabSwitchEnabled,
        gestureBlockingEnabled: parsed.gestureBlockingEnabled ?? fallback.gestureBlockingEnabled,
        autoHideToolbarEnabled: parsed.autoHideToolbarEnabled ?? fallback.autoHideToolbarEnabled,
        quickSitesEnabled: parsed.quickSitesEnabled ?? fallback.quickSitesEnabled,
        tabExpiryDays: parsed.tabExpiryDays ?? fallback.tabExpiryDays,
        tabSoftLimit: parsed.tabSoftLimit ?? fallback.tabSoftLimit,
        appearance: parsed.appearance ?? fallback.appearance,
        clearCookiesOnTabClose: parsed.clearCookiesOnTabClose ?? fallback.clearCookiesOnTabClose,
        readerFontSize: parsed.readerFontSize ?? fallback.readerFontSize,
        readerLineHeight: parsed.readerLineHeight ?? fallback.readerLineHeight,
        readerPaper: parsed.readerPaper ?? fallback.readerPaper
      };
    } catch (error) {
      Logger.warn(TAG, `Invalid settings payload: ${String(error)}`);
      return fallback;
    }
  }

  private decodeSession(value: preferences.ValueType): BrowserSession | undefined {
    if (typeof value !== 'string' || value.length === 0) {
      return undefined;
    }
    try {
      const parsed: BrowserSession = JSON.parse(value) as BrowserSession;
      if (!Array.isArray(parsed.tabs) || parsed.tabs.length === 0) {
        return undefined;
      }
      return {
        tabs: parsed.tabs.map((tab: BrowserTab): BrowserTab => this.decodeTab(tab)),
        activeTabId: parsed.activeTabId
      };
    } catch (error) {
      Logger.warn(TAG, `Invalid ${SESSION_KEY} payload: ${String(error)}`);
      return undefined;
    }
  }

  private decodeTab(tab: BrowserTab): BrowserTab {
    const decoded: BrowserTab = {
      id: tab.id,
      url: tab.url,
      title: tab.title ?? '',
      isPrivate: false,
      isLoading: false,
      progress: 100,
      isDesktop: tab.isDesktop ?? false,
      isReader: false,
      canGoBack: false,
      canGoForward: false,
      blocked: emptyBlockStats(),
      faviconUrl: tab.faviconUrl ?? '',
      lastVisitedAt: tab.lastVisitedAt ?? Date.now(),
      scrollY: tab.scrollY ?? 0,
      readerScrollY: tab.readerScrollY ?? 0,
      scrollSavedAt: tab.scrollSavedAt ?? 0,
      readerScrollSavedAt: tab.readerScrollSavedAt ?? 0,
      loadError: LoadErrorKind.None,
      securityState: SecurityState.Unknown
    };
    return cloneTab(decoded);
  }

  /** Kept for symmetry with the other getters; used by the blocking panel. */
  getSiteStatsSnapshot(): SiteBlockStats[] {
    return this.siteStats.map((item: SiteBlockStats) => cloneSiteStats(item));
  }
}
