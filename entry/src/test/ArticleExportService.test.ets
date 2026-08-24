import { describe, expect, it } from '@ohos/hypium';
import { ArticleSaveFailure, SavedArticle } from '../main/ets/models/ArticleLibraryModels';
import { ArticleExportService } from '../main/ets/services/ArticleExportService';

const ARTICLE: SavedArticle = {
  id: 'article-1',
  sourceUrl: 'https://example.com/original',
  canonicalUrl: 'https://example.com/story',
  title: 'A story',
  excerpt: 'Excerpt',
  createdAt: 1,
  updatedAt: 1,
  failure: ArticleSaveFailure.None,
  failureMessage: ''
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
      expect(html).assertNotContain('track()');
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
  });
}
