import { IconName } from './AppIcon';

export interface SemanticSiteTheme {
  icon: IconName;
  background: ResourceColor;
  foreground: ResourceColor;
}

/**
 * Modern curated vibrant palette for monogram fallback tiles (indices 0 - 5).
 * Designed to deliver high contrast and premium app-icon aesthetics on both
 * plain backgrounds and wallpaper textures.
 */
export const MONOGRAM_PALETTE: string[] = [
  '#2563EB', // 0: Cobalt Blue
  '#E11D48', // 1: Coral Rose
  '#059669', // 2: Emerald Green
  '#D97706', // 3: Amber Gold
  '#7C3AED', // 4: Violet Purple
  '#0891B2'  // 5: Ocean Teal
];

export function monogramTileBackground(colorIndex: number): string {
  const safeIndex: number = colorIndex >= 0 && colorIndex < MONOGRAM_PALETTE.length
    ? colorIndex
    : Math.abs(colorIndex) % MONOGRAM_PALETTE.length;
  return MONOGRAM_PALETTE[safeIndex];
}

/**
 * Matches a site's title or URL against known user intents, built-in features,
 * or ubiquitous web actions (Downloads, History, Bookmarks, Settings, etc.).
 * Returns a designated IconName and themed color scheme when matched.
 */
export function matchSemanticSiteIcon(title: string, url: string): SemanticSiteTheme | undefined {
  const normTitle: string = title.trim().toLowerCase();
  const normUrl: string = url.trim().toLowerCase();

  // 1. Download / Install
  if (normTitle.includes('下载') || normTitle.includes('download') || normTitle.includes('离线') ||
      normTitle.includes('安装包') || normTitle.includes('安装') || normUrl.includes('download') ||
      normUrl.includes('/apk') || normUrl.includes('/hap') || normUrl.includes('browser://downloads')) {
    return {
      icon: IconName.Download,
      background: '#1D4ED8',
      foreground: '#FFFFFF'
    };
  }

  // 2. History / Timeline / Recent
  if (normTitle.includes('历史') || normTitle.includes('history') || normTitle.includes('足迹') ||
      normTitle.includes('记录') || normUrl.includes('history') || normUrl.includes('browser://history')) {
    return {
      icon: IconName.Clock,
      background: '#EA580C',
      foreground: '#FFFFFF'
    };
  }

  // 3. Bookmarks / Favorites
  if (normTitle.includes('书签') || normTitle.includes('bookmark') || normTitle.includes('收藏') ||
      normTitle.includes('favorite') || normUrl.includes('bookmarks') || normUrl.includes('favorites')) {
    return {
      icon: IconName.Bookmark,
      background: '#D97706',
      foreground: '#FFFFFF'
    };
  }

  // 4. Settings / Preferences
  if (normTitle.includes('设置') || normTitle.includes('setting') || normTitle.includes('配置') ||
      normTitle.includes('选项') || normTitle.includes('preference') || normUrl.includes('settings')) {
    return {
      icon: IconName.Settings,
      background: '#475569',
      foreground: '#FFFFFF'
    };
  }

  // 5. Reader / Blog / Novel / Article
  if (normTitle.includes('阅读') || normTitle.includes('reader') || normTitle.includes('文章') ||
      normTitle.includes('博客') || normTitle.includes('blog') || normTitle.includes('小说') ||
      normUrl.includes('reader') || normUrl.includes('blog')) {
    return {
      icon: IconName.Reader,
      background: '#059669',
      foreground: '#FFFFFF'
    };
  }

  // 6. Search / Explore / Engine
  if (normTitle.includes('搜索') || normTitle.includes('search') || normTitle.includes('探索') ||
      normTitle.includes('发现') || normUrl.includes('search')) {
    return {
      icon: IconName.Search,
      background: '#0284C7',
      foreground: '#FFFFFF'
    };
  }

  // 7. Home / Portal / Navigation
  if (normTitle.includes('首页') || normTitle.includes('主页') || normTitle.includes('导航') ||
      normTitle.includes('portal') || normTitle === 'home' || normUrl === 'browser://home') {
    return {
      icon: IconName.Home,
      background: '#0D9488',
      foreground: '#FFFFFF'
    };
  }

  // 8. Privacy / Incognito / Security
  if (normTitle.includes('隐私') || normTitle.includes('无痕') || normTitle.includes('私密') ||
      normTitle.includes('安全') || normTitle.includes('incognito') || normTitle.includes('private')) {
    return {
      icon: IconName.Incognito,
      background: '#334155',
      foreground: '#FFFFFF'
    };
  }

  // 9. Share / Community
  if (normTitle.includes('分享') || normTitle.includes('社区') || normTitle.includes('share') ||
      normTitle.includes('community')) {
    return {
      icon: IconName.Share,
      background: '#7C3AED',
      foreground: '#FFFFFF'
    };
  }

  return undefined;
}
