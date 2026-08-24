import { describe, expect, it } from '@ohos/hypium';
import { createArticleHighlight } from '../main/ets/services/ArticleHighlightFactory';

export default function articleHighlightFactoryTest(): void {
  describe('Article highlight factory', (): void => {
    it('stores a quote with surrounding text and a renderer path', 0, (): void => {
      const highlight = createArticleHighlight('article-1', 'Before selected text after.', 'selected text', 'main > p');
      expect(highlight === undefined).assertFalse();
      if (highlight !== undefined) {
        expect(highlight.prefix).assertEqual('Before ');
        expect(highlight.suffix).assertEqual(' after.');
        expect(highlight.domPath).assertEqual('main > p');
      }
    });

    it('does not create an anchor for text outside the saved article', 0, (): void => {
      expect(createArticleHighlight('article-1', 'Saved text', 'Missing')).assertUndefined();
    });
  });
}
