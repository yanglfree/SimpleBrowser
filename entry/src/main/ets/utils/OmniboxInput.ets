export interface OmniboxSelection {
  start: number;
  end: number;
}

export interface OmniboxEditResult {
  text: string;
  selection: OmniboxSelection;
}

export enum OmniboxShortcutKind {
  CurrentHost = 0,
  Prefix = 1,
  Suffix = 2,
  Path = 3
}

export interface OmniboxShortcut {
  label: string;
  value: string;
  kind: OmniboxShortcutKind;
}

function clampIndex(value: number, length: number): number {
  return Math.min(length, Math.max(0, value));
}

function normalizedSelection(text: string, start: number, end: number): OmniboxSelection {
  const first: number = clampIndex(Math.min(start, end), text.length);
  const second: number = clampIndex(Math.max(start, end), text.length);
  return { start: first, end: second };
}

function replaceSelection(text: string, selection: OmniboxSelection, replacement: string): OmniboxEditResult {
  const nextText: string = `${text.substring(0, selection.start)}${replacement}${text.substring(selection.end)}`;
  const caret: number = selection.start + replacement.length;
  return { text: nextText, selection: { start: caret, end: caret } };
}

function insertPrefix(text: string, selection: OmniboxSelection, prefix: string): OmniboxEditResult {
  if (selection.start !== selection.end) {
    const selected: string = text.substring(selection.start, selection.end);
    return replaceSelection(text, selection, selected.startsWith(prefix) ? selected : `${prefix}${selected}`);
  }
  const schemeMatch: RegExpMatchArray | null = text.match(/^[a-z][a-z0-9+.-]*:\/\//i);
  const insertionPoint: number = schemeMatch === null ? 0 : schemeMatch[0].length;
  if (text.substring(insertionPoint).startsWith(prefix)) {
    return { text: text, selection: { start: selection.start, end: selection.end } };
  }
  return replaceSelection(text, { start: insertionPoint, end: insertionPoint }, prefix);
}

function insertSuffix(text: string, selection: OmniboxSelection, suffix: string): OmniboxEditResult {
  if (selection.start !== selection.end) {
    const selected: string = text.substring(selection.start, selection.end);
    return replaceSelection(text, selection, selected.endsWith(suffix) ? selected : `${selected}${suffix}`);
  }
  if (text.substring(0, selection.start).endsWith(suffix)) {
    return { text: text, selection: { start: selection.start, end: selection.end } };
  }
  return replaceSelection(text, selection, suffix);
}

function insertPathSeparator(text: string, selection: OmniboxSelection): OmniboxEditResult {
  if (selection.start === selection.end &&
    (text.substring(0, selection.start).endsWith('/') || text.substring(selection.start).startsWith('/'))) {
    return { text: text, selection: { start: selection.start, end: selection.end } };
  }
  return replaceSelection(text, selection, '/');
}

export function applyOmniboxShortcut(
  text: string,
  start: number,
  end: number,
  shortcut: OmniboxShortcut
): OmniboxEditResult {
  const selection: OmniboxSelection = normalizedSelection(text, start, end);
  if (shortcut.kind === OmniboxShortcutKind.CurrentHost) {
    const replacement: string = shortcut.value.trim();
    const nextSelection: OmniboxSelection = { start: replacement.length, end: replacement.length };
    return { text: replacement, selection: nextSelection };
  }
  if (shortcut.kind === OmniboxShortcutKind.Prefix) {
    return insertPrefix(text, selection, shortcut.value);
  }
  if (shortcut.kind === OmniboxShortcutKind.Suffix) {
    return insertSuffix(text, selection, shortcut.value);
  }
  return insertPathSeparator(text, selection);
}

export function omniboxShortcuts(currentHost: string): OmniboxShortcut[] {
  const shortcuts: OmniboxShortcut[] = [];
  const host: string = currentHost.trim();
  if (host.length > 0) {
    shortcuts.push({ label: host, value: host, kind: OmniboxShortcutKind.CurrentHost });
  }
  shortcuts.push({ label: '.com', value: '.com', kind: OmniboxShortcutKind.Suffix });
  shortcuts.push({ label: '.cn', value: '.cn', kind: OmniboxShortcutKind.Suffix });
  shortcuts.push({ label: 'www.', value: 'www.', kind: OmniboxShortcutKind.Prefix });
  shortcuts.push({ label: '/', value: '/', kind: OmniboxShortcutKind.Path });
  return shortcuts;
}
