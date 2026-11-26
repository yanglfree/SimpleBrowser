import test from 'node:test';
import assert from 'node:assert/strict';
import {
  isMainlandChinaRegion,
  isGoogleSignInAvailable,
  resolveAvailableAuthProviders,
  normalizeTimestampMs,
  mergeBookmarkSync,
  projectCrossPlatformSettings,
  mergeCrossPlatformSettings,
  mergeSiteControls,
  sanitizeDeviceTabsSnapshot,
  mergeArticlesMeta,
  TOMBSTONE_RETENTION_MS
} from '../src/sync-policy.mjs';

test('region gating hides Google Sign-In strictly in Mainland China', () => {
  assert.equal(isMainlandChinaRegion('CN', 'Asia/Shanghai'), true);
  assert.equal(isGoogleSignInAvailable({ regionCode: 'cn', timezone: 'America/New_York' }), false);

  for (const region of ['HK', 'MO', 'TW', 'US', 'SG', 'JP', 'GB']) {
    assert.equal(isMainlandChinaRegion(region, 'Asia/Shanghai'), false, `region=${region}`);
    assert.equal(isGoogleSignInAvailable({ regionCode: region, timezone: 'Asia/Shanghai' }), true);
  }

  assert.equal(isGoogleSignInAvailable({ regionCode: '', timezone: 'Asia/Shanghai' }), false);
  assert.equal(isGoogleSignInAvailable({ regionCode: '', timezone: 'America/Los_Angeles' }), true);
});

test('resolveAvailableAuthProviders matches platform and region matrix', () => {
  assert.deepEqual(
    resolveAvailableAuthProviders({ platform: 'ios', regionCode: 'CN' }),
    ['email_otp', 'email_password', 'apple']
  );
  assert.deepEqual(
    resolveAvailableAuthProviders({ platform: 'macos', regionCode: 'US' }),
    ['email_otp', 'email_password', 'apple', 'google']
  );
  assert.deepEqual(
    resolveAvailableAuthProviders({ platform: 'harmony', regionCode: 'CN' }),
    ['email_otp', 'email_password', 'huawei']
  );
  assert.deepEqual(
    resolveAvailableAuthProviders({ platform: 'harmony', regionCode: 'HK' }),
    ['email_otp', 'email_password', 'huawei', 'google']
  );
  assert.deepEqual(
    resolveAvailableAuthProviders({ platform: 'android', regionCode: 'CN' }),
    ['email_otp', 'email_password']
  );
  assert.deepEqual(
    resolveAvailableAuthProviders({ platform: 'android', regionCode: 'SG' }),
    ['email_otp', 'email_password', 'google']
  );
});

test('normalizeTimestampMs converts legacy seconds to UTC milliseconds', () => {
  assert.equal(normalizeTimestampMs(1_760_000_000), 1_760_000_000_000);
  assert.equal(normalizeTimestampMs(1_760_000_000_123), 1_760_000_000_123);
  assert.equal(normalizeTimestampMs(0, 999), 999);
});

test('mergeBookmarkSync preserves superset fields and enforces tombstones without resurrection', () => {
  const now = 1_765_000_000_000;
  const local = {
    folders: [
      { id: 'f1', name: 'Work', createdAt: 1_760_000_000, updatedAt: 1_760_000_000, sortOrder: 0 },
      { id: 'f-deleted', name: 'Old', createdAt: 1_760_000_000, updatedAt: 1_760_000_000, sortOrder: 1 }
    ],
    items: [
      {
        id: 'b1',
        title: 'Unread Article',
        url: 'https://example.com/a/',
        folderId: null,
        isRead: false,
        tags: ['swift', 'reading'],
        createdAt: 1_760_000_000_000,
        updatedAt: 1_760_000_100_000
      },
      {
        id: 'b2',
        title: 'Deleted Remote',
        url: 'https://example.com/del',
        createdAt: 1_760_000_000_000,
        updatedAt: 1_760_000_000_000
      }
    ],
    tombstones: [
      { id: 'f-deleted', isFolder: true, deletedAt: 1_760_000_050_000 }
    ]
  };

  const remote = {
    folders: [
      { id: 'f1', name: 'Work & Tech', createdAt: 1_760_000_000_000, updatedAt: 1_760_000_200_000, sortOrder: 0 }
    ],
    items: [
      {
        id: 'b1',
        title: 'Unread Article',
        url: 'https://example.com/a',
        folderId: 'f1',
        isRead: false,
        tags: ['swift', 'harmony'],
        createdAt: 1_760_000_000,
        updatedAt: 1_760_000_300 // seconds -> newer than local ms
      }
    ],
    tombstones: [
      { id: 'b2', url: 'https://example.com/del', isFolder: false, deletedAt: 1_760_000_100_000 },
      { id: 'stale', url: 'https://stale.test', isFolder: false, deletedAt: now - TOMBSTONE_RETENTION_MS - 1000 }
    ]
  };

  const merged = mergeBookmarkSync(local, remote, now);
  assert.equal(merged.folders.length, 1);
  assert.equal(merged.folders[0].name, 'Work & Tech');
  assert.equal(merged.items.length, 1);
  assert.equal(merged.items[0].folderId, 'f1');
  assert.equal(merged.items[0].isRead, false);
  assert.deepEqual(merged.items[0].tags, ['swift', 'harmony']);
  assert.equal(merged.tombstones.some((t) => t.id === 'stale'), false);
  assert.equal(merged.tombstones.some((t) => t.id === 'b2'), true);
});

test('projectCrossPlatformSettings strips device-local budget fields', () => {
  const projected = projectCrossPlatformSettings({
    blockAds: true,
    liveWebViewLimit: 4,
    liveWebViewBudget: 2,
    autoHideToolbarEnabled: true,
    searchEngine: 2,
    updatedAt: 1_760_000_000
  });
  assert.equal(projected.liveWebViewLimit, undefined);
  assert.equal(projected.liveWebViewBudget, undefined);
  assert.equal(projected.autoHideToolbarEnabled, undefined);
  assert.equal(projected.searchEngine, 2);
  assert.equal(projected.updatedAt, 1_760_000_000_000);

  const merged = mergeCrossPlatformSettings(projected, { searchEngine: 0, updatedAt: 1_760_000_100_000 });
  assert.equal(merged.searchEngine, 0);
});

test('mergeSiteControls merges 6-rule host overrides and respects tombstones', () => {
  const now = 1_765_000_000_000;
  const merged = mergeSiteControls(
    {
      controls: [{ host: 'Example.com', networkBlocking: 2, darkMode: 1, updatedAt: 1_760_000_000_000 }],
      tombstones: [{ host: 'removed.com', deletedAt: 1_760_000_100_000 }]
    },
    {
      controls: [
        { host: 'example.com', networkBlocking: 1, darkMode: 2, desktopUserAgent: 2, updatedAt: 1_760_000_200_000 },
        { host: 'removed.com', networkBlocking: 2, updatedAt: 1_760_000_050_000 }
      ]
    },
    now
  );
  assert.equal(merged.controls.length, 1);
  assert.equal(merged.controls[0].host, 'example.com');
  assert.equal(merged.controls[0].desktopUserAgent, 2);
});

test('sanitizeDeviceTabsSnapshot drops private tabs and internal home URLs', () => {
  const snap = sanitizeDeviceTabsSnapshot({
    deviceId: 'mac-1',
    deviceName: 'MacBook Pro',
    platform: 'macos',
    nowMs: 1_765_000_000_000,
    tabs: [
      { id: '1', title: 'Home', url: 'zhuo://home', isPrivate: false },
      { id: '2', title: 'Home', url: 'browser://home', isPrivate: false },
      { id: '3', title: 'Secret', url: 'https://secret.example', isPrivate: true },
      { id: '4', title: 'Swift', url: 'https://swift.org', isPrivate: false, lastVisitedAt: 1_760_000_000 },
      { id: '5', title: 'Dup', url: 'https://swift.org/', isPrivate: false }
    ]
  });
  assert.equal(snap.tabs.length, 1);
  assert.equal(snap.tabs[0].url, 'https://swift.org');
  assert.equal(snap.tabs[0].lastVisitedAt, 1_760_000_000_000);
});

test('mergeArticlesMeta merges reading position, highlights, notes, and tombstones', () => {
  const now = 1_765_000_000_000;
  const merged = mergeArticlesMeta(
    {
      articles: [{
        id: 'art-1',
        sourceUrl: 'https://news.test/post',
        canonicalUrl: 'https://news.test/post',
        title: 'Post',
        readingPosition: 0.4,
        updatedAt: 1_760_000_100_000,
        highlights: [{ id: 'h1', quote: 'alpha', prefixContext: '', suffixContext: '', color: 'yellow', createdAt: 1000, updatedAt: 1000 }],
        notes: []
      }]
    },
    {
      articles: [{
        id: 'art-1',
        sourceUrl: 'https://news.test/post',
        canonicalUrl: 'https://news.test/post/',
        title: 'Post',
        readingPosition: 0.8,
        updatedAt: 1_760_000_200_000,
        highlights: [{ id: 'h2', quote: 'beta', prefixContext: '', suffixContext: '', color: 'green', createdAt: 2000, updatedAt: 2000 }],
        notes: [{ id: 'n1', highlightId: 'h2', content: 'Remember', createdAt: 2000, updatedAt: 2000 }]
      }]
    },
    now
  );
  assert.equal(merged.articles.length, 1);
  assert.equal(merged.articles[0].readingPosition, 0.8);
  assert.equal(merged.articles[0].highlights.length, 2);
  assert.equal(merged.articles[0].notes.length, 1);
});
