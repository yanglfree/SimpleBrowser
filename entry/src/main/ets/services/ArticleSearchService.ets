import { SavedArticle } from '../models/ArticleLibraryModels';

export function normalizeArticleSearchTerms(query: string): string[] {
  return query.trim().toLocaleLowerCase().split(/\s+/).filter((term: string): boolean => term.length > 0);
}

export function articleMatchesSearch(article: SavedArticle, content: string, terms: string[]): boolean {
  if (terms.length === 0) {
    return true;
  }
  const haystack: string = [
    article.title,
    article.author,
    article.excerpt,
    article.canonicalUrl,
    article.tags.join(' '),
    content
  ].join('\n').toLocaleLowerCase();
  return terms.every((term: string): boolean => haystack.includes(term));
}
