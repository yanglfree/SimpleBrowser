import { describe, expect, it } from '@ohos/hypium';
import {
  parseReaderExtractionReport,
  readerExtractionBuckets
} from '../main/ets/models/ReaderExtractionModels';

export default function readerExtractionModelsTest(): void {
  describe('Reader extraction quality models', (): void => {
    it('parses quality metrics returned by ArkWeb', 0, (): void => {
      const report = parseReaderExtractionReport(JSON.stringify({
        status: 'reader', result: 'partial', strategy: 'paragraph_fallback',
        candidateChars: 6400, outputChars: 5900, retainedRatio: 0.92,
        paragraphCount: 68, imageCount: 4, durationMs: 37
      }));

      expect(report.result).assertEqual('partial');
      expect(report.strategy).assertEqual('paragraph_fallback');
      expect(report.outputChars).assertEqual(5900);
      expect(report.paragraphCount).assertEqual(68);
    });

    it('coarsens metrics before telemetry', 0, (): void => {
      const report = parseReaderExtractionReport(JSON.stringify({
        status: 'reader', result: 'complete', strategy: 'heuristic',
        candidateChars: 6400, retainedRatio: 0.92, paragraphCount: 68
      }));
      const buckets = readerExtractionBuckets(report);

      expect(buckets.candidateChars).assertEqual('5000-9999');
      expect(buckets.outputRatio).assertEqual('90-100');
      expect(buckets.paragraphs).assertEqual('50-99');
    });
  });
}
