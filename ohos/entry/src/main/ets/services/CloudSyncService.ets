import { http } from '@kit.NetworkKit';
import {
  ArticleTombstone,
  BookmarkFolder,
  BookmarkTombstone,
  RemoteDeviceTabEntry,
  RemoteDeviceTabGroup
} from '../models/AccountSyncModels';
import {
  ArticleHighlight,
  ArticleNote,
  ArticleSaveFailure,
  SavedArticle
} from '../models/ArticleLibraryModels';
import {
  AppearanceMode,
  BrowserSettings,
  ReaderPaper,
  RuleStrength,
  SavedItem,
  SearchEngine,
  WebDarkModePreference,
  cloneSettings
} from '../models/BrowserModels';
import { SiteControl, SiteControlMode } from '../models/SiteControlModels';
import { Logger } from '../utils/Logger';
import { BrowserViewModel } from '../viewmodels/BrowserViewModel';
import { AccountAuthService } from './AccountAuthService';
import { ProEntitlementService } from './ProEntitlementService';
import {
  ArticleMetaMergeOutput,
  BookmarkSyncMergeOutput,
  mergeArticlesMeta,
  mergeBookmarkSync,
  mergeSiteControls,
  normalizeTimestampMs,
  sanitizeDeviceTabs
} from './SyncMergePolicy';

const TAG: string = 'CloudSyncService';

interface SyncScopePushWire {
  baseVersion: number;
  encryptionMode: string;
  payload: Object;
}

interface SyncPushRequestWire {
  deviceId: string;
  deviceName: string;
  platform: string;
  scopes: Record<string, SyncScopePushWire>;
  deviceTabs: RemoteDeviceTabEntry[];
}

interface ArticleBundleUploadWire {
  html: string;
  markdown: string;
  text: string;
}

interface BookmarkFolderWire {
  id: string;
  name: string;
  iconName: string;
  createdAt: number;
  updatedAt: number;
  sortOrder: number;
  isPinnedToStartPage: boolean;
}

interface BookmarkItemWire {
  id: string;
  title: string;
  url: string;
  folderId: string;
  createdAt: number;
  updatedAt: number;
  isRead: boolean;
  tags: string[];
  isPinnedToStartPage: boolean;
  sortOrder: number;
}

interface BookmarkTombstoneWire {
  id: string;
  url: string;
  isFolder: boolean;
  deletedAt: number;
}

interface BookmarksPayloadWire {
  version: number;
  folders: BookmarkFolderWire[];
  items: BookmarkItemWire[];
  tombstones: BookmarkTombstoneWire[];
  updatedAt: number;
}

interface SettingsPayloadWire {
  blockAds: boolean;
  blockTrackers: boolean;
  ruleStrength: number;
  searchEngine: number;
  customSearchTemplate: string;
  searchSuggestionsEnabled: boolean;
  appearance: number;
  webDarkMode: number;
  webDarkModeExcludedHosts: string[];
  minimumFontSize: number;
  readerFontSize: number;
  readerLineHeight: number;
  readerPaper: number;
  updatedAt: number;
}

interface SiteControlItemWire {
  host: string;
  networkBlocking: number;
  trackerBlocking: number;
  cosmeticCleanup: number;
  autoReader: number;
  darkMode: number;
  desktopUserAgent: number;
  updatedAt: number;
}

interface SiteControlsPayloadWire {
  controls: SiteControlItemWire[];
  tombstones: Object[];
  updatedAt: number;
}

interface ArticleHighlightWire {
  id: string;
  quote: string;
  prefixContext: string;
  suffixContext: string;
  color: string;
  createdAt: number;
  updatedAt: number;
}

interface ArticleNoteWire {
  id: string;
  content: string;
  createdAt: number;
  updatedAt: number;
}

interface ArticleMetaItemWire {
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
  highlights: ArticleHighlightWire[];
  notes: ArticleNoteWire[];
}

interface ArticleTombstoneWire {
  id: string;
  canonicalUrl: string;
  deletedAt: number;
}

interface ArticlesMetaPayloadWire {
  articles: ArticleMetaItemWire[];
  tombstones: ArticleTombstoneWire[];
  updatedAt: number;
}

export class CloudSyncService {
  private static instance: CloudSyncService | null = null;
  private scopeVersions: Record<string, number> = {};
  private remoteDeviceTabs: RemoteDeviceTabGroup[] = [];
  isSyncing: boolean = false;
  lastError: string = '';

  private constructor() {}

  static getInstance(): CloudSyncService {
    if (CloudSyncService.instance === null) {
      CloudSyncService.instance = new CloudSyncService();
    }
    return CloudSyncService.instance;
  }

  getRemoteDeviceTabs(): RemoteDeviceTabGroup[] {
    return this.remoteDeviceTabs.slice(0);
  }

  async sync(context: Context, viewModel: BrowserViewModel): Promise<boolean> {
    const auth: AccountAuthService = AccountAuthService.getInstance();
    if (!auth.isLoggedIn()) {
      return false;
    }
    if (this.isSyncing) {
      return false;
    }

    this.isSyncing = true;
    this.lastError = '';
    const token: string = auth.getToken();
    const isPro: boolean = ProEntitlementService.getInstance().isPro();
    const scopesQuery: string = isPro
      ? 'bookmarks,settings,site_controls,device_tabs,articles_meta'
      : 'bookmarks,settings,site_controls,device_tabs';
    const encodedDeviceId: string = encodeURIComponent(auth.getDeviceId());

    try {
      const pullRes = await auth.requestJson(
        `/api/sync/v3/pull?scopes=${scopesQuery}&excludeDeviceId=${encodedDeviceId}`,
        http.RequestMethod.GET,
        undefined,
        token
      );
      if (pullRes.status === 401 || pullRes.status === 403) {
        await auth.logout(context);
        this.lastError = '登录凭据已过期，请重新登录';
        return false;
      }
      if (pullRes.status !== 200) {
        this.lastError = `拉取云端数据失败 (HTTP ${pullRes.status})`;
        return false;
      }

      const scopesObj: Record<string, Object> = this.obj(pullRes.payload['scopes']) ?? {};
      let remoteFolders: BookmarkFolder[] = [];
      let remoteItems: SavedItem[] = [];
      let remoteTombstones: BookmarkTombstone[] = [];
      let remoteSettings: Record<string, Object> | null = null;
      let remoteControls: SiteControl[] = [];
      let remoteArticles: SavedArticle[] = [];

      const bmScope: Record<string, Object> | null = this.obj(scopesObj['bookmarks']);
      if (bmScope !== null) {
        this.scopeVersions['bookmarks'] = this.num(bmScope['version'], 0);
        const parsedBm = this.parseBookmarksPayload(this.obj(bmScope['payload']));
        remoteFolders = parsedBm.folders;
        remoteItems = parsedBm.items;
        remoteTombstones = parsedBm.tombstones;
      }

      const stScope: Record<string, Object> | null = this.obj(scopesObj['settings']);
      if (stScope !== null) {
        this.scopeVersions['settings'] = this.num(stScope['version'], 0);
        remoteSettings = this.obj(stScope['payload']);
      }

      const scScope: Record<string, Object> | null = this.obj(scopesObj['site_controls']);
      if (scScope !== null) {
        this.scopeVersions['site_controls'] = this.num(scScope['version'], 0);
        remoteControls = this.parseSiteControls(this.obj(scScope['payload']));
      }

      if (isPro) {
        const amScope: Record<string, Object> | null = this.obj(scopesObj['articles_meta']);
        if (amScope !== null) {
          this.scopeVersions['articles_meta'] = this.num(amScope['version'], 0);
          remoteArticles = this.parseArticlesMeta(this.obj(amScope['payload']));
        }
      }

      this.remoteDeviceTabs = this.parseRemoteDevices(pullRes.payload['remoteDevices']);

      // Merge locally and push with CAS retry
      for (let attempt = 0; attempt < 3; attempt++) {
        const mergedBm: BookmarkSyncMergeOutput = mergeBookmarkSync(
          viewModel.repository.getBookmarkFolders(),
          viewModel.repository.getSavedItems(),
          viewModel.repository.getBookmarkTombstones(),
          remoteFolders,
          remoteItems,
          remoteTombstones,
          Date.now()
        );
        await viewModel.repository.applyBookmarkSyncResult(
          mergedBm.folders,
          mergedBm.items,
          mergedBm.tombstones
        );
        viewModel.savedItems = viewModel.repository.getSavedItems();

        if (remoteControls.length > 0) {
          const mergedControls: SiteControl[] = mergeSiteControls(
            viewModel.siteControls.getAll(),
            remoteControls
          );
          await viewModel.siteControls.replaceAll(mergedControls);
        }

        if (remoteSettings !== null) {
          const nextSettings: BrowserSettings = this.applyCrossPlatformSettings(
            viewModel.settings,
            remoteSettings
          );
          viewModel.settings = nextSettings;
          await viewModel.repository.applySettingsFromSync(nextSettings);
        }

        const nowMs: number = Date.now();
        const scopesPayload: Record<string, SyncScopePushWire> = {};
        const bookmarksEnvelope: SyncScopePushWire = {
          baseVersion: this.scopeVersions['bookmarks'] ?? 0,
          encryptionMode: 'none',
          payload: this.encodeBookmarksPayload(mergedBm.folders, mergedBm.items, mergedBm.tombstones, nowMs)
        };
        scopesPayload['bookmarks'] = bookmarksEnvelope;
        const settingsEnvelope: SyncScopePushWire = {
          baseVersion: this.scopeVersions['settings'] ?? 0,
          encryptionMode: 'none',
          payload: this.encodeCrossPlatformSettings(viewModel.settings, nowMs)
        };
        scopesPayload['settings'] = settingsEnvelope;
        const siteControlsEnvelope: SyncScopePushWire = {
          baseVersion: this.scopeVersions['site_controls'] ?? 0,
          encryptionMode: 'none',
          payload: this.encodeSiteControls(viewModel.siteControls.getAll(), nowMs)
        };
        scopesPayload['site_controls'] = siteControlsEnvelope;

        if (isPro) {
          const localArticles: SavedArticle[] = await viewModel.articleLibrary.listArticles();
          const mergedArticles: ArticleMetaMergeOutput = mergeArticlesMeta(
            localArticles,
            remoteArticles,
            viewModel.repository.getArticleTombstones(),
            nowMs
          );
          const encodedArticles: ArticlesMetaPayloadWire = await this.encodeArticlesMeta(
            viewModel,
            mergedArticles.articles,
            mergedArticles.tombstones,
            nowMs
          );
          const articlesEnvelope: SyncScopePushWire = {
            baseVersion: this.scopeVersions['articles_meta'] ?? 0,
            encryptionMode: 'none',
            payload: encodedArticles
          };
          scopesPayload['articles_meta'] = articlesEnvelope;
        }

        const pushBody: SyncPushRequestWire = {
          deviceId: auth.getDeviceId(),
          deviceName: auth.getDeviceName(),
          platform: 'harmony',
          scopes: scopesPayload,
          deviceTabs: sanitizeDeviceTabs(viewModel.tabs)
        };
        const pushRes = await auth.requestJson('/api/sync/v3/push', http.RequestMethod.POST, pushBody, token);

        const appliedObj: Record<string, Object> | null = this.obj(pushRes.payload['appliedScopes']);
        if (appliedObj !== null) {
          const keys: string[] = Object.keys(appliedObj);
          for (let k = 0; k < keys.length; k++) {
            const scopeName: string = keys[k];
            const info: Record<string, Object> | null = this.obj(appliedObj[scopeName]);
            if (info !== null) {
              this.scopeVersions[scopeName] = this.num(info['version'], 0);
            }
          }
        }

        if (pushRes.status === 409 && Array.isArray(pushRes.payload['conflicts'])) {
          const conflicts: Object[] = pushRes.payload['conflicts'] as Object[];
          for (let c = 0; c < conflicts.length; c++) {
            const conflictObj: Record<string, Object> | null = this.obj(conflicts[c]);
            if (conflictObj === null) {
              continue;
            }
            const scopeName: string = this.str(conflictObj['scope']);
            const curVer: number = this.num(conflictObj['currentVersion'], 0);
            this.scopeVersions[scopeName] = curVer;
            if (scopeName === 'bookmarks') {
              const parsedBm = this.parseBookmarksPayload(this.obj(conflictObj['currentPayload']));
              remoteFolders = parsedBm.folders;
              remoteItems = parsedBm.items;
              remoteTombstones = parsedBm.tombstones;
            } else if (scopeName === 'settings') {
              remoteSettings = this.obj(conflictObj['currentPayload']);
            } else if (scopeName === 'site_controls') {
              remoteControls = this.parseSiteControls(this.obj(conflictObj['currentPayload']));
            } else if (scopeName === 'articles_meta') {
              remoteArticles = this.parseArticlesMeta(this.obj(conflictObj['currentPayload']));
            }
          }
          continue;
        }

        if (pushRes.status !== 200) {
          this.lastError = `推送同步数据失败 (HTTP ${pushRes.status})`;
          return false;
        }

        if (isPro) {
          await this.syncArticleBundles(auth, token, viewModel, remoteArticles);
        }
        await auth.setLastSyncTime(context, nowMs);
        return true;
      }
      this.lastError = '并发冲突过多，请稍后重试';
      return false;
    } catch (error) {
      Logger.warn(TAG, `Sync failed: ${String(error)}`);
      this.lastError = String(error);
      return false;
    } finally {
      this.isSyncing = false;
    }
  }

  private async syncArticleBundles(
    auth: AccountAuthService,
    token: string,
    viewModel: BrowserViewModel,
    remoteArticles: SavedArticle[]
  ): Promise<void> {
    let uploaded: number = 0;
    const localArticles: SavedArticle[] = await viewModel.articleLibrary.listArticles();
    for (let i = 0; i < localArticles.length && uploaded < 5; i++) {
      const article: SavedArticle = localArticles[i];
      if (article.failure !== ArticleSaveFailure.None) {
        continue;
      }
      const html: string = await viewModel.articleLibrary.readArticleHtml(article.id) ?? '';
      const md: string = await viewModel.articleLibrary.readArticleMarkdown(article.id) ?? '';
      if (html.length === 0) {
        continue;
      }
      try {
        const bundleBody: ArticleBundleUploadWire = {
          html: html,
          markdown: md,
          text: article.excerpt
        };
        await auth.requestJson(
          `/api/sync/v3/articles/${encodeURIComponent(article.id)}/bundle`,
          http.RequestMethod.PUT,
          bundleBody,
          token
        );
        uploaded += 1;
      } catch (_err) {
        // Skip failed upload without aborting sync
      }
    }

    for (let j = 0; j < remoteArticles.length; j++) {
      const remote: SavedArticle = remoteArticles[j];
      const existing = await viewModel.articleLibrary.getArticle(remote.id);
      if (existing !== undefined) {
        continue;
      }
      try {
        const res = await auth.requestJson(
          `/api/sync/v3/articles/${encodeURIComponent(remote.id)}/bundle`,
          http.RequestMethod.GET,
          undefined,
          token
        );
        if (res.status === 200) {
          const html: string = this.str(res.payload['html']);
          const md: string = this.str(res.payload['markdown']);
          if (html.length > 0) {
            await viewModel.articleLibrary.saveArticle(remote, html, md, []);
          }
        }
      } catch (_err) {
        // Ignore single article download failure
      }
    }
  }

  private encodeBookmarksPayload(
    folders: BookmarkFolder[],
    items: SavedItem[],
    tombstones: BookmarkTombstone[],
    nowMs: number
  ): BookmarksPayloadWire {
    const encodedFolders: BookmarkFolderWire[] = folders.map((f: BookmarkFolder): BookmarkFolderWire => {
      const folderWire: BookmarkFolderWire = {
        id: f.id,
        name: f.name,
        iconName: f.iconName,
        createdAt: f.createdAt,
        updatedAt: f.updatedAt,
        sortOrder: f.sortOrder,
        isPinnedToStartPage: f.isPinnedToStartPage
      };
      return folderWire;
    });
    const encodedItems: BookmarkItemWire[] = items.map((item: SavedItem): BookmarkItemWire => {
      const itemWire: BookmarkItemWire = {
        id: item.id,
        title: item.title,
        url: item.url,
        folderId: item.folderId ?? '',
        createdAt: item.createdAt,
        updatedAt: item.updatedAt,
        isRead: item.isRead,
        tags: item.tags,
        isPinnedToStartPage: item.isPinnedToStartPage ?? (item.folderId === undefined),
        sortOrder: item.sortOrder ?? 0
      };
      return itemWire;
    });
    const encodedTombstones: BookmarkTombstoneWire[] = tombstones.map((tb: BookmarkTombstone): BookmarkTombstoneWire => {
      const tbWire: BookmarkTombstoneWire = {
        id: tb.id,
        url: tb.url,
        isFolder: tb.isFolder,
        deletedAt: tb.deletedAt
      };
      return tbWire;
    });
    const result: BookmarksPayloadWire = {
      version: 3,
      folders: encodedFolders,
      items: encodedItems,
      tombstones: encodedTombstones,
      updatedAt: nowMs
    };
    return result;
  }

  private parseBookmarksPayload(payload: Record<string, Object> | null): BookmarkSyncMergeOutput {
    if (payload === null) {
      return { folders: [], items: [], tombstones: [] };
    }
    const now: number = Date.now();
    const folders: BookmarkFolder[] = [];
    const rawFolders: Object[] = Array.isArray(payload['folders']) ? payload['folders'] as Object[] : [];
    for (let i = 0; i < rawFolders.length; i++) {
      const obj: Record<string, Object> | null = this.obj(rawFolders[i]);
      if (obj === null) {
        continue;
      }
      const id: string = this.str(obj['id']);
      if (id.length === 0) {
        continue;
      }
      const createdAt: number = normalizeTimestampMs(this.num(obj['createdAt'], now), now);
      folders.push({
        id: id,
        name: this.str(obj['name']) || '文件夹',
        iconName: this.str(obj['iconName']) || 'folder.fill',
        createdAt: createdAt,
        updatedAt: normalizeTimestampMs(this.num(obj['updatedAt'], createdAt), createdAt),
        sortOrder: this.num(obj['sortOrder'], 0),
        isPinnedToStartPage: obj['isPinnedToStartPage'] !== false
      });
    }

    const items: SavedItem[] = [];
    const rawItems: Object[] = Array.isArray(payload['items'])
      ? payload['items'] as Object[]
      : (Array.isArray(payload['entries']) ? payload['entries'] as Object[] : []);
    for (let i = 0; i < rawItems.length; i++) {
      const obj: Record<string, Object> | null = this.obj(rawItems[i]);
      if (obj === null) {
        continue;
      }
      const url: string = this.str(obj['url']);
      if (url.length === 0) {
        continue;
      }
      const createdAt: number = normalizeTimestampMs(this.num(obj['createdAt'], now), now);
      const rawFolderId: string = this.str(obj['folderId']) || this.str(obj['folderID']);
      const tags: string[] = Array.isArray(obj['tags'])
        ? (obj['tags'] as Object[]).filter((t: Object): boolean => typeof t === 'string') as string[]
        : [];
      items.push({
        id: this.str(obj['id']) || `saved-${i}-${now}`,
        title: this.str(obj['title']) || url,
        url: url,
        folderId: rawFolderId.length > 0 ? rawFolderId : undefined,
        createdAt: createdAt,
        updatedAt: normalizeTimestampMs(this.num(obj['updatedAt'], createdAt), createdAt),
        isRead: obj['isRead'] !== false,
        tags: tags,
        isPinnedToStartPage: obj['isPinnedToStartPage'] === true,
        sortOrder: this.num(obj['sortOrder'], 0)
      });
    }

    const tombstones: BookmarkTombstone[] = [];
    const rawTb: Object[] = Array.isArray(payload['tombstones']) ? payload['tombstones'] as Object[] : [];
    for (let i = 0; i < rawTb.length; i++) {
      const obj: Record<string, Object> | null = this.obj(rawTb[i]);
      if (obj === null) {
        continue;
      }
      const id: string = this.str(obj['id']);
      if (id.length === 0) {
        continue;
      }
      tombstones.push({
        id: id,
        url: this.str(obj['url']),
        isFolder: obj['isFolder'] === true,
        deletedAt: normalizeTimestampMs(this.num(obj['deletedAt'], now), now)
      });
    }

    return { folders: folders, items: items, tombstones: tombstones };
  }

  private encodeCrossPlatformSettings(settings: BrowserSettings, nowMs: number): SettingsPayloadWire {
    const payload: SettingsPayloadWire = {
      blockAds: settings.blockAds,
      blockTrackers: settings.blockTrackers,
      ruleStrength: settings.ruleStrength as number,
      searchEngine: settings.searchEngine as number,
      customSearchTemplate: settings.customSearchTemplate,
      searchSuggestionsEnabled: settings.searchSuggestionsEnabled,
      appearance: settings.appearance as number,
      webDarkMode: settings.webDarkMode as number,
      webDarkModeExcludedHosts: settings.webDarkModeExcludedHosts,
      minimumFontSize: settings.minimumFontSize,
      readerFontSize: settings.readerFontSize,
      readerLineHeight: settings.readerLineHeight,
      readerPaper: settings.readerPaper as number,
      updatedAt: nowMs
    };
    return payload;
  }

  private applyCrossPlatformSettings(current: BrowserSettings, remote: Record<string, Object>): BrowserSettings {
    const next: BrowserSettings = cloneSettings(current);
    if (typeof remote['blockAds'] === 'boolean') {
      next.blockAds = remote['blockAds'] as boolean;
    }
    if (typeof remote['blockTrackers'] === 'boolean') {
      next.blockTrackers = remote['blockTrackers'] as boolean;
    }
    if (typeof remote['ruleStrength'] === 'number') {
      next.ruleStrength = remote['ruleStrength'] === 1 ? RuleStrength.Strict : RuleStrength.Standard;
    }
    if (typeof remote['searchEngine'] === 'number') {
      next.searchEngine = remote['searchEngine'] as SearchEngine;
    } else if (typeof remote['searchEngine'] === 'string') {
      const lower: string = (remote['searchEngine'] as string).toLowerCase();
      if (lower === 'bing') next.searchEngine = SearchEngine.Bing;
      if (lower === 'baidu') next.searchEngine = SearchEngine.Baidu;
      if (lower === 'google') next.searchEngine = SearchEngine.Google;
      if (lower === 'duckduckgo') next.searchEngine = SearchEngine.DuckDuckGo;
    }
    if (typeof remote['customSearchTemplate'] === 'string') {
      next.customSearchTemplate = remote['customSearchTemplate'] as string;
    }
    if (typeof remote['searchSuggestionsEnabled'] === 'boolean') {
      next.searchSuggestionsEnabled = remote['searchSuggestionsEnabled'] as boolean;
    }
    if (typeof remote['appearance'] === 'number') {
      next.appearance = remote['appearance'] as AppearanceMode;
    }
    if (typeof remote['webDarkMode'] === 'number') {
      next.webDarkMode = remote['webDarkMode'] as WebDarkModePreference;
    }
    if (Array.isArray(remote['webDarkModeExcludedHosts'])) {
      next.webDarkModeExcludedHosts = (remote['webDarkModeExcludedHosts'] as Object[])
        .filter((h: Object): boolean => typeof h === 'string') as string[];
    }
    if (typeof remote['minimumFontSize'] === 'number') {
      next.minimumFontSize = remote['minimumFontSize'] as number;
    }
    if (typeof remote['readerFontSize'] === 'number') {
      next.readerFontSize = remote['readerFontSize'] as number;
    }
    if (typeof remote['readerLineHeight'] === 'number') {
      next.readerLineHeight = remote['readerLineHeight'] as number;
    }
    if (typeof remote['readerPaper'] === 'number') {
      next.readerPaper = remote['readerPaper'] as ReaderPaper;
    }
    return next;
  }

  private encodeSiteControls(controls: SiteControl[], nowMs: number): SiteControlsPayloadWire {
    const encodedControls: SiteControlItemWire[] = controls.map((c: SiteControl): SiteControlItemWire => {
      const controlWire: SiteControlItemWire = {
        host: c.host,
        networkBlocking: c.networkBlocking as number,
        trackerBlocking: c.trackerBlocking as number,
        cosmeticCleanup: c.cosmeticCleanup as number,
        autoReader: c.autoReader as number,
        darkMode: c.darkMode as number,
        desktopUserAgent: c.desktopUserAgent as number,
        updatedAt: nowMs
      };
      return controlWire;
    });
    const payload: SiteControlsPayloadWire = {
      controls: encodedControls,
      tombstones: [],
      updatedAt: nowMs
    };
    return payload;
  }

  private parseSiteControls(payload: Record<string, Object> | null): SiteControl[] {
    if (payload === null || !Array.isArray(payload['controls'])) {
      return [];
    }
    const raw: Object[] = payload['controls'] as Object[];
    const list: SiteControl[] = [];
    for (let i = 0; i < raw.length; i++) {
      const obj: Record<string, Object> | null = this.obj(raw[i]);
      if (obj === null) {
        continue;
      }
      const host: string = this.str(obj['host']).toLowerCase();
      if (host.length === 0) {
        continue;
      }
      list.push({
        host: host,
        networkBlocking: this.num(obj['networkBlocking'], 0) as SiteControlMode,
        trackerBlocking: this.num(obj['trackerBlocking'], 0) as SiteControlMode,
        cosmeticCleanup: this.num(obj['cosmeticCleanup'], 0) as SiteControlMode,
        autoReader: this.num(obj['autoReader'], 0) as SiteControlMode,
        darkMode: this.num(obj['darkMode'], 0) as SiteControlMode,
        desktopUserAgent: this.num(obj['desktopUserAgent'], 0) as SiteControlMode
      });
    }
    return list;
  }

  private async encodeArticlesMeta(
    viewModel: BrowserViewModel,
    articles: SavedArticle[],
    tombstones: ArticleTombstone[],
    nowMs: number
  ): Promise<ArticlesMetaPayloadWire> {
    const encodedList: ArticleMetaItemWire[] = [];
    for (let i = 0; i < articles.length; i++) {
      const a: SavedArticle = articles[i];
      if (a.failure !== ArticleSaveFailure.None) {
        continue;
      }
      const highlights: ArticleHighlight[] = await viewModel.articleLibrary.listHighlights(a.id);
      const notes: ArticleNote[] = await viewModel.articleLibrary.listNotes(a.id);
      const encodedHighlights: ArticleHighlightWire[] = highlights.map((h: ArticleHighlight): ArticleHighlightWire => {
        const hlWire: ArticleHighlightWire = {
          id: h.id,
          quote: h.textQuote,
          prefixContext: h.prefix,
          suffixContext: h.suffix,
          color: 'yellow',
          createdAt: h.createdAt,
          updatedAt: h.createdAt
        };
        return hlWire;
      });
      const encodedNotes: ArticleNoteWire[] = notes.map((n: ArticleNote): ArticleNoteWire => {
        const noteWire: ArticleNoteWire = {
          id: n.id,
          content: n.body,
          createdAt: n.createdAt,
          updatedAt: n.updatedAt
        };
        return noteWire;
      });
      const itemWire: ArticleMetaItemWire = {
        id: a.id,
        sourceUrl: a.sourceUrl,
        canonicalUrl: a.canonicalUrl,
        title: a.title,
        author: a.author,
        excerpt: a.excerpt,
        createdAt: a.createdAt,
        updatedAt: a.updatedAt,
        readingPosition: a.readingPosition,
        tags: a.tags,
        topics: a.topicNames ?? [],
        isArchived: a.isArchived,
        quality: a.quality ?? 'partial',
        highlights: encodedHighlights,
        notes: encodedNotes
      };
      encodedList.push(itemWire);
    }
    const encodedTombstones: ArticleTombstoneWire[] = tombstones.map((t: ArticleTombstone): ArticleTombstoneWire => {
      const tbWire: ArticleTombstoneWire = {
        id: t.id,
        canonicalUrl: t.canonicalUrl,
        deletedAt: t.deletedAt
      };
      return tbWire;
    });
    const result: ArticlesMetaPayloadWire = {
      articles: encodedList,
      tombstones: encodedTombstones,
      updatedAt: nowMs
    };
    return result;
  }

  private parseArticlesMeta(payload: Record<string, Object> | null): SavedArticle[] {
    if (payload === null || !Array.isArray(payload['articles'])) {
      return [];
    }
    const now: number = Date.now();
    const raw: Object[] = payload['articles'] as Object[];
    const list: SavedArticle[] = [];
    for (let i = 0; i < raw.length; i++) {
      const obj: Record<string, Object> | null = this.obj(raw[i]);
      if (obj === null) {
        continue;
      }
      const id: string = this.str(obj['id']);
      const sourceUrl: string = this.str(obj['sourceUrl']);
      if (id.length === 0 || sourceUrl.length === 0) {
        continue;
      }
      const createdAt: number = normalizeTimestampMs(this.num(obj['createdAt'], now), now);
      list.push({
        id: id,
        sourceUrl: sourceUrl,
        canonicalUrl: this.str(obj['canonicalUrl']) || sourceUrl,
        title: this.str(obj['title']) || sourceUrl,
        author: this.str(obj['author']),
        excerpt: this.str(obj['excerpt']),
        createdAt: createdAt,
        updatedAt: normalizeTimestampMs(this.num(obj['updatedAt'], createdAt), createdAt),
        readingPosition: this.num(obj['readingPosition'], 0),
        tags: Array.isArray(obj['tags']) ? obj['tags'] as string[] : [],
        isArchived: obj['isArchived'] === true,
        failure: ArticleSaveFailure.None,
        failureMessage: '',
        quality: this.str(obj['quality']) || 'partial',
        topicNames: Array.isArray(obj['topics']) ? obj['topics'] as string[] : []
      });
    }
    return list;
  }

  private parseRemoteDevices(raw: Object | undefined): RemoteDeviceTabGroup[] {
    if (!Array.isArray(raw)) {
      return [];
    }
    const groups: RemoteDeviceTabGroup[] = [];
    const arr: Object[] = raw as Object[];
    for (let i = 0; i < arr.length; i++) {
      const obj: Record<string, Object> | null = this.obj(arr[i]);
      if (obj === null) {
        continue;
      }
      const deviceId: string = this.str(obj['deviceId']);
      if (deviceId.length === 0) {
        continue;
      }
      const tabs: RemoteDeviceTabEntry[] = [];
      const rawTabs: Object[] = Array.isArray(obj['tabs']) ? obj['tabs'] as Object[] : [];
      for (let t = 0; t < rawTabs.length; t++) {
        const tabObj: Record<string, Object> | null = this.obj(rawTabs[t]);
        if (tabObj === null) {
          continue;
        }
        const url: string = this.str(tabObj['url']);
        if (url.length === 0) {
          continue;
        }
        tabs.push({
          id: this.str(tabObj['id']) || `rt-${t}`,
          title: this.str(tabObj['title']) || url,
          url: url,
          lastVisitedAt: this.num(tabObj['lastVisitedAt'], 0)
        });
      }
      groups.push({
        deviceId: deviceId,
        deviceName: this.str(obj['deviceName']) || '其他设备',
        platform: this.str(obj['platform']) || 'unknown',
        updatedAt: this.num(obj['updatedAt'], 0),
        tabs: tabs
      });
    }
    return groups;
  }

  private obj(value: Object | undefined): Record<string, Object> | null {
    if (value !== undefined && value !== null && typeof value === 'object' && !Array.isArray(value)) {
      return value as Record<string, Object>;
    }
    return null;
  }

  private str(value: Object | undefined): string {
    return typeof value === 'string' ? value : '';
  }

  private num(value: Object | undefined, fallback: number): number {
    return typeof value === 'number' && Number.isFinite(value) ? value : fallback;
  }
}
