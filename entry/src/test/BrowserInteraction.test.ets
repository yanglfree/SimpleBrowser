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
import { SearchEngine, WebDarkModePreference } from '../main/ets/models/BrowserModels';
import {
  applyOmniboxShortcut,
  OmniboxEditResult,
  OmniboxShortcut,
  OmniboxShortcutKind
} from '../main/ets/utils/OmniboxInput';
import { quickSiteEditorPanelHeight } from '../main/ets/components/QuickSiteEditor';
import { looksLikeUrl, normalizeAddress, normalizeUrlInput } from '../main/ets/utils/UrlUtils';

export default function browserInteractionTest(): void {
  describe('Browser surface interactions', (): void => {
    it('applies omnibox shortcuts at the current selection', 0, (): void => {
      const suffix: OmniboxShortcut = { label: '.com', value: '.com', kind: OmniboxShortcutKind.Suffix };
      const result: OmniboxEditResult = applyOmniboxShortcut('openai', 6, 6, suffix);

      expect(result.text).assertEqual('openai.com');
      expect(result.selection.start).assertEqual(10);
      expect(result.selection.end).assertEqual(10);
    });

    it('inserts a domain prefix after an existing scheme', 0, (): void => {
      const prefix: OmniboxShortcut = { label: 'www.', value: 'www.', kind: OmniboxShortcutKind.Prefix };
      const result: OmniboxEditResult = applyOmniboxShortcut('https://example.com', 19, 19, prefix);

      expect(result.text).assertEqual('https://www.example.com');
      expect(result.selection.start).assertEqual(12);
    });

    it('replaces the address with the current-host shortcut', 0, (): void => {
      const host: OmniboxShortcut = {
        label: 'example.com',
        value: 'example.com',
        kind: OmniboxShortcutKind.CurrentHost
      };
      const result: OmniboxEditResult = applyOmniboxShortcut('https://example.com/article', 0, 27, host);

      expect(result.text).assertEqual('example.com');
      expect(result.selection.start).assertEqual(11);
    });

    it('does not duplicate suffixes or path separators', 0, (): void => {
      const suffix: OmniboxShortcut = { label: '.com', value: '.com', kind: OmniboxShortcutKind.Suffix };
      const path: OmniboxShortcut = { label: '/', value: '/', kind: OmniboxShortcutKind.Path };

      expect(applyOmniboxShortcut('openai.com', 10, 10, suffix).text).assertEqual('openai.com');
      expect(applyOmniboxShortcut('openai.com/', 11, 11, path).text).assertEqual('openai.com/');
    });

    it('keeps the shortcut editor inside the keyboard-safe window height', 0, (): void => {
      expect(quickSiteEditorPanelHeight(780, 300, 36)).assertEqual(432);
      expect(quickSiteEditorPanelHeight(930, 0, 36)).assertEqual(620);
      expect(quickSiteEditorPanelHeight(320, 240, 24)).assertEqual(44);
    });

    it('recognizes common mobile address formats without treating phrases as URLs', 0, (): void => {
      expect(looksLikeUrl('localhost:8787')).assertTrue();
      expect(looksLikeUrl('192.168.1.20:3000/path')).assertTrue();
      expect(looksLikeUrl('[::1]:8080')).assertTrue();
      expect(looksLikeUrl('例子.中国')).assertTrue();
      expect(looksLikeUrl('999.168.1.20')).assertFalse();
      expect(looksLikeUrl('privacy browser')).assertFalse();
    });

    it('uses local-friendly schemes and searches non-address input', 0, (): void => {
      expect(normalizeUrlInput('localhost:8787')).assertEqual('http://localhost:8787');
      expect(normalizeUrlInput('192.168.1.20')).assertEqual('http://192.168.1.20');
      expect(normalizeUrlInput('例子.中国')).assertEqual('https://例子.中国');
      expect(normalizeAddress('privacy browser', SearchEngine.Bing))
        .assertEqual('https://www.bing.com/search?q=privacy%20browser');
    });

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
