import {
  ArticleHighlight,
  ArticleHighlightState,
  createArticleRecordId
} from '../models/ArticleLibraryModels';

const CONTEXT_LENGTH: number = 48;

/** Creates a resilient text-quote anchor from a selected excerpt in saved article text. */
export function createArticleHighlight(
  articleId: string,
  articleText: string,
  selectedText: string,
  domPath: string = 'offline-markdown'
): ArticleHighlight | undefined {
  const quote: string = selectedText.trim();
  if (quote.length === 0) {
    return undefined;
  }
  const offset: number = articleText.indexOf(quote);
  if (offset < 0) {
    return undefined;
  }
  const now: number = Date.now();
  return {
    id: createArticleRecordId('highlight', now),
    articleId: articleId,
    textQuote: quote,
    prefix: articleText.substring(Math.max(0, offset - CONTEXT_LENGTH), offset),
    suffix: articleText.substring(offset + quote.length, offset + quote.length + CONTEXT_LENGTH),
    domPath: domPath,
    state: ArticleHighlightState.Located,
    createdAt: now
  };
}
