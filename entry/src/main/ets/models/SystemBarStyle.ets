import { ReaderPaper, ReaderTheme, getReaderTheme } from './BrowserModels';

export const HOME_STATUS_SCRIM: string = '#99000000';
export const STATUS_SCRIM_FADE_HEIGHT: number = 32;

export interface BrowserSystemBarStyle {
  background: string;
  content: string;
  wallpaper: boolean;
}

/** The backdrop and native icons must always use the same resolved surface. */
export function resolveSystemBarStyle(
  isDark: boolean,
  wallpaper: boolean,
  isReader: boolean,
  readerPaper: ReaderPaper,
  hasOverlay: boolean
): BrowserSystemBarStyle {
  if (wallpaper && !hasOverlay) {
    return { background: '#20352B', content: '#FFFFFF', wallpaper: true };
  }
  if (isReader && !hasOverlay) {
    const theme: ReaderTheme = getReaderTheme(readerPaper);
    return {
      background: theme.background,
      content: theme.isDark ? '#F5F3EE' : '#1A1A18',
      wallpaper: false
    };
  }
  return {
    background: isDark ? '#131311' : '#FAF9F7',
    content: isDark ? '#F5F3EE' : '#1A1A18',
    wallpaper: false
  };
}

export function resolveStatusBarBackdropHeight(topInset: number, wallpaper: boolean): number {
  if (topInset <= 0) {
    return 0;
  }
  return topInset + (wallpaper ? STATUS_SCRIM_FADE_HEIGHT : 0);
}

