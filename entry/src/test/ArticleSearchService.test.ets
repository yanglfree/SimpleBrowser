import { describe, expect, it } from '@ohos/hypium';
import { ArticleSaveFailure, SavedArticle } from '../main/ets/models/ArticleLibraryModels';
import { articleMatchesSearch, normalizeArticleSearchTerms } from '../main/ets/services/ArticleSearchService';

const ARTICLE: SavedArticle = {
  id: 'article-1', sourceUrl: 'https://example.com/original', canonicalUrl: 'https://example.com/story',
  title: 'Local reader', author: 'Author', excerpt: 'A quiet reading workspace', createdAt: 1, updatedAt: 1,
  readingPosition: 0, tags: ['research'], isArchived: false,
  failure: ArticleSaveFailure.None, failureMessage: ''
};

export default function articleSearchServiceTest(): void {
  describe('Article search service', (): void => {
    it('matches every term against local metadata and content', 0, (): void => {
      const terms: string[] = normalizeArticleSearchTerms('reader offline');
      expect(articleMatchesSearch(ARTICLE, 'Offline body is available after restart.', terms)).assertTrue();
    });

    it('does not match when one search term is absent', 0, (): void => {
      const terms: string[] = normalizeArticleSearchTerms('reader missing');
      expect(articleMatchesSearch(ARTICLE, 'Offline body is available after restart.', terms)).assertFalse();
    });
  });
}
