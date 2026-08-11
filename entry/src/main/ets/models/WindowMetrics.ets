export const MEDIUM_WINDOW_MIN_WIDTH: number = 600;
export const EXPANDED_WINDOW_MIN_WIDTH: number = 840;
export const DESKTOP_WINDOW_MIN_WIDTH: number = 1440;
export const CONSTRAINED_WINDOW_MAX_HEIGHT: number = 480;
export const WIDE_WINDOW_MIN_ASPECT_RATIO: number = 2;

export enum BrowserLayoutClass {
  Compact = 0,
  Medium = 1,
  Expanded = 2,
  Desktop = 3
}

export enum BrowserWindowMode {
  Unknown = 0,
  FullScreen = 1,
  Maximized = 2,
  Minimized = 3,
  Floating = 4,
  Split = 5
}

export interface BrowserWindowMetrics {
  widthVp: number;
  heightVp: number;
  aspectRatio: number;
  layoutClass: BrowserLayoutClass;
  windowMode: BrowserWindowMode;
  isHeightConstrained: boolean;
}

export function createWindowMetrics(
  widthVp: number,
  heightVp: number,
  windowMode: BrowserWindowMode
): BrowserWindowMetrics {
  const safeWidth: number = normalizedDimension(widthVp);
  const safeHeight: number = normalizedDimension(heightVp);
  const aspectRatio: number = safeHeight > 0 ? safeWidth / safeHeight : 0;
  return {
    widthVp: safeWidth,
    heightVp: safeHeight,
    aspectRatio: aspectRatio,
    layoutClass: layoutClassForWidth(safeWidth),
    windowMode: windowMode,
    isHeightConstrained: safeHeight < CONSTRAINED_WINDOW_MAX_HEIGHT ||
      aspectRatio >= WIDE_WINDOW_MIN_ASPECT_RATIO
  };
}

export function layoutClassForWidth(widthVp: number): BrowserLayoutClass {
  if (widthVp >= DESKTOP_WINDOW_MIN_WIDTH) {
    return BrowserLayoutClass.Desktop;
  }
  if (widthVp >= EXPANDED_WINDOW_MIN_WIDTH) {
    return BrowserLayoutClass.Expanded;
  }
  if (widthVp >= MEDIUM_WINDOW_MIN_WIDTH) {
    return BrowserLayoutClass.Medium;
  }
  return BrowserLayoutClass.Compact;
}

function normalizedDimension(value: number): number {
  return Number.isFinite(value) && value > 0 ? value : 0;
}
