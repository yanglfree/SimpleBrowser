export const TOMBSTONE_RETENTION_MS = 60 * 24 * 60 * 60 * 1000;

export const MAINLAND_TIMEZONES = new Set([
  'Asia/Shanghai',
  'Asia/Chongqing',
  'Asia/Harbin',
  'Asia/Urumqi'
]);

export const CROSS_PLATFORM_SETTINGS_KEYS = Object.freeze([
  'blockAds',
  'blockTrackers',
  'ruleStrength',
  'searchEngine',
  'customSearchTemplate',
  'searchSuggestionsEnabled',
  'appearance',
  'webDarkMode',
  'webDarkModeExcludedHosts',
  'minimumFontSize',
  'readerFontSize',
  'readerLineHeight',
  'readerPaper',
  'updatedAt'
]);

const INTERNAL_OR_BLANK_URLS = new Set([
  '',
  'about:blank',
  'browser://home',
  'zhuo://home'
]);

/**
 * Normalizes legacy second-precision timestamps and millisecond-precision timestamps
 * onto canonical UTC milliseconds.
 */
export function normalizeTimestampMs(raw, fallbackMs = 0) {
  if (typeof raw !== 'number' || !Number.isFinite(raw) || raw <= 0) {
    return fallbackMs;
  }
  if (raw < 10_000_000_000) {
    return Math.round(raw * 1000);
  }
  return Math.round(raw);
}

/**
 * Determines whether the effective region represents Mainland China.
 * Explicit ISO 3166-1 alpha-2 codes like HK, MO, TW, US, SG, JP return false.
 * Only falls back to Mainland timezone detection when regionCode is empty.
 */
export function isMainlandChinaRegion(regionCode = '', timezone = '') {
  const normalizedRegion = String(regionCode ?? '').trim().toUpperCase();
  if (/^[A-Z]{2}$/.test(normalizedRegion)) {
    return normalizedRegion === 'CN';
  }
  const normalizedTimezone = String(timezone ?? '').trim();
  return MAINLAND_TIMEZONES.has(normalizedTimezone);
}

/**
 * Google Sign-In is exposed exclusively outside Mainland China.
 */
export function isGoogleSignInAvailable({ regionCode = '', timezone = '' } = {}) {
  return !isMainlandChinaRegion(regionCode, timezone);
}

/**
 * Resolves the auth providers offered on a specific platform and region.
 */
export function resolveAvailableAuthProviders({ platform, regionCode = '', timezone = '' }) {
  const providers = ['email_otp', 'email_password'];
  if (platform === 'ios' || platform === 'macos') {
    providers.push('apple');
  } else if (platform === 'harmony') {
    providers.push('huawei');
  }
  if (isGoogleSignInAvailable({ regionCode, timezone })) {
    providers.push('google');
  }
  return providers;
}

export function normalizeComparableUrl(url) {
  let trimmed = String(url ?? '').trim();
  while (trimmed.endsWith('/') && trimmed.length > 1) {
    trimmed = trimmed.slice(0, -1);
  }
  return trimmed.toLowerCase();
}

export function isInternalOrBlankUrl(url) {
  const normalized = normalizeComparableUrl(url);
  if (INTERNAL_OR_BLANK_URLS.has(normalized)) {
    return true;
  }
  return (
    normalized.startsWith('javascript:') ||
    normalized.startsWith('data:') ||
    normalized.startsWith('browser://') ||
    normalized.startsWith('zhuo://')
  );
}

function cleanTombstones(tombstones, nowMs, extractTs) {
  const cutoff = nowMs - TOMBSTONE_RETENTION_MS;
  return (Array.isArray(tombstones) ? tombstones : []).filter((tb) => extractTs(tb) >= cutoff);
}

function normalizeFolder(folder, nowMs) {
  const createdAt = normalizeTimestampMs(folder.createdAt, nowMs);
  const updatedAt = normalizeTimestampMs(folder.updatedAt, createdAt);
  return {
    id: String(folder.id),
    name: String(folder.name ?? '').trim() || '文件夹',
    iconName: String(folder.iconName ?? 'folder.fill'),
    createdAt,
    updatedAt,
    sortOrder: Number.isFinite(folder.sortOrder) ? Math.trunc(folder.sortOrder) : 0,
    isPinnedToStartPage: folder.isPinnedToStartPage !== false
  };
}

function normalizeBookmarkItem(item, nowMs) {
  const createdAt = normalizeTimestampMs(item.createdAt, nowMs);
  const updatedAt = normalizeTimestampMs(item.updatedAt, createdAt);
  const rawTitle = String(item.title ?? '').trim();
  const url = String(item.url ?? '').trim();
  const title = rawTitle || url;
  const folderId = item.folderId ?? item.folderID ?? null;
  const tags = Array.isArray(item.tags)
    ? Array.from(new Set(item.tags.map((t) => String(t).trim()).filter(Boolean)))
    : [];
  const shortTitle = typeof item.shortTitle === 'string' && item.shortTitle.trim().length > 0
    ? item.shortTitle.trim()
    : undefined;
  const fallbackLetter = (title || url).slice(0, 1).toUpperCase() || 'B';
  return {
    id: String(item.id),
    title,
    ...(shortTitle ? { shortTitle } : {}),
    url,
    folderId: folderId ? String(folderId) : null,
    createdAt,
    updatedAt,
    isRead: item.isRead !== undefined ? Boolean(item.isRead) : true,
    tags,
    isPinnedToStartPage: Boolean(item.isPinnedToStartPage ?? (folderId == null)),
    iconName: String(item.iconName ?? ''),
    iconLetter: String(item.iconLetter ?? '').trim() || fallbackLetter,
    colorHex: String(item.colorHex ?? ''),
    sortOrder: Number.isFinite(item.sortOrder) ? Math.trunc(item.sortOrder) : 0
  };
}

/**
 * Deterministic superset merge for folders, bookmarks/read-later items, and 60-day tombstones.
 */
export function mergeBookmarkSync(localPayload = {}, remotePayload = {}, nowMs = Date.now()) {
  const localFolders = (localPayload.folders ?? []).map((f) => normalizeFolder(f, nowMs));
  const remoteFolders = (remotePayload.folders ?? []).map((f) => normalizeFolder(f, nowMs));
  const localItems = (localPayload.items ?? localPayload.entries ?? []).map((i) => normalizeBookmarkItem(i, nowMs));
  const remoteItems = (remotePayload.items ?? remotePayload.entries ?? []).map((i) => normalizeBookmarkItem(i, nowMs));

  const rawTombstones = [
    ...(localPayload.tombstones ?? []),
    ...(remotePayload.tombstones ?? [])
  ].map((tb) => ({
    id: String(tb.id),
    ...(tb.url ? { url: String(tb.url) } : {}),
    isFolder: Boolean(tb.isFolder),
    deletedAt: normalizeTimestampMs(tb.deletedAt, nowMs)
  }));

  const combinedTombstones = new Map();
  for (const tb of cleanTombstones(rawTombstones, nowMs, (t) => t.deletedAt)) {
    const key = tb.isFolder
      ? `f:${tb.id}`
      : tb.url
        ? `u:${normalizeComparableUrl(tb.url)}`
        : `b:${tb.id}`;
    const existing = combinedTombstones.get(key);
    if (!existing || tb.deletedAt > existing.deletedAt) {
      combinedTombstones.set(key, tb);
    }
  }

  let activeTombstones = Array.from(combinedTombstones.values());
  const deletedFolderIds = new Map();
  const deletedItemUrls = new Map();
  const deletedItemIds = new Map();

  for (const tb of activeTombstones) {
    if (tb.isFolder) {
      deletedFolderIds.set(tb.id, Math.max(deletedFolderIds.get(tb.id) ?? 0, tb.deletedAt));
    } else {
      deletedItemIds.set(tb.id, Math.max(deletedItemIds.get(tb.id) ?? 0, tb.deletedAt));
      if (tb.url) {
        const norm = normalizeComparableUrl(tb.url);
        deletedItemUrls.set(norm, Math.max(deletedItemUrls.get(norm) ?? 0, tb.deletedAt));
      }
    }
  }

  const mergedFoldersMap = new Map();
  for (const folder of [...localFolders, ...remoteFolders]) {
    const delAt = deletedFolderIds.get(folder.id);
    if (delAt !== undefined && delAt >= folder.updatedAt) {
      continue;
    }
    const existing = mergedFoldersMap.get(folder.id);
    if (!existing || folder.updatedAt > existing.updatedAt) {
      mergedFoldersMap.set(folder.id, folder);
    }
  }

  const sortedFolders = Array.from(mergedFoldersMap.values()).sort((a, b) => {
    if (a.sortOrder !== b.sortOrder) {
      return a.sortOrder - b.sortOrder;
    }
    return a.createdAt - b.createdAt;
  });
  const validFolderIds = new Set(sortedFolders.map((f) => f.id));

  const isDeletedItem = (item) => {
    const norm = normalizeComparableUrl(item.url);
    const delByUrl = deletedItemUrls.get(norm);
    if (delByUrl !== undefined && delByUrl >= item.updatedAt) {
      return true;
    }
    const delById = deletedItemIds.get(item.id);
    return delById !== undefined && delById >= item.updatedAt;
  };

  const mergedItemsMap = new Map();
  for (const rawItem of [...localItems, ...remoteItems]) {
    const norm = normalizeComparableUrl(rawItem.url);
    if (!norm || isDeletedItem(rawItem)) {
      continue;
    }
    const candidate = { ...rawItem };
    if (candidate.folderId && !validFolderIds.has(candidate.folderId)) {
      candidate.folderId = null;
      candidate.isPinnedToStartPage = true;
    }
    const existing = mergedItemsMap.get(norm);
    if (!existing || candidate.updatedAt > existing.updatedAt) {
      mergedItemsMap.set(norm, candidate);
    }
  }

  const mergedItems = Array.from(mergedItemsMap.values()).sort((a, b) => {
    if (a.sortOrder !== b.sortOrder) {
      return a.sortOrder - b.sortOrder;
    }
    return b.updatedAt - a.updatedAt;
  });

  // Prune tombstones superseded by newer re-creations
  const liveFolderById = new Map(sortedFolders.map((f) => [f.id, f]));
  const liveItemById = new Map(mergedItems.map((i) => [i.id, i]));
  const liveItemByUrl = new Map(mergedItems.map((i) => [normalizeComparableUrl(i.url), i]));

  activeTombstones = activeTombstones.filter((tb) => {
    if (tb.isFolder) {
      const folder = liveFolderById.get(tb.id);
      return !(folder && folder.updatedAt > tb.deletedAt);
    }
    const byUrl = tb.url ? liveItemByUrl.get(normalizeComparableUrl(tb.url)) : undefined;
    if (byUrl && byUrl.updatedAt > tb.deletedAt) {
      return false;
    }
    const byId = liveItemById.get(tb.id);
    return !(byId && byId.updatedAt > tb.deletedAt);
  });

  return {
    version: 3,
    folders: sortedFolders,
    items: mergedItems,
    tombstones: activeTombstones,
    updatedAt: nowMs
  };
}

/**
 * Extracts only cross-platform user-intent settings, dropping device-specific quotas.
 */
export function projectCrossPlatformSettings(settings = {}, updatedAtMs = 0) {
  const projected = {};
  for (const key of CROSS_PLATFORM_SETTINGS_KEYS) {
    if (key === 'updatedAt') {
      continue;
    }
    if (settings[key] !== undefined) {
      projected[key] = Array.isArray(settings[key]) ? [...settings[key]] : settings[key];
    }
  }
  projected.updatedAt = normalizeTimestampMs(settings.updatedAt, updatedAtMs);
  return projected;
}

export function mergeCrossPlatformSettings(local = {}, remote = {}) {
  const localNorm = projectCrossPlatformSettings(local, 0);
  const remoteNorm = projectCrossPlatformSettings(remote, 0);
  if (remoteNorm.updatedAt > localNorm.updatedAt) {
    return { ...localNorm, ...remoteNorm, updatedAt: remoteNorm.updatedAt };
  }
  return localNorm;
}

export function mergeSiteControls(localPayload = {}, remotePayload = {}, nowMs = Date.now()) {
  const rawTombstones = [
    ...(localPayload.tombstones ?? []),
    ...(remotePayload.tombstones ?? [])
  ].map((tb) => ({
    host: String(tb.host ?? '').trim().toLowerCase(),
    deletedAt: normalizeTimestampMs(tb.deletedAt, nowMs)
  })).filter((tb) => tb.host.length > 0);

  const tombstonesMap = new Map();
  for (const tb of cleanTombstones(rawTombstones, nowMs, (t) => t.deletedAt)) {
    const existing = tombstonesMap.get(tb.host);
    if (!existing || tb.deletedAt > existing.deletedAt) {
      tombstonesMap.set(tb.host, tb);
    }
  }

  const controlsMap = new Map();
  for (const rawControl of [...(localPayload.controls ?? []), ...(remotePayload.controls ?? [])]) {
    const host = String(rawControl.host ?? '').trim().toLowerCase();
    if (!host) {
      continue;
    }
    const normalized = {
      host,
      networkBlocking: rawControl.networkBlocking ?? 0,
      trackerBlocking: rawControl.trackerBlocking ?? 0,
      cosmeticCleanup: rawControl.cosmeticCleanup ?? 0,
      autoReader: rawControl.autoReader ?? 0,
      darkMode: rawControl.darkMode ?? 0,
      desktopUserAgent: rawControl.desktopUserAgent ?? 0,
      updatedAt: normalizeTimestampMs(rawControl.updatedAt, nowMs)
    };
    const deleted = tombstonesMap.get(host);
    if (deleted && deleted.deletedAt >= normalized.updatedAt) {
      continue;
    }
    const existing = controlsMap.get(host);
    if (!existing || normalized.updatedAt > existing.updatedAt) {
      controlsMap.set(host, normalized);
    }
  }

  const controls = Array.from(controlsMap.values()).sort((a, b) => a.host.localeCompare(b.host));
  const liveByHost = new Map(controls.map((c) => [c.host, c]));
  const tombstones = Array.from(tombstonesMap.values()).filter((tb) => {
    const live = liveByHost.get(tb.host);
    return !(live && live.updatedAt > tb.deletedAt);
  });

  return {
    controls,
    tombstones,
    updatedAt: nowMs
  };
}

/**
 * Strips private tabs and internal/blank URLs before uploading a device tab snapshot.
 */
export function sanitizeDeviceTabsSnapshot({
  deviceId,
  deviceName,
  platform,
  tabs = [],
  nowMs = Date.now(),
  maxTabs = 50
}) {
  const sanitized = [];
  const seenUrls = new Set();
  for (const tab of tabs) {
    if (!tab || tab.isPrivate) {
      continue;
    }
    const url = String(tab.url ?? '').trim();
    if (isInternalOrBlankUrl(url)) {
      continue;
    }
    const norm = normalizeComparableUrl(url);
    if (seenUrls.has(norm)) {
      continue;
    }
    seenUrls.add(norm);
    sanitized.push({
      id: String(tab.id),
      title: String(tab.title ?? '').trim() || url,
      url,
      lastVisitedAt: normalizeTimestampMs(tab.lastVisitedAt, nowMs)
    });
    if (sanitized.length >= maxTabs) {
      break;
    }
  }
  return {
    deviceId: String(deviceId),
    deviceName: String(deviceName ?? '').trim() || '我的设备',
    platform,
    updatedAt: nowMs,
    tabs: sanitized
  };
}

function mergeByIdLww(localList = [], remoteList = [], nowMs) {
  const map = new Map();
  for (const item of [...localList, ...remoteList]) {
    if (!item || !item.id) {
      continue;
    }
    const createdAt = normalizeTimestampMs(item.createdAt, nowMs);
    const updatedAt = normalizeTimestampMs(item.updatedAt, createdAt);
    const normalized = { ...item, id: String(item.id), createdAt, updatedAt };
    const existing = map.get(normalized.id);
    if (!existing || normalized.updatedAt > existing.updatedAt) {
      map.set(normalized.id, normalized);
    }
  }
  return Array.from(map.values()).sort((a, b) => a.createdAt - b.createdAt);
}

export function mergeArticlesMeta(localPayload = {}, remotePayload = {}, nowMs = Date.now()) {
  const rawTombstones = [
    ...(localPayload.tombstones ?? []),
    ...(remotePayload.tombstones ?? [])
  ].map((tb) => ({
    id: String(tb.id),
    ...(tb.canonicalUrl ? { canonicalUrl: String(tb.canonicalUrl) } : {}),
    deletedAt: normalizeTimestampMs(tb.deletedAt, nowMs)
  }));

  const tombstonesMap = new Map();
  for (const tb of cleanTombstones(rawTombstones, nowMs, (t) => t.deletedAt)) {
    const key = tb.canonicalUrl ? `u:${normalizeComparableUrl(tb.canonicalUrl)}` : `i:${tb.id}`;
    const existing = tombstonesMap.get(key);
    if (!existing || tb.deletedAt > existing.deletedAt) {
      tombstonesMap.set(key, tb);
    }
  }

  const deletedIds = new Map();
  const deletedUrls = new Map();
  for (const tb of tombstonesMap.values()) {
    deletedIds.set(tb.id, Math.max(deletedIds.get(tb.id) ?? 0, tb.deletedAt));
    if (tb.canonicalUrl) {
      const norm = normalizeComparableUrl(tb.canonicalUrl);
      deletedUrls.set(norm, Math.max(deletedUrls.get(norm) ?? 0, tb.deletedAt));
    }
  }

  const articlesMap = new Map();
  for (const raw of [...(localPayload.articles ?? []), ...(remotePayload.articles ?? [])]) {
    if (!raw || !raw.id) {
      continue;
    }
    const canonicalUrl = String(raw.canonicalUrl || raw.sourceUrl || '').trim();
    if (!canonicalUrl) {
      continue;
    }
    const normUrl = normalizeComparableUrl(canonicalUrl);
    const createdAt = normalizeTimestampMs(raw.createdAt, nowMs);
    const updatedAt = normalizeTimestampMs(raw.updatedAt, createdAt);
    const delAt = Math.max(deletedIds.get(String(raw.id)) ?? 0, deletedUrls.get(normUrl) ?? 0);
    if (delAt >= updatedAt) {
      continue;
    }

    const candidate = {
      id: String(raw.id),
      sourceUrl: String(raw.sourceUrl || canonicalUrl),
      canonicalUrl,
      title: String(raw.title ?? ''),
      author: String(raw.author ?? ''),
      excerpt: String(raw.excerpt ?? ''),
      createdAt,
      updatedAt,
      readingPosition: Number.isFinite(raw.readingPosition) ? Math.max(0, raw.readingPosition) : 0,
      tags: Array.isArray(raw.tags) ? Array.from(new Set(raw.tags.map(String))) : [],
      topics: Array.isArray(raw.topics) ? Array.from(new Set(raw.topics.map(String))) : [],
      isArchived: Boolean(raw.isArchived),
      quality: String(raw.quality ?? 'partial'),
      ...(raw.bundleSha256 ? { bundleSha256: String(raw.bundleSha256) } : {}),
      highlights: Array.isArray(raw.highlights) ? raw.highlights : [],
      notes: Array.isArray(raw.notes) ? raw.notes : []
    };

    const existing = articlesMap.get(normUrl);
    if (!existing) {
      articlesMap.set(normUrl, candidate);
    } else {
      const winner = candidate.updatedAt > existing.updatedAt ? candidate : existing;
      const loser = winner === candidate ? existing : candidate;
      articlesMap.set(normUrl, {
        ...winner,
        readingPosition: winner.readingPosition > 0 || winner.updatedAt > loser.updatedAt
          ? winner.readingPosition
          : loser.readingPosition,
        highlights: mergeByIdLww(existing.highlights, candidate.highlights, nowMs),
        notes: mergeByIdLww(existing.notes, candidate.notes, nowMs)
      });
    }
  }

  const articles = Array.from(articlesMap.values()).sort((a, b) => b.updatedAt - a.updatedAt);
  const liveById = new Map(articles.map((a) => [a.id, a]));
  const liveByUrl = new Map(articles.map((a) => [normalizeComparableUrl(a.canonicalUrl), a]));
  const tombstones = Array.from(tombstonesMap.values()).filter((tb) => {
    const byId = liveById.get(tb.id);
    if (byId && byId.updatedAt > tb.deletedAt) {
      return false;
    }
    const byUrl = tb.canonicalUrl ? liveByUrl.get(normalizeComparableUrl(tb.canonicalUrl)) : undefined;
    return !(byUrl && byUrl.updatedAt > tb.deletedAt);
  });

  return {
    articles,
    tombstones,
    updatedAt: nowMs
  };
}
