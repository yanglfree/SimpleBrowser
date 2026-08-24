import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import relationalStore from '@ohos.data.relationalStore';
import {
  ArticleContent,
  ArticleSaveFailure,
  cloneSavedArticle,
  SavedArticle
} from '../models/ArticleLibraryModels';
import { Logger } from '../utils/Logger';

const TAG: string = 'ArticleLibraryRepository';
const DATABASE_NAME: string = 'zhuoyue_article_library.db';
const CONTENT_DIRECTORY: string = 'article-library';
const ARTICLE_TABLE: string = 'saved_article';
const CONTENT_TABLE: string = 'article_content';

export class ArticleLibraryRepository {
  private store: relationalStore.RdbStore | undefined;
  private filesDirectory: string = '';

  async initialize(context: common.UIAbilityContext): Promise<void> {
    if (this.store !== undefined) {
      return;
    }
    const config: relationalStore.StoreConfig = {
      name: DATABASE_NAME,
      securityLevel: relationalStore.SecurityLevel.S1
    };
    this.store = await relationalStore.getRdbStore(context, config);
    this.filesDirectory = `${context.filesDir}/${CONTENT_DIRECTORY}`;
    await fileIo.mkdir(this.filesDirectory, true);
    await this.createSchema(this.store);
  }

  async saveArticle(article: SavedArticle, html: string, markdown: string): Promise<ArticleContent> {
    const store: relationalStore.RdbStore = this.requireStore();
    const content: ArticleContent = await this.writeContent(article.id, html, markdown);
    const values: relationalStore.ValuesBucket = {
      id: article.id,
      source_url: article.sourceUrl,
      canonical_url: article.canonicalUrl,
      title: article.title,
      excerpt: article.excerpt,
      created_at: article.createdAt,
      updated_at: article.updatedAt,
      failure: article.failure,
      failure_message: article.failureMessage
    };
    const contentValues: relationalStore.ValuesBucket = {
      article_id: content.articleId,
      html_path: content.htmlPath,
      markdown_path: content.markdownPath,
      image_directory_path: content.imageDirectoryPath,
      extracted_at: content.extractedAt
    };
    await store.insert(ARTICLE_TABLE, values, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
    await store.insert(CONTENT_TABLE, contentValues, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
    return content;
  }

  async saveFailure(article: SavedArticle, failure: ArticleSaveFailure, message: string): Promise<void> {
    const store: relationalStore.RdbStore = this.requireStore();
    const values: relationalStore.ValuesBucket = {
      id: article.id,
      source_url: article.sourceUrl,
      canonical_url: article.canonicalUrl,
      title: article.title,
      excerpt: article.excerpt,
      created_at: article.createdAt,
      updated_at: Date.now(),
      failure: failure,
      failure_message: message
    };
    await store.insert(ARTICLE_TABLE, values, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
  }

  async readArticleHtml(articleId: string): Promise<string | undefined> {
    const store: relationalStore.RdbStore = this.requireStore();
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(CONTENT_TABLE);
    predicates.equalTo('article_id', articleId);
    const result: relationalStore.ResultSet = await store.query(predicates, ['html_path']);
    try {
      if (!result.goToFirstRow()) {
        return undefined;
      }
      return await fileIo.readText(result.getString(0));
    } finally {
      result.close();
    }
  }

  async listArticles(): Promise<SavedArticle[]> {
    const store: relationalStore.RdbStore = this.requireStore();
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(ARTICLE_TABLE);
    predicates.orderByDesc('updated_at');
    const result: relationalStore.ResultSet = await store.query(predicates);
    const articles: SavedArticle[] = [];
    try {
      while (result.goToNextRow()) {
        articles.push(cloneSavedArticle({
          id: result.getString(result.getColumnIndex('id')),
          sourceUrl: result.getString(result.getColumnIndex('source_url')),
          canonicalUrl: result.getString(result.getColumnIndex('canonical_url')),
          title: result.getString(result.getColumnIndex('title')),
          excerpt: result.getString(result.getColumnIndex('excerpt')),
          createdAt: result.getLong(result.getColumnIndex('created_at')),
          updatedAt: result.getLong(result.getColumnIndex('updated_at')),
          failure: result.getLong(result.getColumnIndex('failure')) as ArticleSaveFailure,
          failureMessage: result.getString(result.getColumnIndex('failure_message'))
        }));
      }
      return articles;
    } finally {
      result.close();
    }
  }

  private async createSchema(store: relationalStore.RdbStore): Promise<void> {
    await store.executeSql(`CREATE TABLE IF NOT EXISTS ${ARTICLE_TABLE} (
      id TEXT PRIMARY KEY, source_url TEXT NOT NULL, canonical_url TEXT NOT NULL,
      title TEXT NOT NULL, excerpt TEXT NOT NULL, created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL, failure INTEGER NOT NULL, failure_message TEXT NOT NULL
    )`);
    await store.executeSql(`CREATE TABLE IF NOT EXISTS ${CONTENT_TABLE} (
      article_id TEXT PRIMARY KEY, html_path TEXT NOT NULL, markdown_path TEXT NOT NULL,
      image_directory_path TEXT NOT NULL, extracted_at INTEGER NOT NULL
    )`);
    await store.executeSql(`CREATE TABLE IF NOT EXISTS article_note (
      id TEXT PRIMARY KEY, article_id TEXT NOT NULL, body TEXT NOT NULL,
      created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL
    )`);
    await store.executeSql(`CREATE TABLE IF NOT EXISTS article_highlight (
      id TEXT PRIMARY KEY, article_id TEXT NOT NULL, text_quote TEXT NOT NULL,
      prefix TEXT NOT NULL, suffix TEXT NOT NULL, dom_path TEXT NOT NULL,
      state INTEGER NOT NULL, created_at INTEGER NOT NULL
    )`);
    await store.executeSql(`CREATE TABLE IF NOT EXISTS topic (
      id TEXT PRIMARY KEY, name TEXT NOT NULL UNIQUE, created_at INTEGER NOT NULL
    )`);
    await store.executeSql(`CREATE TABLE IF NOT EXISTS article_topic (
      article_id TEXT NOT NULL, topic_id TEXT NOT NULL, PRIMARY KEY (article_id, topic_id)
    )`);
  }

  private async writeContent(articleId: string, html: string, markdown: string): Promise<ArticleContent> {
    const articleDirectory: string = `${this.filesDirectory}/${articleId}`;
    const imageDirectoryPath: string = `${articleDirectory}/images`;
    await fileIo.mkdir(imageDirectoryPath, true);
    const htmlPath: string = `${articleDirectory}/article.html`;
    const markdownPath: string = `${articleDirectory}/article.md`;
    await this.writeText(htmlPath, html);
    await this.writeText(markdownPath, markdown);
    return {
      articleId: articleId,
      htmlPath: htmlPath,
      markdownPath: markdownPath,
      imageDirectoryPath: imageDirectoryPath,
      extractedAt: Date.now()
    };
  }

  private async writeText(path: string, content: string): Promise<void> {
    const fd: number = await fileIo.open(path, fileIo.OpenMode.READ_WRITE |
      fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    try {
      await fileIo.write(fd, content);
    } finally {
      await fileIo.close(fd);
    }
  }

  private requireStore(): relationalStore.RdbStore {
    if (this.store === undefined) {
      Logger.error(TAG, 'Article library was used before initialization');
      throw new Error('Article library is not initialized');
    }
    return this.store;
  }
}
