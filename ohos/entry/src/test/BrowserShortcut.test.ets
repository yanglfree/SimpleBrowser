import { KeyCode } from '@kit.InputKit';
import { describe, expect, it } from '@ohos/hypium';
import {
  BrowserShortcut,
  resolveBrowserShortcut
} from '../main/ets/models/BrowserShortcut';

export default function browserShortcutTest(): void {
  describe('BrowserShortcut resolver', (): void => {
    it('maps the supported control shortcuts', 0, (): void => {
      expect(resolveBrowserShortcut({ keyCode: KeyCode.KEYCODE_L, ctrl: true, shift: false, keyDown: true }))
        .assertEqual(BrowserShortcut.FocusAddress);
      expect(resolveBrowserShortcut({ keyCode: KeyCode.KEYCODE_T, ctrl: true, shift: false, keyDown: true }))
        .assertEqual(BrowserShortcut.NewTab);
      expect(resolveBrowserShortcut({ keyCode: KeyCode.KEYCODE_W, ctrl: true, shift: false, keyDown: true }))
        .assertEqual(BrowserShortcut.CloseTab);
      expect(resolveBrowserShortcut({ keyCode: KeyCode.KEYCODE_R, ctrl: true, shift: false, keyDown: true }))
        .assertEqual(BrowserShortcut.Reload);
      expect(resolveBrowserShortcut({ keyCode: KeyCode.KEYCODE_F, ctrl: true, shift: false, keyDown: true }))
        .assertEqual(BrowserShortcut.Find);
      expect(resolveBrowserShortcut({ keyCode: KeyCode.KEYCODE_S, ctrl: true, shift: false, keyDown: true }))
        .assertEqual(BrowserShortcut.SaveArticle);
    });

    it('uses shift only for reopen and reverse tab traversal', 0, (): void => {
      expect(resolveBrowserShortcut({ keyCode: KeyCode.KEYCODE_T, ctrl: true, shift: true, keyDown: true }))
        .assertEqual(BrowserShortcut.ReopenTab);
      expect(resolveBrowserShortcut({ keyCode: KeyCode.KEYCODE_TAB, ctrl: true, shift: false, keyDown: true }))
        .assertEqual(BrowserShortcut.NextTab);
      expect(resolveBrowserShortcut({ keyCode: KeyCode.KEYCODE_TAB, ctrl: true, shift: true, keyDown: true }))
        .assertEqual(BrowserShortcut.PreviousTab);
    });

    it('does not consume plain keys, key-up events, or unsupported shifted combinations', 0, (): void => {
      expect(resolveBrowserShortcut({ keyCode: KeyCode.KEYCODE_L, ctrl: false, shift: false, keyDown: true }))
        .assertEqual(BrowserShortcut.None);
      expect(resolveBrowserShortcut({ keyCode: KeyCode.KEYCODE_L, ctrl: true, shift: false, keyDown: false }))
        .assertEqual(BrowserShortcut.None);
      expect(resolveBrowserShortcut({ keyCode: KeyCode.KEYCODE_W, ctrl: true, shift: true, keyDown: true }))
        .assertEqual(BrowserShortcut.None);
    });

    it('maps desktop zoom, panel, private-tab, reload, and alt navigation shortcuts', 0, (): void => {
      expect(resolveBrowserShortcut({ keyCode: KeyCode.KEYCODE_EQUALS, ctrl: true, shift: false, keyDown: true }))
        .assertEqual(BrowserShortcut.ZoomIn);
      expect(resolveBrowserShortcut({ keyCode: KeyCode.KEYCODE_NUMPAD_ADD, ctrl: true, shift: true, keyDown: true }))
        .assertEqual(BrowserShortcut.ZoomIn);
      expect(resolveBrowserShortcut({ keyCode: KeyCode.KEYCODE_MINUS, ctrl: true, shift: false, keyDown: true }))
        .assertEqual(BrowserShortcut.ZoomOut);
      expect(resolveBrowserShortcut({ keyCode: KeyCode.KEYCODE_NUMPAD_SUBTRACT, ctrl: true, shift: false, keyDown: true }))
        .assertEqual(BrowserShortcut.ZoomOut);
      expect(resolveBrowserShortcut({ keyCode: KeyCode.KEYCODE_0, ctrl: true, shift: false, keyDown: true }))
        .assertEqual(BrowserShortcut.ZoomReset);
      expect(resolveBrowserShortcut({ keyCode: KeyCode.KEYCODE_NUMPAD_0, ctrl: true, shift: false, keyDown: true }))
        .assertEqual(BrowserShortcut.ZoomReset);
      expect(resolveBrowserShortcut({ keyCode: KeyCode.KEYCODE_H, ctrl: true, shift: false, keyDown: true }))
        .assertEqual(BrowserShortcut.OpenHistory);
      expect(resolveBrowserShortcut({ keyCode: KeyCode.KEYCODE_J, ctrl: true, shift: false, keyDown: true }))
        .assertEqual(BrowserShortcut.OpenDownloads);
      expect(resolveBrowserShortcut({ keyCode: KeyCode.KEYCODE_D, ctrl: true, shift: false, keyDown: true }))
        .assertEqual(BrowserShortcut.BookmarkPage);
      expect(resolveBrowserShortcut({ keyCode: KeyCode.KEYCODE_N, ctrl: true, shift: true, keyDown: true }))
        .assertEqual(BrowserShortcut.NewPrivateTab);
      expect(resolveBrowserShortcut({ keyCode: KeyCode.KEYCODE_F5, ctrl: false, shift: false, keyDown: true }))
        .assertEqual(BrowserShortcut.Reload);
      expect(resolveBrowserShortcut({
        keyCode: KeyCode.KEYCODE_DPAD_LEFT, ctrl: false, shift: false, alt: true, keyDown: true
      })).assertEqual(BrowserShortcut.NavigateBack);
      expect(resolveBrowserShortcut({
        keyCode: KeyCode.KEYCODE_DPAD_RIGHT, ctrl: false, shift: false, alt: true, keyDown: true
      })).assertEqual(BrowserShortcut.NavigateForward);
    });
  });
}
