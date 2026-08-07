import { describe, expect, it } from '@ohos/hypium';
import { BrowserTab } from '../main/ets/models/BrowserModels';
import { BrowserViewModel } from '../main/ets/viewmodels/BrowserViewModel';

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
}
