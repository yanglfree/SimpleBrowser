import { ArticleHighlight, ArticleHighlightState, cloneArticleHighlight } from '../models/ArticleLibraryModels';

export function restoreArticleHighlight(highlight: ArticleHighlight, text: string): ArticleHighlight {
  const restored: ArticleHighlight = cloneArticleHighlight(highlight);
  if (highlight.textQuote.length === 0) {
    restored.state = ArticleHighlightState.NeedsRelocation;
    return restored;
  }
  let offset: number = text.indexOf(highlight.textQuote);
  while (offset >= 0) {
    const before: string = text.substring(Math.max(0, offset - highlight.prefix.length), offset);
    const after: string = text.substring(offset + highlight.textQuote.length,
      offset + highlight.textQuote.length + highlight.suffix.length);
    if (before === highlight.prefix && after === highlight.suffix) {
      restored.state = ArticleHighlightState.Located;
      return restored;
    }
    offset = text.indexOf(highlight.textQuote, offset + highlight.textQuote.length);
  }
  restored.state = ArticleHighlightState.NeedsRelocation;
  return restored;
}
