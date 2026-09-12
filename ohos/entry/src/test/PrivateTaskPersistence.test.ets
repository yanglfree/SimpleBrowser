import { describe, expect, it } from '@ohos/hypium';
import { BlockStats, BrowserSession, BrowserTab, emptyBlockStats } from '../main/ets/models/BrowserModels';
import { BrowserViewModel } from '../main/ets/viewmodels/BrowserViewModel';

export default function privateTaskPersistenceTest(): void {
  describe('Private task persistence', (): void => {
    it('keeps disposable work out of sessions, history, and persistent block totals', 0, (): void => {
      const viewModel: BrowserViewModel = new BrowserViewModel();
      const normalTab: BrowserTab = viewModel.createTab('https://normal.example', false);
      const disposableTab: BrowserTab = viewModel.createTab('https://private.example/task', true);
      viewModel.tabs = [normalTab, disposableTab];
      viewModel.activeTabId = disposableTab.id;

      viewModel.persistSession();
      const session: BrowserSession | undefined = viewModel.repository.getSession();
      expect(session?.tabs.length).assertEqual(1);
      expect(session?.tabs[0].id).assertEqual(normalTab.id);
      expect(session?.activeTabId).assertEqual(normalTab.id);

      void viewModel.recordPageVisit(disposableTab);
      expect(viewModel.history.length).assertEqual(0);

      const blocked: BlockStats = emptyBlockStats();
      blocked.trackers = 2;
      void viewModel.recordBlocked(disposableTab.id, blocked);
      expect(viewModel.getTab(disposableTab.id)?.blocked.trackers).assertEqual(2);
      expect(viewModel.getCumulativeBlocked()).assertEqual(0);
    });
  });
}
