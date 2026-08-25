import { describe, expect, it } from '@ohos/hypium';
import {
  ArticleHighlightState,
  ArticleSaveFailure,
  SavedArticle
} from '../main/ets/models/ArticleLibraryModels';
import { ArticleExportExtras, ArticleExportService } from '../main/ets/services/ArticleExportService';

const ARTICLE: SavedArticle = {
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
  failure: ArticleSaveFailure.None,
  failureMessage: ''
};

const EXTRAS: ArticleExportExtras = {
  notes: [{ id: 'note-1', articleId: 'article-1', body: 'Remember this.', createdAt: 1, updatedAt: 1 }],
  topics: [{ id: 'topic-1', name: 'Research', createdAt: 1 }],
  highlights: [{
    id: 'highlight-1', articleId: 'article-1', textQuote: 'Important passage', prefix: '', suffix: '',
    domPath: 'main > p', state: ArticleHighlightState.Located, createdAt: 1
  }],
  imageFailedCount: 2
};

export default function articleExportServiceTest(): void {
  describe('Article export service', (): void => {
    it('creates a Markdown document with the canonical source', 0, (): void => {
      const markdown: string = ArticleExportService.markdownDocument(ARTICLE, 'Saved article body');
      expect(markdown).assertContain('# A story');
      expect(markdown).assertContain('Source: https://example.com/story');
      expect(markdown).assertContain('Saved article body');
    });

    it('creates a standalone HTML shell around extracted content', 0, (): void => {
      const html: string = ArticleExportService.standaloneHtmlDocument(ARTICLE, '<main>Saved article body</main>');
      expect(html).assertContain('<!doctype html>');
      expect(html).assertContain('<base href="https://example.com/story">');
      expect(html).assertContain('<main>Saved article body</main>');
    });

    it('strips scripts from exported HTML fragments', 0, (): void => {
      const html: string = ArticleExportService.standaloneHtmlDocument(ARTICLE, '<script>track()</script><p>Readable</p>');
      expect(html.includes('track()')).assertFalse();
      expect(html).assertContain('<p>Readable</p>');
    });

    it('keeps full extracted documents standalone with a canonical base URL', 0, (): void => {
      const html: string = ArticleExportService.standaloneHtmlDocument(
        ARTICLE,
        '<html><head></head><body><img src="image.jpg"></body></html>'
      );
      expect(html).assertContain('<!doctype html>');
      expect(html).assertContain('<base href="https://example.com/story">');
    });

    it('keeps local image references eligible for standalone embedding', 0, (): void => {
      const html: string = ArticleExportService.standaloneHtmlDocument(
        ARTICLE,
        '<img src="images/image-0.webp">'
      );
      expect(html).assertContain('images/image-0.webp');
    });

    it('includes annotations and image degradation details in both formats', 0, (): void => {
      const markdown: string = ArticleExportService.markdownDocument(ARTICLE, 'Body', EXTRAS);
      const html: string = ArticleExportService.standaloneHtmlDocument(ARTICLE, '<p>Body</p>', EXTRAS);

      expect(markdown).assertContain('Remember this.');
      expect(markdown).assertContain('Important passage');
      expect(markdown).assertContain('2 image(s)');
      expect(html).assertContain('data-zhuoyue-annotations');
      expect(html).assertContain('Remember this.');
      expect(html).assertContain('2 image(s)');
    });
  });
}
