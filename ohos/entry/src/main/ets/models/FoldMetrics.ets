export interface FoldCreaseMetrics {
  leftVp: number;
  topVp: number;
  widthVp: number;
  heightVp: number;
}

export interface BrowserFoldMetrics {
  isHalfFolded: boolean;
  crease?: FoldCreaseMetrics;
}

export function emptyFoldMetrics(): BrowserFoldMetrics {
  return { isHalfFolded: false };
}

export function hasHorizontalCrease(metrics: BrowserFoldMetrics): boolean {
  const crease: FoldCreaseMetrics | undefined = metrics.crease;
  return metrics.isHalfFolded && crease !== undefined && crease.widthVp > crease.heightVp;
}

export function hasVerticalCrease(metrics: BrowserFoldMetrics): boolean {
  const crease: FoldCreaseMetrics | undefined = metrics.crease;
  return metrics.isHalfFolded && crease !== undefined && crease.heightVp >= crease.widthVp;
}
