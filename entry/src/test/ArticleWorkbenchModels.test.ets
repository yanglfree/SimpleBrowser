import { describe, expect, it } from '@ohos/hypium';
import {
  ARTICLE_WORKBENCH_READER_MAX_WIDTH,
  ArticleWorkbenchMode,
  articleReaderMaxWidth,
  articleWorkbenchMode,
  articleWorkbenchOverlayWidth,
  shouldShowArticleInspector
} from '../main/ets/models/ArticleWorkbenchModels';
import { BrowserLayoutClass } from '../main/ets/models/WindowMetrics';

export default function articleWorkbenchModelsTest(): void {
  describe('Article workbench layout', (): void => {
    it('uses the requested breakpoints for the inspector', 0, (): void => {
      expect(articleWorkbenchMode(BrowserLayoutClass.Compact)).assertEqual(ArticleWorkbenchMode.Compact);
      expect(articleWorkbenchMode(BrowserLayoutClass.Medium))
        .assertEqual(ArticleWorkbenchMode.SwitchableInspector);
      expect(articleWorkbenchMode(BrowserLayoutClass.Expanded))
        .assertEqual(ArticleWorkbenchMode.FixedInspector);
      expect(shouldShowArticleInspector(BrowserLayoutClass.Medium, false)).assertFalse();
      expect(shouldShowArticleInspector(BrowserLayoutClass.Medium, true)).assertTrue();
      expect(shouldShowArticleInspector(BrowserLayoutClass.Expanded, false)).assertTrue();
    });

    it('caps the reader measure while reserving a fixed inspector', 0, (): void => {
      expect(articleReaderMaxWidth(1400, true)).assertEqual(ARTICLE_WORKBENCH_READER_MAX_WIDTH);
      expect(articleReaderMaxWidth(1060, true)).assertEqual(692);
      expect(articleReaderMaxWidth(840, true)).assertEqual(472);
      expect(articleWorkbenchOverlayWidth(840)).assertEqual(816);
      expect(articleWorkbenchOverlayWidth(1600)).assertEqual(1180);
    });
  });
}
