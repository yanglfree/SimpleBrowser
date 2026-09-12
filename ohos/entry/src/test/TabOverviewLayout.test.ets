import { describe, expect, it } from '@ohos/hypium';
import {
  tabOverviewColumnCount,
  tabOverviewGridHeight
} from '../main/ets/components/TabOverview';
import {
  TAB_CARD_HEIGHT,
  TAB_OVERVIEW_GRID_BOTTOM,
  TAB_OVERVIEW_GRID_GAP
} from '../main/ets/components/TabTokens';

export default function tabOverviewLayoutTest(): void {
  describe('TabOverview responsive layout', (): void => {
    it('keeps phone tab overview cards in a two-column grid', 0, (): void => {
      expect(tabOverviewColumnCount(280)).assertEqual(1);
      expect(tabOverviewColumnCount(360)).assertEqual(2);
      expect(tabOverviewColumnCount(599)).assertEqual(2);
      expect(tabOverviewColumnCount(600)).assertEqual(2);
      expect(tabOverviewColumnCount(840)).assertEqual(3);
      expect(tabOverviewColumnCount(1200)).assertEqual(4);
      expect(tabOverviewColumnCount(2400)).assertEqual(4);
    });

    it('computes height from actual rows for small and large tab sets', 0, (): void => {
      expect(tabOverviewGridHeight(1, 1)).assertEqual(TAB_CARD_HEIGHT + TAB_OVERVIEW_GRID_BOTTOM);
      expect(tabOverviewGridHeight(2, 2)).assertEqual(TAB_CARD_HEIGHT + TAB_OVERVIEW_GRID_BOTTOM);
      expect(tabOverviewGridHeight(10, 3)).assertEqual(
        TAB_CARD_HEIGHT * 4 + TAB_OVERVIEW_GRID_GAP * 3 + TAB_OVERVIEW_GRID_BOTTOM
      );
      expect(tabOverviewGridHeight(40, 4)).assertEqual(
        TAB_CARD_HEIGHT * 10 + TAB_OVERVIEW_GRID_GAP * 9 + TAB_OVERVIEW_GRID_BOTTOM
      );
    });
  });
}
