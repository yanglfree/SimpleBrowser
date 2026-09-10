import { describe, expect, it } from '@ohos/hypium';
import { IconName } from '../main/ets/components/AppIcon';
import {
  matchSemanticSiteIcon,
  monogramTileBackground,
  MONOGRAM_PALETTE,
  SemanticSiteTheme
} from '../main/ets/components/QuickSiteSemantic';
import { siteBadge } from '../main/ets/utils/UrlUtils';

export default function quickSiteSemanticTest(): void {
  describe('QuickSiteSemantic matching and monogram palette', (): void => {
    it('matches download intents and returns Download icon theme', 0, (): void => {
      const byTitle: SemanticSiteTheme | undefined = matchSemanticSiteIcon('下载页', 'https://example.com');
      expect(byTitle !== undefined).assertTrue();
      expect(byTitle?.icon).assertEqual(IconName.Download);

      const byEnglishTitle: SemanticSiteTheme | undefined = matchSemanticSiteIcon('Downloads', 'https://example.com');
      expect(byEnglishTitle !== undefined).assertTrue();
      expect(byEnglishTitle?.icon).assertEqual(IconName.Download);

      const byUrl: SemanticSiteTheme | undefined = matchSemanticSiteIcon('Custom Tool', 'browser://downloads');
      expect(byUrl !== undefined).assertTrue();
      expect(byUrl?.icon).assertEqual(IconName.Download);
    });

    it('matches history, bookmarks, and settings intents', 0, (): void => {
      const history: SemanticSiteTheme | undefined = matchSemanticSiteIcon('历史记录', 'https://example.com');
      expect(history !== undefined).assertTrue();
      expect(history?.icon).assertEqual(IconName.Clock);

      const bookmarks: SemanticSiteTheme | undefined = matchSemanticSiteIcon('我的书签', 'https://example.com');
      expect(bookmarks !== undefined).assertTrue();
      expect(bookmarks?.icon).assertEqual(IconName.Bookmark);

      const settings: SemanticSiteTheme | undefined = matchSemanticSiteIcon('系统设置', 'https://example.com');
      expect(settings !== undefined).assertTrue();
      expect(settings?.icon).assertEqual(IconName.Settings);
    });

    it('matches reader, search, home, and privacy intents', 0, (): void => {
      const reader: SemanticSiteTheme | undefined = matchSemanticSiteIcon('科技博客', 'https://example.com');
      expect(reader !== undefined).assertTrue();
      expect(reader?.icon).assertEqual(IconName.Reader);

      const search: SemanticSiteTheme | undefined = matchSemanticSiteIcon('全网搜索', 'https://example.com');
      expect(search !== undefined).assertTrue();
      expect(search?.icon).assertEqual(IconName.Search);

      const home: SemanticSiteTheme | undefined = matchSemanticSiteIcon('导航首页', 'https://example.com');
      expect(home !== undefined).assertTrue();
      expect(home?.icon).assertEqual(IconName.Home);

      const incognito: SemanticSiteTheme | undefined = matchSemanticSiteIcon('无痕模式', 'https://example.com');
      expect(incognito !== undefined).assertTrue();
      expect(incognito?.icon).assertEqual(IconName.Incognito);
    });

    it('returns undefined for normal sites without semantic keywords', 0, (): void => {
      expect(matchSemanticSiteIcon('知乎', 'https://www.zhihu.com')).assertUndefined();
      expect(matchSemanticSiteIcon('V2EX', 'https://v2ex.com')).assertUndefined();
      expect(matchSemanticSiteIcon('GitHub', 'https://github.com')).assertUndefined();
    });

    it('returns stable vibrant color from monogram palette', 0, (): void => {
      expect(monogramTileBackground(0)).assertEqual(MONOGRAM_PALETTE[0]);
      expect(monogramTileBackground(1)).assertEqual(MONOGRAM_PALETTE[1]);
      expect(monogramTileBackground(5)).assertEqual(MONOGRAM_PALETTE[5]);
      // Wraps out-of-range index safely
      expect(monogramTileBackground(6)).assertEqual(MONOGRAM_PALETTE[0]);
    });

    it('extracts clean first character in siteBadge', 0, (): void => {
      expect(siteBadge('知乎', 'https://zhihu.com')).assertEqual('知');
      expect(siteBadge('github', 'https://github.com')).assertEqual('G');
      expect(siteBadge('【推荐】少数派', 'https://sspai.com')).assertEqual('少');
      expect(siteBadge('[官方] 豆瓣', 'https://douban.com')).assertEqual('豆');
      expect(siteBadge('', 'https://example.com')).assertEqual('E');
    });
  });
}
