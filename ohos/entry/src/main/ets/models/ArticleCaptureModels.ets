import { ArticleImageAsset, ArticleSaveFailure } from './ArticleLibraryModels';

export interface ArticleCaptureSnapshot {
  title: string;
  author: string;
  canonicalUrl: string;
  sourceUrl: string;
  html: string;
  text: string;
  markdown: string;
  images: ArticleImageAsset[];
  quality: string;
}

interface ArticleCaptureWire {
  title?: string;
  author?: string;
  canonicalUrl?: string;
  sourceUrl?: string;
  html?: string;
  text?: string;
  markdown?: string;
  images?: ArticleImageAsset[];
  readerMetrics?: ArticleCaptureMetrics;
}

interface ArticleCaptureMetrics {
  result?: string;
}

export interface ArticleSaveResult {
  articleId: string;
  failure: ArticleSaveFailure;
  partial: boolean;
  preserved: boolean;
  imageSavedCount: number;
  imageFailedCount: number;
}

/** ArkWeb encodes string results; browser fixtures may return an unwrapped object string. */
export function decodeArticleScriptResult(raw: string): string {
  const decoded: Object = JSON.parse(raw) as Object;
  return typeof decoded === 'string' ? String(decoded) : raw;
}

export function parseArticleCapture(raw: string): ArticleCaptureSnapshot {
  const wire: ArticleCaptureWire = JSON.parse(decodeArticleScriptResult(raw)) as ArticleCaptureWire;
  if (wire === null || typeof wire !== 'object' || typeof wire.html !== 'string' ||
    typeof wire.text !== 'string' || typeof wire.markdown !== 'string' ||
    typeof wire.canonicalUrl !== 'string') {
    throw new Error('Invalid article capture response');
  }
  return {
    title: typeof wire.title === 'string' ? wire.title : '',
    author: typeof wire.author === 'string' ? wire.author : '',
    canonicalUrl: wire.canonicalUrl,
    sourceUrl: typeof wire.sourceUrl === 'string' ? wire.sourceUrl : wire.canonicalUrl,
    html: wire.html, text: wire.text, markdown: wire.markdown,
    images: Array.isArray(wire.images) ? wire.images : [],
    quality: wire.readerMetrics?.result ?? 'partial'
  };
}

export function articleCaptureReadable(snapshot: ArticleCaptureSnapshot): boolean {
  return snapshot.quality !== 'unavailable' && snapshot.html.trim().length > 0 &&
    snapshot.text.trim().length > 0 && snapshot.markdown.trim().length > 0;
}
