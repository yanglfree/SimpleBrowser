import { describe, expect, it } from '@ohos/hypium';
import {
  BrowserTab,
  Suggestion,
  SuggestionKind,
  UserAgentPreference
} from '../main/ets/models/BrowserModels';
import { BrowserViewModel } from '../main/ets/viewmodels/BrowserViewModel';
import { clampPaneRatio } from '../main/ets/models/PaneModels';

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

  describe('Pane layout', (): void => {
    it('keeps a draggable divider inside the supported 30/70 range', 0, (): void => {
      expect(clampPaneRatio(0.1)).assertEqual(0.3);
      expect(clampPaneRatio(0.5)).assertEqual(0.5);
      expect(clampPaneRatio(0.9)).assertEqual(0.7);
    });
  });
}
