import { describe, expect, it } from '@ohos/hypium';
import {
  ACTION_SHEET_DISMISS_THRESHOLD,
  clampedActionSheetDrag,
  shouldDismissActionSheet
} from '../main/ets/components/ActionSheet';
import {
  DOCK_COLLAPSED_HEIGHT,
  DOCK_COLLAPSED_PILL_HEIGHT,
  TAB_WEB_BOTTOM_INSET_COMPACT
} from '../main/ets/components/TabTokens';

export default function browserInteractionTest(): void {
  describe('Browser surface interactions', (): void => {
    it('dismisses the action sheet only after a deliberate downward drag', 0, (): void => {
      expect(clampedActionSheetDrag(-20)).assertEqual(0);
      expect(clampedActionSheetDrag(ACTION_SHEET_DISMISS_THRESHOLD - 1))
        .assertEqual(ACTION_SHEET_DISMISS_THRESHOLD - 1);
      expect(shouldDismissActionSheet(ACTION_SHEET_DISMISS_THRESHOLD - 1)).assertFalse();
      expect(shouldDismissActionSheet(ACTION_SHEET_DISMISS_THRESHOLD)).assertTrue();
    });

    it('reserves only the collapsed pill height beneath a scrolled page', 0, (): void => {
      expect(DOCK_COLLAPSED_HEIGHT).assertEqual(DOCK_COLLAPSED_PILL_HEIGHT);
      expect(TAB_WEB_BOTTOM_INSET_COMPACT).assertEqual(DOCK_COLLAPSED_PILL_HEIGHT + 4);
    });
  });
}
