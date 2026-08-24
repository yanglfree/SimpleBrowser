import { describe, expect, it } from '@ohos/hypium';
import { ArticleHighlight, ArticleHighlightState } from '../main/ets/models/ArticleLibraryModels';
import { restoreArticleHighlight } from '../main/ets/services/ArticleHighlightLocator';

const HIGHLIGHT: ArticleHighlight = {
  id: 'highlight-1', articleId: 'article-1', textQuote: 'focus text', prefix: 'before ', suffix: ' after',
  domPath: 'main > p:nth-child(2)', state: ArticleHighlightState.Located, createdAt: 1
};

export default function articleHighlightLocatorTest(): void {
  describe('Article highlight locator', (): void => {
    it('keeps an anchor located when its quote and context match', 0, (): void => {
      const restored: ArticleHighlight = restoreArticleHighlight(HIGHLIGHT, 'before focus text after');
      expect(restored.state).assertEqual(ArticleHighlightState.Located);
    });

    it('marks an anchor for relocation when surrounding context changes', 0, (): void => {
      const restored: ArticleHighlight = restoreArticleHighlight(HIGHLIGHT, 'changed focus text after');
      expect(restored.state).assertEqual(ArticleHighlightState.NeedsRelocation);
    });
  });
}
