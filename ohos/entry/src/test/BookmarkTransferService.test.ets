import { describe, expect, it } from '@ohos/hypium';
import { SavedItem } from '../main/ets/models/BrowserModels';
import { BookmarkTransferService } from '../main/ets/services/BookmarkTransferService';

export default function bookmarkTransferServiceTest(): void {
  describe('Bookmark transfer service', (): void => {
    it('imports valid unique links and preserves normalized tags', 0, (): void => {
      const html: string = [
        '<DL><p>',
        '<DT><A TAGS="alpha, beta,alpha" HREF="https://example.com/path?x=1&amp;y=2">One &amp; More</A>',
        '<DT><A HREF="https://example.com/path?x=1&amp;y=2">Duplicate</A>',
        '<DT><A HREF="javascript:alert(1)">Script</A>',
        '<DT><A HREF="file:///etc/passwd">File</A>',
        '<DT><A HREF="http://example.org/">Two</A>',
        '</DL><p>'
      ].join('\n');

      const items: SavedItem[] = BookmarkTransferService.parse(html);

      expect(items.length).assertEqual(2);
      expect(items[0].url).assertEqual('https://example.com/path?x=1&y=2');
      expect(items[0].title).assertEqual('One & More');
      expect(items[0].tags.join(',')).assertEqual('alpha,beta');
      expect(items[1].url).assertEqual('http://example.org/');
    });

    it('exports escaped bookmark fields and round-trips tags', 0, (): void => {
      const item: SavedItem = {
        id: 'saved-1',
        title: 'One & More',
        url: 'https://example.com/path?x=1&y=2',
        createdAt: 1,
        updatedAt: 1,
        isRead: true,
        tags: [' alpha ', 'beta', 'alpha', '']
      };

      const html: string = BookmarkTransferService.export([item]);
      const imported: SavedItem[] = BookmarkTransferService.parse(html);

      expect(html).assertContain('HREF="https://example.com/path?x=1&amp;y=2"');
      expect(html).assertContain('TAGS="alpha,beta"');
      expect(html).assertContain('>One &amp; More</A>');
      expect(imported.length).assertEqual(1);
      expect(imported[0].title).assertEqual(item.title);
      expect(imported[0].url).assertEqual(item.url);
      expect(imported[0].tags.join(',')).assertEqual('alpha,beta');
    });
  });
}
