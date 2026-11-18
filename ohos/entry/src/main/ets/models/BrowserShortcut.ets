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
  Find = 8,
  SaveArticle = 9,
  ZoomIn = 10,
  ZoomOut = 11,
  ZoomReset = 12,
  OpenHistory = 13,
  OpenDownloads = 14,
  BookmarkPage = 15,
  NewPrivateTab = 16,
  NavigateBack = 17,
  NavigateForward = 18
}

export interface BrowserShortcutInput {
  keyCode: number;
  ctrl: boolean;
  shift: boolean;
  alt?: boolean;
  keyDown: boolean;
}

export function resolveBrowserShortcut(input: BrowserShortcutInput): BrowserShortcut {
  if (!input.keyDown) {
    return BrowserShortcut.None;
  }
  const alt: boolean = input.alt === true;
  if (!input.ctrl && !alt && !input.shift && input.keyCode === KeyCode.KEYCODE_F5) {
    return BrowserShortcut.Reload;
  }
  if (alt && !input.ctrl && !input.shift) {
    if (input.keyCode === KeyCode.KEYCODE_DPAD_LEFT) {
      return BrowserShortcut.NavigateBack;
    }
    if (input.keyCode === KeyCode.KEYCODE_DPAD_RIGHT) {
      return BrowserShortcut.NavigateForward;
    }
    return BrowserShortcut.None;
  }
  if (!input.ctrl || alt) {
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
    case KeyCode.KEYCODE_S:
      return input.shift ? BrowserShortcut.None : BrowserShortcut.SaveArticle;
    case KeyCode.KEYCODE_EQUALS:
    case KeyCode.KEYCODE_NUMPAD_ADD:
      return BrowserShortcut.ZoomIn;
    case KeyCode.KEYCODE_MINUS:
    case KeyCode.KEYCODE_NUMPAD_SUBTRACT:
      return BrowserShortcut.ZoomOut;
    case KeyCode.KEYCODE_0:
    case KeyCode.KEYCODE_NUMPAD_0:
      return input.shift ? BrowserShortcut.None : BrowserShortcut.ZoomReset;
    case KeyCode.KEYCODE_H:
      return input.shift ? BrowserShortcut.None : BrowserShortcut.OpenHistory;
    case KeyCode.KEYCODE_J:
      return input.shift ? BrowserShortcut.None : BrowserShortcut.OpenDownloads;
    case KeyCode.KEYCODE_D:
      return input.shift ? BrowserShortcut.None : BrowserShortcut.BookmarkPage;
    case KeyCode.KEYCODE_N:
      return input.shift ? BrowserShortcut.NewPrivateTab : BrowserShortcut.None;
    default:
      return BrowserShortcut.None;
  }
}
