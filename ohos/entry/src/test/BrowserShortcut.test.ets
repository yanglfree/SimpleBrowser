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
  });
}
