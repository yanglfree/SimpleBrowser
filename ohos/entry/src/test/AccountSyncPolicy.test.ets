import { describe, expect, it } from '@ohos/hypium';
import { AuthProviderKind, BookmarkFolder, BookmarkTombstone } from '../main/ets/models/AccountSyncModels';
import { ArticleSaveFailure, SavedArticle } from '../main/ets/models/ArticleLibraryModels';
import { BrowserTab, LoadErrorKind, SavedItem, SecurityState, emptyBlockStats } from '../main/ets/models/BrowserModels';
import { isGoogleSignInAvailable, isMainlandChinaRegion, resolveHarmonyAuthProviders } from '../main/ets/services/RegionAuthPolicy';
import {
  mergeArticlesMeta,
  mergeBookmarkSync,
  normalizeTimestampMs,
  sanitizeDeviceTabs
} from '../main/ets/services/SyncMergePolicy';

function sampleTab(id: string, url: string, isPrivate: boolean): BrowserTab {
  return {
    id: id,
    url: url,
    title: url,
    isPrivate: isPrivate,
    isLoading: false,
    progress: 0,
    isDesktop: false,
    isPinned: false,
    isReader: false,
    canGoBack: false,
    canGoForward: false,
    blocked: emptyBlockStats(),
    faviconUrl: '',
    lastVisitedAt: 1760000000,
    scrollY: 0,
    readerScrollY: 0,
    scrollSavedAt: 0,
    readerScrollSavedAt: 0,
    formDraft: '',
    loadError: LoadErrorKind.None,
    securityState: SecurityState.Secure
  };
}

export default function accountSyncPolicyTest(): void {
  describe('AccountSyncPolicyTest', () => {
    it('hides Google Sign-In strictly in Mainland China', 0, () => {
      expect(isMainlandChinaRegion('CN', 'Asia/Shanghai')).assertTrue();
      expect(isGoogleSignInAvailable('CN', 'America/New_York')).assertFalse();
      expect(isGoogleSignInAvailable('HK', 'Asia/Shanghai')).assertTrue();
      expect(isGoogleSignInAvailable('US', 'America/Los_Angeles')).assertTrue();
      expect(isGoogleSignInAvailable('', 'Asia/Shanghai')).assertFalse();

      const cnProviders: AuthProviderKind[] = resolveHarmonyAuthProviders('CN', 'Asia/Shanghai');
      expect(cnProviders.includes(AuthProviderKind.HUAWEI)).assertTrue();
      expect(cnProviders.includes(AuthProviderKind.GOOGLE)).assertFalse();

      const sgProviders: AuthProviderKind[] = resolveHarmonyAuthProviders('SG', 'Asia/Singapore');
      expect(sgProviders.includes(AuthProviderKind.HUAWEI)).assertTrue();
      expect(sgProviders.includes(AuthProviderKind.GOOGLE)).assertTrue();
    });

    it('normalizes legacy seconds to UTC milliseconds', 0, () => {
      expect(normalizeTimestampMs(1760000000, 0)).assertEqual(1760000000000);
      expect(normalizeTimestampMs(1760000000500, 0)).assertEqual(1760000000500);
    });

    it('merges superset folders, bookmarks, read-later items, and tombstones without resurrection', 0, () => {
      const now: number = 1765000000000;
      const localFolders: BookmarkFolder[] = [{
        id: 'f1',
        name: '工作',
        iconName: 'folder.fill',
        createdAt: 1760000000000,
        updatedAt: 1760000000000,
        sortOrder: 0,
        isPinnedToStartPage: true
      }];
      const localItems: SavedItem[] = [
        {
          id: 'b1',
          title: 'Local',
          url: 'https://example.com/a/',
          folderId: 'f1',
          createdAt: 1760000000000,
          updatedAt: 1760000100000,
          isRead: false,
          tags: ['ohos']
        },
        {
          id: 'b2',
          title: 'Deleted Remote',
          url: 'https://example.com/del',
          createdAt: 1760000000000,
          updatedAt: 1760000050000,
          isRead: true,
          tags: []
        }
      ];
      const remoteItems: SavedItem[] = [{
        id: 'b1',
        title: 'Remote Updated',
        url: 'https://example.com/a',
        folderId: 'f1',
        createdAt: 1760000000,
        updatedAt: 1760000200,
        isRead: false,
        tags: ['ohos', 'mac']
      }];
      const remoteTombstones: BookmarkTombstone[] = [{
        id: 'b2',
        url: 'https://example.com/del',
        isFolder: false,
        deletedAt: 1760000150000
      }];

      const merged = mergeBookmarkSync(localFolders, localItems, [], [], remoteItems, remoteTombstones, now);
      expect(merged.folders.length).assertEqual(1);
      expect(merged.items.length).assertEqual(1);
      expect(merged.items[0].title).assertEqual('Remote Updated');
      expect(merged.items[0].isRead).assertFalse();
      expect(merged.items[0].tags.length).assertEqual(2);
    });

    it('sanitizes device tabs by excluding private and home URLs', 0, () => {
      const sanitized = sanitizeDeviceTabs([
        sampleTab('1', 'browser://home', false),
        sampleTab('2', 'https://secret.test', true),
        sampleTab('3', 'https://developer.huawei.com', false)
      ]);
      expect(sanitized.length).assertEqual(1);
      expect(sanitized[0].url).assertEqual('https://developer.huawei.com');
    });

    it('merges article metadata reading position and honors tombstones', 0, () => {
      const now: number = 1765000000000;
      const localArticle: SavedArticle = {
        id: 'a1',
        sourceUrl: 'https://news.test/1',
        canonicalUrl: 'https://news.test/1',
        title: 'News',
        author: '',
        excerpt: '',
        createdAt: 1760000000000,
        updatedAt: 1760000100000,
        readingPosition: 0.25,
        tags: [],
        isArchived: false,
        failure: ArticleSaveFailure.None,
        failureMessage: ''
      };
      const remoteArticle: SavedArticle = {
        id: 'a1',
        sourceUrl: 'https://news.test/1',
        canonicalUrl: 'https://news.test/1/',
        title: 'News',
        author: '',
        excerpt: '',
        createdAt: 1760000000000,
        updatedAt: 1760000200000,
        readingPosition: 0.85,
        tags: [],
        isArchived: true,
        failure: ArticleSaveFailure.None,
        failureMessage: ''
      };
      const merged = mergeArticlesMeta([localArticle], [remoteArticle], [], now);
      expect(merged.articles.length).assertEqual(1);
      expect(merged.articles[0].readingPosition).assertEqual(0.85);
      expect(merged.articles[0].isArchived).assertTrue();
    });
  });
}
