import { SavedArticle } from '../models/ArticleLibraryModels';

export function normalizeArticleSearchTerms(query: string): string[] {
  return query.trim().toLocaleLowerCase().split(/\s+/).filter((term: string): boolean => term.length > 0);
}

export function articleMatchesSearch(article: SavedArticle, content: string, terms: string[]): boolean {
  if (terms.length === 0) {
    return true;
  }
  const haystack: string = `${article.title}\n${article.excerpt}\n${article.canonicalUrl}\n${content}`.toLocaleLowerCase();
  return terms.every((term: string): boolean => haystack.includes(term));
}
