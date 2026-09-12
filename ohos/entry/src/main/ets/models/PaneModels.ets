export enum PaneId {
  Primary = 'primary',
  Secondary = 'secondary'
}

export interface BrowserPane {
  id: PaneId;
  tabId: string;
}

export interface PaneLayout {
  panes: BrowserPane[];
  focusedPaneId: PaneId;
  targetPaneId: PaneId;
  primaryRatio: number;
}

export function clampPaneRatio(ratio: number): number {
  return Math.max(0.3, Math.min(0.7, ratio));
}

export function paneTabId(layout: PaneLayout, paneId: PaneId): string {
  return layout.panes.find((pane: BrowserPane): boolean => pane.id === paneId)?.tabId ?? '';
}
