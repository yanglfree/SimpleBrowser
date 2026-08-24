import { BrowserLayoutClass } from './WindowMetrics';

export const ARTICLE_WORKBENCH_INSPECTOR_WIDTH: number = 320;
export const ARTICLE_WORKBENCH_READER_MAX_WIDTH: number = 760;
const ARTICLE_WORKBENCH_HORIZONTAL_PADDING: number = 48;

export enum ArticleWorkbenchMode {
  Compact = 0,
  SwitchableInspector = 1,
  FixedInspector = 2
}

export function articleWorkbenchMode(layoutClass: BrowserLayoutClass): ArticleWorkbenchMode {
  if (layoutClass >= BrowserLayoutClass.Expanded) {
    return ArticleWorkbenchMode.FixedInspector;
  }
  if (layoutClass >= BrowserLayoutClass.Medium) {
    return ArticleWorkbenchMode.SwitchableInspector;
  }
  return ArticleWorkbenchMode.Compact;
}

export function shouldShowArticleInspector(
  layoutClass: BrowserLayoutClass,
  requestedVisible: boolean
): boolean {
  return articleWorkbenchMode(layoutClass) === ArticleWorkbenchMode.FixedInspector ||
    (articleWorkbenchMode(layoutClass) === ArticleWorkbenchMode.SwitchableInspector && requestedVisible);
}

export function articleReaderMaxWidth(availableWidthVp: number, inspectorVisible: boolean): number {
  if (availableWidthVp <= 0) {
    return ARTICLE_WORKBENCH_READER_MAX_WIDTH;
  }
  const reservedWidth: number = inspectorVisible ? ARTICLE_WORKBENCH_INSPECTOR_WIDTH : 0;
  return Math.min(
    ARTICLE_WORKBENCH_READER_MAX_WIDTH,
    Math.max(0, availableWidthVp - reservedWidth - ARTICLE_WORKBENCH_HORIZONTAL_PADDING)
  );
}

export function articleWorkbenchOverlayWidth(windowWidthVp: number): number {
  return Math.min(1180, Math.max(0, windowWidthVp - 24));
}
