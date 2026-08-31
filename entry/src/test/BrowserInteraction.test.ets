import { describe, expect, it } from '@ohos/hypium';
import {
  ACTION_SHEET_DISMISS_THRESHOLD,
  clampedActionSheetDrag,
  shouldDismissActionSheet
} from '../main/ets/components/ActionSheet';
import {
  shouldShowCurrentSiteDarkModeRow
} from '../main/ets/components/SettingsPage';
import { GLYPH_GRID, iconStrokeUnits } from '../main/ets/components/AppIcon';
import {
  DOCK_BADGE_ICON_STROKE,
  DOCK_COLLAPSED_HEIGHT,
  DOCK_COLLAPSED_PILL_HEIGHT,
  DOCK_ICON_SIZE,
  DOCK_ICON_STROKE,
  DOCK_PILL_ICON_SIZE,
  TAB_WEB_BOTTOM_INSET_COMPACT
} from '../main/ets/components/TabTokens';
import { WebDarkModePreference } from '../main/ets/models/BrowserModels';

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
      expect(TAB_WEB_BOTTOM_INSET_COMPACT).assertEqual(DOCK_COLLAPSED_PILL_HEIGHT + 2);
    });

    it('draws one stroke weight across the toolbar glyph sizes', 0, (): void => {
      const bar: number = iconStrokeUnits(DOCK_ICON_SIZE, DOCK_ICON_STROKE) * DOCK_ICON_SIZE / GLYPH_GRID;
      const field: number =
        iconStrokeUnits(DOCK_PILL_ICON_SIZE, DOCK_ICON_STROKE) * DOCK_PILL_ICON_SIZE / GLYPH_GRID;
      expect(Math.abs(bar - DOCK_ICON_STROKE) < 0.001).assertTrue();
      expect(Math.abs(field - DOCK_ICON_STROKE) < 0.001).assertTrue();
      // Status glyphs stay a step lighter than the controls they sit beside.
      expect(DOCK_BADGE_ICON_STROKE < DOCK_ICON_STROKE).assertTrue();
      expect(iconStrokeUnits(0, DOCK_ICON_STROKE)).assertEqual(DOCK_ICON_STROKE);
    });

    it('hides the current-site dark-mode row only when web dark mode is light', 0, (): void => {
      expect(shouldShowCurrentSiteDarkModeRow('zhihu.com', WebDarkModePreference.System)).assertTrue();
      expect(shouldShowCurrentSiteDarkModeRow('zhihu.com', WebDarkModePreference.Light)).assertFalse();
      expect(shouldShowCurrentSiteDarkModeRow('', WebDarkModePreference.System)).assertFalse();
    });
  });
}
