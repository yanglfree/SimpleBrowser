export interface ReaderExtractionReport {
  result: string;
  strategy: string;
  candidateChars: number;
  outputChars: number;
  retainedRatio: number;
  paragraphCount: number;
  imageCount: number;
  durationMs: number;
}

interface ReaderExtractionWire {
  status?: string;
  result?: string;
  strategy?: string;
  candidateChars?: number;
  outputChars?: number;
  retainedRatio?: number;
  paragraphCount?: number;
  imageCount?: number;
  durationMs?: number;
}

export interface ReaderExtractionBuckets {
  candidateChars: string;
  outputRatio: string;
  paragraphs: string;
}

export function unavailableReaderExtraction(): ReaderExtractionReport {
  return {
    result: 'unavailable',
    strategy: 'none',
    candidateChars: 0,
    outputChars: 0,
    retainedRatio: 0,
    paragraphCount: 0,
    imageCount: 0,
    durationMs: 0
  };
}

export function parseReaderExtractionReport(raw: string): ReaderExtractionReport {
  let value: string = raw.trim();
  if (value === 'reader' || value === '"reader"') {
    const legacy: ReaderExtractionReport = unavailableReaderExtraction();
    legacy.result = 'complete';
    legacy.strategy = 'unknown';
    return legacy;
  }
  if (value.length === 0 || value === 'no-article' || value === '"no-article"') {
    return unavailableReaderExtraction();
  }
  try {
    const decoded: string = JSON.parse(value) as string;
    if (typeof decoded === 'string') {
      value = decoded;
    }
  } catch (error) {
    // ArkWeb may already return the unwrapped object string.
  }
  try {
    const parsed: ReaderExtractionWire = JSON.parse(value) as ReaderExtractionWire;
    const report: ReaderExtractionReport = unavailableReaderExtraction();
    report.result = normalizeResult(parsed.result, parsed.status);
    report.strategy = normalizeStrategy(parsed.strategy);
    report.candidateChars = safeCount(parsed.candidateChars);
    report.outputChars = safeCount(parsed.outputChars);
    report.retainedRatio = safeRatio(parsed.retainedRatio);
    report.paragraphCount = safeCount(parsed.paragraphCount);
    report.imageCount = safeCount(parsed.imageCount);
    report.durationMs = safeCount(parsed.durationMs);
    return report;
  } catch (error) {
    return unavailableReaderExtraction();
  }
}

export function readerExtractionBuckets(report: ReaderExtractionReport): ReaderExtractionBuckets {
  return {
    candidateChars: countBucket(report.candidateChars, [240, 1000, 5000, 10000],
      ['0-239', '240-999', '1000-4999', '5000-9999', '10000+']),
    outputRatio: countBucket(Math.round(report.retainedRatio * 100), [50, 70, 90, 101],
      ['0-49', '50-69', '70-89', '90-100', '100+']),
    paragraphs: countBucket(report.paragraphCount, [1, 5, 20, 50, 100],
      ['0', '1-4', '5-19', '20-49', '50-99', '100+'])
  };
}

function normalizeResult(result: string | undefined, status: string | undefined): string {
  if (result === 'complete' || result === 'partial' || result === 'unavailable') {
    return result;
  }
  return status === 'reader' ? 'complete' : 'unavailable';
}

function normalizeStrategy(strategy: string | undefined): string {
  if (strategy === 'site_adapter' || strategy === 'heuristic' || strategy === 'paragraph_fallback' ||
    strategy === 'none' || strategy === 'unknown') {
    return strategy;
  }
  return 'unknown';
}

function safeCount(value: number | undefined): number {
  return value !== undefined && Number.isFinite(value) && value > 0 ? Math.round(value) : 0;
}

function safeRatio(value: number | undefined): number {
  return value !== undefined && Number.isFinite(value) ? Math.min(1, Math.max(0, value)) : 0;
}

function countBucket(value: number, thresholds: number[], labels: string[]): string {
  for (let index: number = 0; index < thresholds.length; index++) {
    if (value < thresholds[index]) {
      return labels[index];
    }
  }
  return labels[labels.length - 1];
}
