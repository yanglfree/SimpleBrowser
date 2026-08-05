import { common } from '@kit.AbilityKit';
import { HOME_URL } from '../constants/AppConstants';
import {
  Bookmark,
  BrowserSettings,
  BrowserTab,
  BrowserTabUpdate,
  HistoryEntry,
  cloneSettings,
  cloneTab
} from '../models/BrowserModels';
import { BrowserRepository } from '../repositories/BrowserRepository';
import { AdsBlockService } from '../services/AdsBlockService';
import { DownloadService } from '../services/DownloadService';
import { Logger } from '../utils/Logger';

const TAG: string = 'BrowserViewModel';

export class BrowserViewModel {
  readonly repository: BrowserRepository = new BrowserRepository();
  readonly adsBlockService: AdsBlockService = new AdsBlockService();
  tabs: BrowserTab[] = [];
  bookmarks: Bookmark[] = [];
  history: HistoryEntry[] = [];
  settings: BrowserSettings = {
    isAdsBlockingEnabled: true,
    isDarkModeEnabled: false,
    isDesktopModeEnabled: false
  };
  activeTabId: string = '';
  private tabSequence: number = 0;

  async initialize(context: common.UIAbilityContext): Promise<void> {
    await this.repository.initialize(context);
    this.bookmarks = this.repository.getBookmarks();
    this.history = this.repository.getHistory();
    this.settings = this.repository.getSettings();
    this.tabs = [this.createTab(HOME_URL, false)];
    this.activeTabId = this.tabs[0].id;
    await this.adsBlockService.initialize(context);
    DownloadService.configure();
  }

  getActiveTab(): BrowserTab | undefined {
    return this.tabs.find((tab: BrowserTab) => tab.id === this.activeTabId);
  }

  createTab(url: string, isPrivate: boolean): BrowserTab {
    this.tabSequence += 1;
    return {
      id: `tab-${this.tabSequence}`,
      url,
      title: isPrivate ? 'Private tab' : 'New tab',
      isPrivate,
      isLoading: true,
      progress: 0,
      blockedCount: 0
    };
  }

  addTab(url: string = HOME_URL, isPrivate: boolean = false): BrowserTab {
    const tab: BrowserTab = this.createTab(url, isPrivate);
    this.tabs = this.tabs.concat([tab]);
    this.activeTabId = tab.id;
    return tab;
  }

  closeTab(id: string): void {
    if (this.tabs.length === 1) {
      return;
    }
    const index: number = this.tabs.findIndex((tab: BrowserTab) => tab.id === id);
    this.tabs = this.tabs.filter((tab: BrowserTab) => tab.id !== id);
    if (id === this.activeTabId) {
      const nextIndex: number = Math.min(index, this.tabs.length - 1);
      this.activeTabId = this.tabs[nextIndex].id;
    }
  }

  selectTab(id: string): void {
    if (this.tabs.some((tab: BrowserTab) => tab.id === id)) {
      this.activeTabId = id;
    }
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
      if (update.blockedCount !== undefined) {
        updated.blockedCount = update.blockedCount;
      }
      return updated;
    });
  }

  async recordPageVisit(tab: BrowserTab): Promise<void> {
    if (tab.isPrivate || tab.url === HOME_URL) {
      return;
    }
    const entry: HistoryEntry = {
      id: `history-${Date.now()}`,
      title: tab.title,
      url: tab.url,
      visitedAt: Date.now()
    };
    await this.repository.recordHistory(entry);
    this.history = this.repository.getHistory();
  }

  async toggleBookmark(tab: BrowserTab): Promise<boolean> {
    const existing: Bookmark | undefined = this.bookmarks.find((item: Bookmark) => item.url === tab.url);
    if (existing !== undefined) {
      await this.repository.removeBookmark(existing.id);
    } else {
      const bookmark: Bookmark = {
        id: `bookmark-${Date.now()}`,
        title: tab.title,
        url: tab.url,
        createdAt: Date.now()
      };
      await this.repository.addBookmark(bookmark);
    }
    this.bookmarks = this.repository.getBookmarks();
    return existing === undefined;
  }

  isBookmarked(url: string): boolean {
    return this.bookmarks.some((item: Bookmark) => item.url === url);
  }

  async clearHistory(): Promise<void> {
    await this.repository.clearHistory();
    this.history = [];
  }

  async updateSettings(settings: BrowserSettings): Promise<void> {
    this.settings = cloneSettings(settings);
    await this.repository.saveSettings(this.settings);
    Logger.info(TAG, 'Browser settings updated');
  }

  copyTab(tab: BrowserTab): BrowserTab | undefined {
    return tab === undefined ? undefined : cloneTab(tab);
  }
}
