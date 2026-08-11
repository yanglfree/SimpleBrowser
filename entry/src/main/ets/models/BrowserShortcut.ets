import { KeyCode } from '@kit.InputKit';

export enum BrowserShortcut {
  None = 0,
  FocusAddress = 1,
  NewTab = 2,
  CloseTab = 3,
  ReopenTab = 4,
  NextTab = 5,
  PreviousTab = 6,
  Reload = 7,
  Find = 8
}

export interface BrowserShortcutInput {
  keyCode: number;
  ctrl: boolean;
  shift: boolean;
  keyDown: boolean;
}

export function resolveBrowserShortcut(input: BrowserShortcutInput): BrowserShortcut {
  if (!input.keyDown || !input.ctrl) {
    return BrowserShortcut.None;
  }
  switch (input.keyCode) {
    case KeyCode.KEYCODE_L:
      return input.shift ? BrowserShortcut.None : BrowserShortcut.FocusAddress;
    case KeyCode.KEYCODE_T:
      return input.shift ? BrowserShortcut.ReopenTab : BrowserShortcut.NewTab;
    case KeyCode.KEYCODE_W:
      return input.shift ? BrowserShortcut.None : BrowserShortcut.CloseTab;
    case KeyCode.KEYCODE_TAB:
      return input.shift ? BrowserShortcut.PreviousTab : BrowserShortcut.NextTab;
    case KeyCode.KEYCODE_R:
      return input.shift ? BrowserShortcut.None : BrowserShortcut.Reload;
    case KeyCode.KEYCODE_F:
      return input.shift ? BrowserShortcut.None : BrowserShortcut.Find;
    default:
      return BrowserShortcut.None;
  }
}
