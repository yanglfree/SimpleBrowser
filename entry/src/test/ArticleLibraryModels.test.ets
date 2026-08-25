import { describe, expect, it } from '@ohos/hypium';
import {
  ArticleSaveFailure,
  isReadableSavedArticle,
  SavedArticle
} from '../main/ets/models/ArticleLibraryModels';

function articleWithFailure(failure: ArticleSaveFailure): SavedArticle {
  return {
    id: 'article-1',
    sourceUrl: 'https://example.com/original',
    canonicalUrl: 'https://example.com/story',
    title: 'A story',
    author: 'Author',
    excerpt: 'Excerpt',
    createdAt: 1,
    updatedAt: 1,
    readingPosition: 0,
    tags: [],
    isArchived: false,
    failure: failure,
    failureMessage: ''
  };
}

export default function articleLibraryModelsTest(): void {
  describe('Article library models', (): void => {
    it('opens only articles with locally readable content', 0, (): void => {
      expect(isReadableSavedArticle(articleWithFailure(ArticleSaveFailure.None))).assertTrue();
      expect(isReadableSavedArticle(articleWithFailure(ArticleSaveFailure.ExtractionUnavailable))).assertFalse();
      expect(isReadableSavedArticle(articleWithFailure(ArticleSaveFailure.StorageUnavailable))).assertFalse();
    });
  });
}
