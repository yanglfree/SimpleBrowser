export enum ArticleSaveFailure {
  None = 0,
  ExtractionUnavailable = 1,
  StorageUnavailable = 2
}

export enum ArticleHighlightState {
  Located = 0,
  NeedsRelocation = 1
}

export interface SavedArticle {
  id: string;
  sourceUrl: string;
  canonicalUrl: string;
  title: string;
  author: string;
  excerpt: string;
  createdAt: number;
  updatedAt: number;
  readingPosition: number;
  tags: string[];
  isArchived: boolean;
  failure: ArticleSaveFailure;
  failureMessage: string;
}

export interface ArticleContent {
  articleId: string;
  htmlPath: string;
  markdownPath: string;
  imageDirectoryPath: string;
  extractedAt: number;
  imageSavedCount: number;
  imageFailedCount: number;
}

export interface ArticleImageAsset {
  index: number;
  url: string;
  fileName: string;
}

export interface ArticleNote {
  id: string;
  articleId: string;
  body: string;
  createdAt: number;
  updatedAt: number;
}

export interface ArticleHighlight {
  id: string;
  articleId: string;
  textQuote: string;
  prefix: string;
  suffix: string;
  domPath: string;
  state: ArticleHighlightState;
  createdAt: number;
}

export interface Topic {
  id: string;
  name: string;
  createdAt: number;
}

export function createArticleId(now: number = Date.now()): string {
  return `article-${now}-${Math.floor(Math.random() * 1000000)}`;
}

export function createArticleRecordId(prefix: string, now: number = Date.now()): string {
  return `${prefix}-${now}-${Math.floor(Math.random() * 1000000)}`;
}

export function cloneSavedArticle(article: SavedArticle): SavedArticle {
  return {
    id: article.id,
    sourceUrl: article.sourceUrl,
    canonicalUrl: article.canonicalUrl,
    title: article.title,
    author: article.author,
    excerpt: article.excerpt,
    createdAt: article.createdAt,
    updatedAt: article.updatedAt,
    readingPosition: article.readingPosition,
    tags: article.tags.slice(0),
    isArchived: article.isArchived,
    failure: article.failure,
    failureMessage: article.failureMessage
  };
}

export function isReadableSavedArticle(article: SavedArticle): boolean {
  return article.failure === ArticleSaveFailure.None;
}

export function shouldRecordArticleSaveFailure(existing: SavedArticle | undefined): boolean {
  return existing === undefined || !isReadableSavedArticle(existing);
}

export function cloneArticleNote(note: ArticleNote): ArticleNote {
  return {
    id: note.id,
    articleId: note.articleId,
    body: note.body,
    createdAt: note.createdAt,
    updatedAt: note.updatedAt
  };
}

export function cloneArticleHighlight(highlight: ArticleHighlight): ArticleHighlight {
  return {
    id: highlight.id,
    articleId: highlight.articleId,
    textQuote: highlight.textQuote,
    prefix: highlight.prefix,
    suffix: highlight.suffix,
    domPath: highlight.domPath,
    state: highlight.state,
    createdAt: highlight.createdAt
  };
}

export function cloneTopic(topic: Topic): Topic {
  return { id: topic.id, name: topic.name, createdAt: topic.createdAt };
}
