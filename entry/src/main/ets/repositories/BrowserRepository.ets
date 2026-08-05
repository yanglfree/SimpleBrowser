import { common } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';
import { MAX_BOOKMARK_COUNT, MAX_HISTORY_COUNT, STORE_NAME } from '../constants/AppConstants';
import {
  Bookmark,
  BrowserSettings,
  HistoryEntry,
  cloneBookmark,
  cloneHistoryEntry,
  cloneSettings,
  defaultBrowserSettings
} from '../models/BrowserModels';
import { Logger } from '../utils/Logger';

const TAG: string = 'BrowserRepository';
const BOOKMARKS_KEY: string = 'bookmarks';
const HISTORY_KEY: string = 'history';
const SETTINGS_KEY: string = 'settings';

export class BrowserRepository {
  private store: preferences.Preferences | undefined;
  private bookmarks: Bookmark[] = [];
  private history: HistoryEntry[] = [];
  private settings: BrowserSettings = defaultBrowserSettings();

  async initialize(context: common.UIAbilityContext): Promise<void> {
    try {
      this.store = await preferences.getPreferences(context, STORE_NAME);
      const store: preferences.Preferences = this.store;
      const savedBookmarks: preferences.ValueType = await store.get(BOOKMARKS_KEY, '[]');
      const savedHistory: preferences.ValueType = await store.get(HISTORY_KEY, '[]');
      const savedSettings: preferences.ValueType = await store.get(SETTINGS_KEY, '');
      this.bookmarks = this.decodeBookmarks(savedBookmarks);
      this.history = this.decodeHistory(savedHistory);
      this.settings = this.decodeSettings(savedSettings);
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

  async addBookmark(bookmark: Bookmark): Promise<void> {
    const filtered: Bookmark[] = this.bookmarks.filter((item: Bookmark) => item.url !== bookmark.url);
    this.bookmarks = [bookmark].concat(filtered).slice(0, MAX_BOOKMARK_COUNT);
    await this.save(BOOKMARKS_KEY, JSON.stringify(this.bookmarks));
  }

  async removeBookmark(id: string): Promise<void> {
    this.bookmarks = this.bookmarks.filter((item: Bookmark) => item.id !== id);
    await this.save(BOOKMARKS_KEY, JSON.stringify(this.bookmarks));
  }

  async recordHistory(entry: HistoryEntry): Promise<void> {
    const filtered: HistoryEntry[] = this.history.filter((item: HistoryEntry) => item.url !== entry.url);
    this.history = [entry].concat(filtered).slice(0, MAX_HISTORY_COUNT);
    await this.save(HISTORY_KEY, JSON.stringify(this.history));
  }

  async clearHistory(): Promise<void> {
    this.history = [];
    await this.save(HISTORY_KEY, '[]');
  }

  async saveSettings(settings: BrowserSettings): Promise<void> {
    this.settings = cloneSettings(settings);
    await this.save(SETTINGS_KEY, JSON.stringify(this.settings));
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

  private decodeBookmarks(value: preferences.ValueType): Bookmark[] {
    if (typeof value !== 'string') {
      return [];
    }
    try {
      return JSON.parse(value) as Bookmark[];
    } catch (error) {
      Logger.warn(TAG, `Invalid bookmarks payload: ${String(error)}`);
      return [];
    }
  }

  private decodeHistory(value: preferences.ValueType): HistoryEntry[] {
    if (typeof value !== 'string') {
      return [];
    }
    try {
      return JSON.parse(value) as HistoryEntry[];
    } catch (error) {
      Logger.warn(TAG, `Invalid history payload: ${String(error)}`);
      return [];
    }
  }

  private decodeSettings(value: preferences.ValueType): BrowserSettings {
    if (typeof value !== 'string' || value.length === 0) {
      return defaultBrowserSettings();
    }
    try {
      const parsed: BrowserSettings = JSON.parse(value) as BrowserSettings;
      return {
        isAdsBlockingEnabled: parsed.isAdsBlockingEnabled,
        isDarkModeEnabled: parsed.isDarkModeEnabled,
        isDesktopModeEnabled: parsed.isDesktopModeEnabled
      };
    } catch (error) {
      Logger.warn(TAG, `Invalid settings payload: ${String(error)}`);
      return defaultBrowserSettings();
    }
  }
}
