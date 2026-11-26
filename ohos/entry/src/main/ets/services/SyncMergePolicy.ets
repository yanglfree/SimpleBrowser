import {
  ArticleTombstone,
  BookmarkFolder,
  BookmarkTombstone,
  RemoteDeviceTabEntry
} from '../models/AccountSyncModels';
import {
  ArticleHighlight,
  ArticleNote,
  SavedArticle,
  cloneArticleHighlight,
  cloneArticleNote,
  cloneSavedArticle
} from '../models/ArticleLibraryModels';
import { BrowserTab, SavedItem, cloneSavedItem } from '../models/BrowserModels';
import { SiteControl, cloneSiteControl } from '../models/SiteControlModels';

export const TOMBSTONE_RETENTION_MS: number = 60 * 24 * 60 * 60 * 1000;

export interface BookmarkSyncMergeOutput {
  folders: BookmarkFolder[];
  items: SavedItem[];
  tombstones: BookmarkTombstone[];
}

export interface ArticleMetaMergeOutput {
  articles: SavedArticle[];
  tombstones: ArticleTombstone[];
}

export function normalizeTimestampMs(raw: number, fallbackMs: number): number {
  if (!Number.isFinite(raw) || raw <= 0) {
    return fallbackMs;
  }
  if (raw < 10000000000) {
    return Math.round(raw * 1000);
  }
  return Math.round(raw);
}

export function normalizeComparableUrl(url: string): string {
  let trimmed: string = url.trim();
  while (trimmed.endsWith('/') && trimmed.length > 1) {
    trimmed = trimmed.substring(0, trimmed.length - 1);
  }
  return trimmed.toLowerCase();
}

export function isInternalOrBlankUrl(url: string): boolean {
  const norm: string = normalizeComparableUrl(url);
  if (norm.length === 0 || norm === 'about:blank' || norm === 'browser://home' || norm === 'zhuo://home') {
    return true;
  }
  return norm.startsWith('javascript:') || norm.startsWith('data:') ||
    norm.startsWith('browser://') || norm.startsWith('zhuo://');
}

export function cloneBookmarkFolder(folder: BookmarkFolder): BookmarkFolder {
  return {
    id: folder.id,
    name: folder.name,
    iconName: folder.iconName,
    createdAt: folder.createdAt,
    updatedAt: folder.updatedAt,
    sortOrder: folder.sortOrder,
    isPinnedToStartPage: folder.isPinnedToStartPage
  };
}

export function cloneBookmarkTombstone(tb: BookmarkTombstone): BookmarkTombstone {
  return {
    id: tb.id,
    url: tb.url,
    isFolder: tb.isFolder,
    deletedAt: tb.deletedAt
  };
}

export function mergeBookmarkSync(
  localFolders: BookmarkFolder[],
  localItems: SavedItem[],
  localTombstones: BookmarkTombstone[],
  remoteFolders: BookmarkFolder[],
  remoteItems: SavedItem[],
  remoteTombstones: BookmarkTombstone[],
  nowMs: number = Date.now()
): BookmarkSyncMergeOutput {
  const cutoff: number = nowMs - TOMBSTONE_RETENTION_MS;
  const tbMap: Map<string, BookmarkTombstone> = new Map<string, BookmarkTombstone>();
  const combinedTb: BookmarkTombstone[] = localTombstones.concat(remoteTombstones);
  for (let i = 0; i < combinedTb.length; i++) {
    const raw: BookmarkTombstone = combinedTb[i];
    const deletedAt: number = normalizeTimestampMs(raw.deletedAt, nowMs);
    if (deletedAt < cutoff) {
      continue;
    }
    const key: string = raw.isFolder
      ? `f:${raw.id}`
      : (raw.url.length > 0 ? `u:${normalizeComparableUrl(raw.url)}` : `b:${raw.id}`);
    const prev: BookmarkTombstone | undefined = tbMap.get(key);
    if (prev === undefined || deletedAt > prev.deletedAt) {
      tbMap.set(key, {
        id: raw.id,
        url: raw.url,
        isFolder: raw.isFolder,
        deletedAt: deletedAt
      });
    }
  }

  const deletedFolderIds: Map<string, number> = new Map<string, number>();
  const deletedUrls: Map<string, number> = new Map<string, number>();
  const deletedIds: Map<string, number> = new Map<string, number>();
  tbMap.forEach((tb: BookmarkTombstone): void => {
    if (tb.isFolder) {
      const prev: number = deletedFolderIds.get(tb.id) ?? 0;
      deletedFolderIds.set(tb.id, Math.max(prev, tb.deletedAt));
    } else {
      const prevId: number = deletedIds.get(tb.id) ?? 0;
      deletedIds.set(tb.id, Math.max(prevId, tb.deletedAt));
      if (tb.url.length > 0) {
        const norm: string = normalizeComparableUrl(tb.url);
        const prevUrl: number = deletedUrls.get(norm) ?? 0;
        deletedUrls.set(norm, Math.max(prevUrl, tb.deletedAt));
      }
    }
  });

  const folderMap: Map<string, BookmarkFolder> = new Map<string, BookmarkFolder>();
  const allFolders: BookmarkFolder[] = localFolders.concat(remoteFolders);
  for (let i = 0; i < allFolders.length; i++) {
    const folder: BookmarkFolder = cloneBookmarkFolder(allFolders[i]);
    folder.createdAt = normalizeTimestampMs(folder.createdAt, nowMs);
    folder.updatedAt = normalizeTimestampMs(folder.updatedAt, folder.createdAt);
    const delAt: number | undefined = deletedFolderIds.get(folder.id);
    if (delAt !== undefined && delAt >= folder.updatedAt) {
      continue;
    }
    const existing: BookmarkFolder | undefined = folderMap.get(folder.id);
    if (existing === undefined || folder.updatedAt > existing.updatedAt) {
      folderMap.set(folder.id, folder);
    }
  }

  const mergedFolders: BookmarkFolder[] = [];
  folderMap.forEach((f: BookmarkFolder): void => {
    mergedFolders.push(f);
  });
  mergedFolders.sort((a: BookmarkFolder, b: BookmarkFolder): number => {
    if (a.sortOrder !== b.sortOrder) {
      return a.sortOrder - b.sortOrder;
    }
    return a.createdAt - b.createdAt;
  });

  const validFolderIds: Set<string> = new Set<string>(
    mergedFolders.map((f: BookmarkFolder): string => f.id)
  );

  const itemMap: Map<string, SavedItem> = new Map<string, SavedItem>();
  const allItems: SavedItem[] = localItems.concat(remoteItems);
  for (let i = 0; i < allItems.length; i++) {
    const item: SavedItem = cloneSavedItem(allItems[i]);
    item.createdAt = normalizeTimestampMs(item.createdAt, nowMs);
    item.updatedAt = normalizeTimestampMs(item.updatedAt, item.createdAt);
    const norm: string = normalizeComparableUrl(item.url);
    if (norm.length === 0) {
      continue;
    }
    const delUrl: number | undefined = deletedUrls.get(norm);
    if (delUrl !== undefined && delUrl >= item.updatedAt) {
      continue;
    }
    const delId: number | undefined = deletedIds.get(item.id);
    if (delId !== undefined && delId >= item.updatedAt) {
      continue;
    }
    if (item.folderId !== undefined && item.folderId.length > 0 && !validFolderIds.has(item.folderId)) {
      item.folderId = undefined;
      item.isPinnedToStartPage = true;
    }
    const existing: SavedItem | undefined = itemMap.get(norm);
    if (existing === undefined || item.updatedAt > existing.updatedAt) {
      itemMap.set(norm, item);
    }
  }

  const mergedItems: SavedItem[] = [];
  itemMap.forEach((item: SavedItem): void => {
    mergedItems.push(item);
  });
  mergedItems.sort((a: SavedItem, b: SavedItem): number => b.updatedAt - a.updatedAt);

  const activeTombstones: BookmarkTombstone[] = [];
  tbMap.forEach((tb: BookmarkTombstone): void => {
    if (tb.isFolder) {
      const folder: BookmarkFolder | undefined = folderMap.get(tb.id);
      if (folder === undefined || folder.updatedAt <= tb.deletedAt) {
        activeTombstones.push(tb);
      }
      return;
    }
    const byUrl: SavedItem | undefined = tb.url.length > 0
      ? itemMap.get(normalizeComparableUrl(tb.url))
      : undefined;
    if (byUrl !== undefined && byUrl.updatedAt > tb.deletedAt) {
      return;
    }
    activeTombstones.push(tb);
  });

  return {
    folders: mergedFolders,
    items: mergedItems,
    tombstones: activeTombstones
  };
}

export function mergeSiteControls(localControls: SiteControl[], remoteControls: SiteControl[]): SiteControl[] {
  const map: Map<string, SiteControl> = new Map<string, SiteControl>();
  for (let i = 0; i < localControls.length; i++) {
    const c: SiteControl = cloneSiteControl(localControls[i]);
    c.host = c.host.toLowerCase();
    if (c.host.length > 0) {
      map.set(c.host, c);
    }
  }
  for (let i = 0; i < remoteControls.length; i++) {
    const c: SiteControl = cloneSiteControl(remoteControls[i]);
    c.host = c.host.toLowerCase();
    if (c.host.length === 0) {
      continue;
    }
    if (!map.has(c.host)) {
      map.set(c.host, c);
    } else {
      map.set(c.host, c);
    }
  }
  const output: SiteControl[] = [];
  map.forEach((c: SiteControl): void => {
    output.push(c);
  });
  return output;
}

export function sanitizeDeviceTabs(tabs: BrowserTab[], maxCount: number = 50): RemoteDeviceTabEntry[] {
  const clean: RemoteDeviceTabEntry[] = [];
  const seen: Set<string> = new Set<string>();
  for (let i = 0; i < tabs.length; i++) {
    const tab: BrowserTab = tabs[i];
    if (tab.isPrivate) {
      continue;
    }
    const url: string = tab.url.trim();
    if (isInternalOrBlankUrl(url)) {
      continue;
    }
    const norm: string = normalizeComparableUrl(url);
    if (seen.has(norm)) {
      continue;
    }
    seen.add(norm);
    clean.push({
      id: tab.id,
      title: tab.title.trim().length > 0 ? tab.title.trim() : url,
      url: url,
      lastVisitedAt: normalizeTimestampMs(tab.lastVisitedAt, Date.now())
    });
    if (clean.length >= maxCount) {
      break;
    }
  }
  return clean;
}

export interface SyncArticleMetaBundle {
  article: SavedArticle;
  highlights: ArticleHighlight[];
  notes: ArticleNote[];
}

export function mergeArticleHighlights(
  localList: ArticleHighlight[],
  remoteList: ArticleHighlight[]
): ArticleHighlight[] {
  const map: Map<string, ArticleHighlight> = new Map<string, ArticleHighlight>();
  const combined: ArticleHighlight[] = localList.concat(remoteList);
  for (let i = 0; i < combined.length; i++) {
    const item: ArticleHighlight = cloneArticleHighlight(combined[i]);
    if (!map.has(item.id)) {
      map.set(item.id, item);
    }
  }
  const output: ArticleHighlight[] = [];
  map.forEach((h: ArticleHighlight): void => {
    output.push(h);
  });
  output.sort((a: ArticleHighlight, b: ArticleHighlight): number => a.createdAt - b.createdAt);
  return output;
}

export function mergeArticleNotes(localList: ArticleNote[], remoteList: ArticleNote[]): ArticleNote[] {
  const map: Map<string, ArticleNote> = new Map<string, ArticleNote>();
  const combined: ArticleNote[] = localList.concat(remoteList);
  for (let i = 0; i < combined.length; i++) {
    const note: ArticleNote = cloneArticleNote(combined[i]);
    const prev: ArticleNote | undefined = map.get(note.id);
    if (prev === undefined || note.updatedAt > prev.updatedAt) {
      map.set(note.id, note);
    }
  }
  const output: ArticleNote[] = [];
  map.forEach((n: ArticleNote): void => {
    output.push(n);
  });
  output.sort((a: ArticleNote, b: ArticleNote): number => a.createdAt - b.createdAt);
  return output;
}

export function mergeArticlesMeta(
  localArticles: SavedArticle[],
  remoteArticles: SavedArticle[],
  tombstones: ArticleTombstone[],
  nowMs: number = Date.now()
): ArticleMetaMergeOutput {
  const cutoff: number = nowMs - TOMBSTONE_RETENTION_MS;
  const activeTombstones: ArticleTombstone[] = tombstones.filter((tb: ArticleTombstone): boolean =>
    normalizeTimestampMs(tb.deletedAt, nowMs) >= cutoff);
  const deletedIds: Set<string> = new Set<string>(
    activeTombstones.map((tb: ArticleTombstone): string => tb.id)
  );
  const map: Map<string, SavedArticle> = new Map<string, SavedArticle>();
  const combined: SavedArticle[] = localArticles.concat(remoteArticles);
  for (let i = 0; i < combined.length; i++) {
    const item: SavedArticle = cloneSavedArticle(combined[i]);
    if (deletedIds.has(item.id)) {
      continue;
    }
    const key: string = normalizeComparableUrl(item.canonicalUrl.length > 0 ? item.canonicalUrl : item.sourceUrl);
    if (key.length === 0) {
      continue;
    }
    item.createdAt = normalizeTimestampMs(item.createdAt, nowMs);
    item.updatedAt = normalizeTimestampMs(item.updatedAt, item.createdAt);
    const existing: SavedArticle | undefined = map.get(key);
    if (existing === undefined) {
      map.set(key, item);
    } else if (item.updatedAt > existing.updatedAt) {
      const merged: SavedArticle = cloneSavedArticle(item);
      merged.readingPosition = Math.max(item.readingPosition, existing.readingPosition);
      map.set(key, merged);
    } else {
      existing.readingPosition = Math.max(existing.readingPosition, item.readingPosition);
      map.set(key, existing);
    }
  }
  const mergedList: SavedArticle[] = [];
  map.forEach((a: SavedArticle): void => {
    mergedList.push(a);
  });
  mergedList.sort((a: SavedArticle, b: SavedArticle): number => b.updatedAt - a.updatedAt);
  return {
    articles: mergedList,
    tombstones: activeTombstones
  };
}
