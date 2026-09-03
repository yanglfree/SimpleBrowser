import { describe, expect, it } from '@ohos/hypium';
import { historyHeaderTopPadding, resolveHistoryEntryDeleteTarget } from '../main/ets/components/HistorySheet';
import { readerApplyScript } from '../main/ets/constants/AppConstants';
import { HistoryEntry, ReaderPaper, SavedItem, getReaderTheme } from '../main/ets/models/BrowserModels';
import {
  SCREENSHOT_CACHE_RETENTION_MS,
  buildLinkShareRecord,
  screenshotCacheFileName,
  shouldRemoveScreenshotCacheFile
} from '../main/ets/services/ShareService';

export default function browserReportedBugsTest(): void {
  describe('Reported browser regressions', (): void => {
    it('shares a hyperlink as content accepted by Share Kit', 0, (): void => {
      const record = buildLinkShareRecord('https://example.com/article', 'Article');

      expect(record.content).assertEqual('https://example.com/article');
      expect(record.uri).assertUndefined();
      expect(record.title).assertEqual('Article');
    });

    it('keeps screenshot cache files alive for the share target', 0, (): void => {
      const createdAt: number = 1_700_000_000_000;
      const name: string = screenshotCacheFileName(createdAt);

      expect(shouldRemoveScreenshotCacheFile(name, createdAt + SCREENSHOT_CACHE_RETENTION_MS - 1))
        .assertFalse();
      expect(shouldRemoveScreenshotCacheFile(name, createdAt + SCREENSHOT_CACHE_RETENTION_MS))
        .assertTrue();
      expect(shouldRemoveScreenshotCacheFile('unrelated.jpg', createdAt + SCREENSHOT_CACHE_RETENTION_MS))
        .assertFalse();
    });

    it('uses detached-node text fallbacks and keeps short lead paragraphs', 0, (): void => {
      const script: string = readerApplyScript(17, 205, '#fff', '#111', '#111', '#06f');

      expect(script.includes('node.innerText || node.textContent')).assertTrue();
      expect(script.includes('paragraphText.length < 24')).assertTrue();
      expect(script.includes('wrapper.className = \'__mb-reader-body\'')).assertTrue();
    });

    it('positions full-screen list headers below the real status bar inset', 0, (): void => {
      expect(historyHeaderTopPadding(0)).assertEqual(18);
      expect(historyHeaderTopPadding(34)).assertEqual(46);
      expect(historyHeaderTopPadding(-10)).assertEqual(18);
    });

    it('returns consistent reader theme color schemes for each paper type', 0, (): void => {
      const white = getReaderTheme(ReaderPaper.White);
      expect(white.background).assertEqual('#FFFFFF');
      expect(white.isDark).assertFalse();

      const sepia = getReaderTheme(ReaderPaper.Sepia);
      expect(sepia.background).assertEqual('#F1EFEA');
      expect(sepia.isDark).assertFalse();

      const night = getReaderTheme(ReaderPaper.Night);
      expect(night.background).assertEqual('#26251F');
      expect(night.isDark).assertTrue();
    });

    it('enables text selection and touch-callout in reader mode styles', 0, (): void => {
      const script: string = readerApplyScript(17, 205, '#fff', '#111', '#111', '#06f');

      expect(script.includes('user-select:text !important')).assertTrue();
      expect(script.includes('-webkit-user-select:text !important')).assertTrue();
      expect(script.includes('-webkit-touch-callout:default !important')).assertTrue();
      expect(script.includes('document.onselectstart = null')).assertTrue();
      expect(script.includes('document.oncopy = null')).assertTrue();
    });

    it('resolves history entry deletion target id for history and saved items', 0, (): void => {
      const historyEntry: HistoryEntry = {
        id: 'hist-123',
        title: 'Example',
        url: 'https://example.com',
        visitedAt: 1000,
        visitCount: 1
      };
      const savedItems: SavedItem[] = [
        {
          id: 'fav-456',
          title: 'Saved Example',
          url: 'https://example.com',
          createdAt: 500,
          updatedAt: 500,
          isRead: false,
          tags: []
        }
      ];

      expect(resolveHistoryEntryDeleteTarget(historyEntry, false, savedItems)).assertEqual('hist-123');
      expect(resolveHistoryEntryDeleteTarget(historyEntry, true, savedItems)).assertEqual('fav-456');

      const savedSearchEntry: HistoryEntry = {
        id: 'saved-search-fav-456',
        title: 'Saved Example',
        url: 'https://example.com',
        visitedAt: 500,
        visitCount: 0
      };
      expect(resolveHistoryEntryDeleteTarget(savedSearchEntry, false, savedItems)).assertEqual('fav-456');
    });
  });
}
