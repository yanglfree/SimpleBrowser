import { describe, expect, it } from '@ohos/hypium';
import { articleCaptureReadable, parseArticleCapture } from '../main/ets/models/ArticleCaptureModels';

export default function articleCaptureModelsTest(): void {
  describe('Article capture transport', (): void => {
    const raw: string = '{"title":"Title","canonicalUrl":"https://example.com/article",' +
      '"html":"<p>Body</p>","text":"Body","markdown":"Body","images":[],' +
      '"readerMetrics":{"result":"complete"}}';
    it('parses a browser fixture object', 0, (): void => {
      expect(parseArticleCapture(raw).title).assertEqual('Title');
      expect(articleCaptureReadable(parseArticleCapture(raw))).assertTrue();
    });
    it('unwraps the ArkWeb string transport before reading fields', 0, (): void => {
      expect(parseArticleCapture(JSON.stringify(raw)).canonicalUrl).assertEqual('https://example.com/article');
    });
    it('keeps unavailable extraction distinct from saved content', 0, (): void => {
      expect(articleCaptureReadable(parseArticleCapture(raw.replace('complete', 'unavailable')))).assertFalse();
    });
  });
}
