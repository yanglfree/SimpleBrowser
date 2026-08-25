import { describe, expect, it } from '@ohos/hypium';
import { historyHeaderTopPadding } from '../main/ets/components/HistorySheet';
import { readerApplyScript } from '../main/ets/constants/AppConstants';
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

      expect(script.includes('probe.innerText || probe.textContent')).assertTrue();
      expect(script.includes('paragraphText.length < 24')).assertTrue();
      expect(script.includes('wrapper.innerText || wrapper.textContent')).assertTrue();
    });

    it('positions full-screen list headers below the real status bar inset', 0, (): void => {
      expect(historyHeaderTopPadding(0)).assertEqual(18);
      expect(historyHeaderTopPadding(34)).assertEqual(46);
      expect(historyHeaderTopPadding(-10)).assertEqual(18);
    });
  });
}
