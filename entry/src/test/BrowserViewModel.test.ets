import { describe, expect, it } from '@ohos/hypium';
import {
  BrowserTab,
  HistoryEntry,
  moveQuickSite,
  quickSiteDropTarget,
  QuickSite,
  SavedItem,
  Suggestion,
  SuggestionKind,
  UserAgentPreference
} from '../main/ets/models/BrowserModels';
import { BrowserViewModel } from '../main/ets/viewmodels/BrowserViewModel';
import { HOME_URL } from '../main/ets/constants/AppConstants';
import { clampPaneRatio } from '../main/ets/models/PaneModels';
import { BrowserFoldMetrics, hasHorizontalCrease, hasVerticalCrease } from '../main/ets/models/FoldMetrics';

export default function browserViewModelTest(): void {
  describe('BrowserViewModel recent tabs', (): void => {
    it('keeps the active tab first and sorts the remaining working set by recency', 0, (): void => {
      const viewModel: BrowserViewModel = new BrowserViewModel();
      const active: BrowserTab = viewModel.createTab('https://active.example', false);
      const older: BrowserTab = viewModel.createTab('https://older.example', false);
      const newer: BrowserTab = viewModel.createTab('https://newer.example', false);
      active.lastVisitedAt = 1;
      older.lastVisitedAt = 10;
      newer.lastVisitedAt = 20;
      viewModel.tabs = [older, active, newer];
      viewModel.activeTabId = active.id;

      const recent: BrowserTab[] = viewModel.recentTabs(3);

      expect(recent.length).assertEqual(3);
      expect(recent[0].id).assertEqual(active.id);
      expect(recent[1].id).assertEqual(newer.id);
      expect(recent[2].id).assertEqual(older.id);
    });

    it('does not mix normal and private tabs in the recent dock', 0, (): void => {
      const viewModel: BrowserViewModel = new BrowserViewModel();
      const active: BrowserTab = viewModel.createTab('https://active.example', false);
      const normal: BrowserTab = viewModel.createTab('https://normal.example', false);
      const privateTab: BrowserTab = viewModel.createTab('https://private.example', true);
      privateTab.lastVisitedAt = 30;
      viewModel.tabs = [active, privateTab, normal];
      viewModel.activeTabId = active.id;

      const recent: BrowserTab[] = viewModel.recentTabs(5);

      expect(recent.length).assertEqual(2);
      expect(recent.some((tab: BrowserTab): boolean => tab.isPrivate)).assertFalse();
    });

    it('keeps a private active tab inside its private working set', 0, (): void => {
      const viewModel: BrowserViewModel = new BrowserViewModel();
      const normal: BrowserTab = viewModel.createTab('https://normal.example', false);
      const active: BrowserTab = viewModel.createTab('https://private-active.example', true);
      const privateRecent: BrowserTab = viewModel.createTab('https://private-recent.example', true);
      viewModel.tabs = [normal, privateRecent, active];
      viewModel.activeTabId = active.id;

      const recent: BrowserTab[] = viewModel.recentTabs(5);

      expect(recent.length).assertEqual(2);
      expect(recent[0].id).assertEqual(active.id);
      expect(recent.every((tab: BrowserTab): boolean => tab.isPrivate)).assertTrue();
    });
  });

  describe('BrowserViewModel local search shortcut', (): void => {
    it('shows one typed-query search action when the shortcut setting is enabled', 0, (): void => {
      const viewModel: BrowserViewModel = new BrowserViewModel();
      viewModel.settings.searchSuggestionsEnabled = true;

      const suggestions: Suggestion[] = viewModel.getSuggestions('privacy browser');

      expect(suggestions.length).assertEqual(1);
      expect(suggestions[0].kind).assertEqual(SuggestionKind.Search);
      expect(suggestions[0].title).assertEqual('privacy browser');
      expect(suggestions[0].subtitle).assertEqual('');
      expect(suggestions[0].url).assertEqual('https://www.bing.com/search?q=privacy%20browser');
    });

    it('does not create remote-style shortcuts when disabled or when the input is an address', 0, (): void => {
      const viewModel: BrowserViewModel = new BrowserViewModel();

      expect(viewModel.getSuggestions('privacy browser').length).assertEqual(0);

      viewModel.settings.searchSuggestionsEnabled = true;

      expect(viewModel.getSuggestions('example.com').length).assertEqual(0);
    });
  });

  describe('BrowserViewModel start-page shortcuts', (): void => {
    it('keeps bookmarks and browsing history out of start-page shortcuts', 0, (): void => {
      const viewModel: BrowserViewModel = new BrowserViewModel();
      const now: number = Date.now();
      const favorite: SavedItem = {
        id: 'saved-docs',
        title: 'Dolphin Docs',
        url: 'https://docs.dolphin.example/guide',
        createdAt: now,
        updatedAt: now,
        isRead: true,
        tags: []
      };
      const frequent: HistoryEntry = {
        id: 'history-news',
        title: 'Visited News',
        url: 'https://visited.example/article',
        visitedAt: now,
        visitCount: 200
      };
      viewModel.savedItems = [favorite];
      viewModel.history = [frequent];

      const sites: QuickSite[] = viewModel.getQuickSites();

      expect(sites.some((site: QuickSite): boolean => site.url === favorite.url)).assertFalse();
      expect(sites.some((site: QuickSite): boolean => site.url.includes('visited.example'))).assertFalse();
      expect(sites.some((site: QuickSite): boolean => site.title === '知乎')).assertTrue();
      expect(sites.some((site: QuickSite): boolean => site.url.includes('m.weibo.cn'))).assertFalse();
    });

    it('moves shortcuts without changing their contents', 0, (): void => {
      const sites: QuickSite[] = [
        { title: 'One', url: 'https://one.example', badge: 'O', colorIndex: 0 },
        { title: 'Two', url: 'https://two.example', badge: 'T', colorIndex: 1 },
        { title: 'Three', url: 'https://three.example', badge: 'T', colorIndex: 2 }
      ];

      const moved: QuickSite[] = moveQuickSite(sites, 0, 2);

      expect(moved[0].title).assertEqual('Two');
      expect(moved[1].title).assertEqual('Three');
      expect(moved[2].title).assertEqual('One');
      expect(sites[0].title).assertEqual('One');
    });

    it('rejects invalid shortcut move indexes', 0, (): void => {
      const sites: QuickSite[] = [
        { title: 'Only', url: 'https://only.example', badge: 'O', colorIndex: 0 }
      ];

      expect(moveQuickSite(sites, -1, 0)[0].title).assertEqual('Only');
      expect(moveQuickSite(sites, 0, 4)[0].title).assertEqual('Only');
    });

    it('maps a grid drop after the last item to the final shortcut', 0, (): void => {
      expect(quickSiteDropTarget(4, 4)).assertEqual(3);
      expect(quickSiteDropTarget(4, 2)).assertEqual(2);
      expect(quickSiteDropTarget(4, 5)).assertEqual(-1);
    });
  });

  describe('BrowserViewModel closed tab restore', (): void => {
    it('restores a normal tab with a fresh identity and preserved page state', 0, (): void => {
      const viewModel: BrowserViewModel = new BrowserViewModel();
      const snapshot: BrowserTab = viewModel.createTab('https://restore.example/article', false);
      snapshot.title = 'Restorable page';
      snapshot.scrollY = 420;

      const restored: BrowserTab | undefined = viewModel.restoreTab(snapshot);

      expect(restored === undefined).assertFalse();
      expect(restored?.id === snapshot.id).assertFalse();
      expect(restored?.title).assertEqual('Restorable page');
      expect(restored?.scrollY).assertEqual(420);
      expect(viewModel.activeTabId).assertEqual(restored?.id);
    });

    it('never restores a private tab into the persistent normal session', 0, (): void => {
      const viewModel: BrowserViewModel = new BrowserViewModel();
      const snapshot: BrowserTab = viewModel.createTab('https://private.example', true);

      expect(viewModel.restoreTab(snapshot) === undefined).assertTrue();
    });
  });

  describe('BrowserViewModel window transfer', (): void => {
    it('adopts one transferred tab with a fresh identity and preserved page state', 0, (): void => {
      const viewModel: BrowserViewModel = new BrowserViewModel();
      const snapshot: BrowserTab = viewModel.createTab('https://window.example/article', false);
      snapshot.title = 'Window transfer';
      snapshot.scrollY = 640;
      snapshot.formDraft = 'draft';

      const transferred: BrowserTab = viewModel.adoptTransferredTab(snapshot);

      expect(viewModel.tabs.length).assertEqual(1);
      expect(transferred.id === snapshot.id).assertFalse();
      expect(transferred.title).assertEqual('Window transfer');
      expect(transferred.scrollY).assertEqual(640);
      expect(transferred.formDraft).assertEqual('draft');
      expect(viewModel.activeTabId).assertEqual(transferred.id);
    });

    it('leaves a fresh home tab after detaching the only source tab', 0, (): void => {
      const viewModel: BrowserViewModel = new BrowserViewModel();
      const source: BrowserTab = viewModel.createTab('https://window.example', false);
      viewModel.tabs = [source];
      viewModel.activeTabId = source.id;

      viewModel.detachTab(source.id);

      expect(viewModel.tabs.length).assertEqual(1);
      expect(viewModel.tabs[0].id === source.id).assertFalse();
      expect(viewModel.tabs[0].url).assertEqual(HOME_URL);
    });
  });

  describe('BrowserViewModel desktop tab strip', (): void => {
    it('reorders tabs only inside the same privacy and pin group', 0, (): void => {
      const viewModel: BrowserViewModel = new BrowserViewModel();
      const first: BrowserTab = viewModel.createTab('https://first.example', false);
      const second: BrowserTab = viewModel.createTab('https://second.example', false);
      const privateTab: BrowserTab = viewModel.createTab('https://private.example', true);
      viewModel.tabs = [first, second, privateTab];

      expect(viewModel.reorderTab(second.id, -1)).assertTrue();
      expect(viewModel.tabs[0].id).assertEqual(second.id);
      expect(viewModel.reorderTab(first.id, 1)).assertFalse();
      expect(viewModel.tabs[2].id).assertEqual(privateTab.id);
    });

    it('keeps pinned tabs ahead of regular tabs and never pins private tabs', 0, (): void => {
      const viewModel: BrowserViewModel = new BrowserViewModel();
      const first: BrowserTab = viewModel.createTab('https://first.example', false);
      const second: BrowserTab = viewModel.createTab('https://second.example', false);
      const privateTab: BrowserTab = viewModel.createTab('https://private.example', true);
      viewModel.tabs = [first, second, privateTab];

      expect(viewModel.toggleTabPinned(second.id)).assertTrue();
      expect(viewModel.tabs[0].id).assertEqual(second.id);
      expect(viewModel.tabs[0].isPinned).assertTrue();
      expect(viewModel.toggleTabPinned(privateTab.id)).assertFalse();
    });
  });

  describe('BrowserViewModel user agent policy', (): void => {
    it('resolves host preference ahead of the global default', 0, (): void => {
      const viewModel: BrowserViewModel = new BrowserViewModel();
      viewModel.settings.defaultUserAgentPreference = UserAgentPreference.Desktop;
      viewModel.settings.siteUserAgentPreferences = [{
        host: 'mobile.example',
        preference: UserAgentPreference.Mobile
      }];

      expect(viewModel.preferredDesktopForUrl('https://docs.example/page')).assertTrue();
      expect(viewModel.preferredDesktopForUrl('https://mobile.example/page')).assertFalse();
      expect(viewModel.userAgentPreferenceForUrl('https://mobile.example/other'))
        .assertEqual(UserAgentPreference.Mobile);
    });
  });

  describe('BrowserViewModel content blocking policy', (): void => {
    it('keeps a host allow-list entry scoped to that exact navigation host', 0, async (): Promise<void> => {
      const viewModel: BrowserViewModel = new BrowserViewModel();
      await viewModel.setHostAllowed('http://127.0.0.1:4188/fixture', true);

      expect(viewModel.adsBlockEnabledForUrl('http://127.0.0.1:4188/next')).assertFalse();
      expect(viewModel.adsBlockEnabledForUrl('http://localhost:4188/fixture')).assertTrue();
    });
  });

  describe('Pane layout', (): void => {
    it('keeps a draggable divider inside the supported 30/70 range', 0, (): void => {
      expect(clampPaneRatio(0.1)).assertEqual(0.3);
      expect(clampPaneRatio(0.5)).assertEqual(0.5);
      expect(clampPaneRatio(0.9)).assertEqual(0.7);
    });
  });

  describe('Fold crease metrics', (): void => {
    it('classifies only valid half-folded crease orientation', 0, (): void => {
      const horizontal: BrowserFoldMetrics = {
        isHalfFolded: true,
        crease: { leftVp: 0, topVp: 400, widthVp: 800, heightVp: 18 }
      };
      const vertical: BrowserFoldMetrics = {
        isHalfFolded: true,
        crease: { leftVp: 400, topVp: 0, widthVp: 18, heightVp: 800 }
      };
      expect(hasHorizontalCrease(horizontal)).assertTrue();
      expect(hasVerticalCrease(horizontal)).assertFalse();
      expect(hasVerticalCrease(vertical)).assertTrue();
    });
  });
}
