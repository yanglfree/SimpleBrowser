import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import relationalStore from '@ohos.data.relationalStore';
import {
  ArticleContent,
  ArticleHighlight,
  ArticleHighlightState,
  ArticleImageAsset,
  ArticleSaveFailure,
  ArticleNote,
  Topic,
  cloneArticleHighlight,
  cloneArticleNote,
  cloneSavedArticle,
  cloneTopic,
  createArticleRecordId,
  SavedArticle
} from '../models/ArticleLibraryModels';
import { restoreArticleHighlight } from '../services/ArticleHighlightLocator';
import { articleMatchesSearch, normalizeArticleSearchTerms } from '../services/ArticleSearchService';
import { ArticleImageStore, ArticleImageStoreResult } from '../services/ArticleImageStore';
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
    await this.migrateSchema(this.store);
  }

  async saveArticle(
    article: SavedArticle,
    html: string,
    markdown: string,
    images: ArticleImageAsset[] = []
  ): Promise<ArticleContent> {
    const store: relationalStore.RdbStore = this.requireStore();
    const content: ArticleContent = await this.writeContent(article.id, html, markdown, images);
    const values: relationalStore.ValuesBucket = {
      id: article.id,
      source_url: article.sourceUrl,
      canonical_url: article.canonicalUrl,
      title: article.title,
      author: article.author,
      excerpt: article.excerpt,
      created_at: article.createdAt,
      updated_at: article.updatedAt,
      reading_position: article.readingPosition,
      tags_json: JSON.stringify(article.tags),
      is_archived: article.isArchived ? 1 : 0,
      failure: article.failure,
      failure_message: article.failureMessage
    };
    const contentValues: relationalStore.ValuesBucket = {
      article_id: content.articleId,
      html_path: content.htmlPath,
      markdown_path: content.markdownPath,
      image_directory_path: content.imageDirectoryPath,
      extracted_at: content.extractedAt,
      image_saved_count: content.imageSavedCount,
      image_failed_count: content.imageFailedCount
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
      author: article.author,
      excerpt: article.excerpt,
      created_at: article.createdAt,
      updated_at: Date.now(),
      reading_position: article.readingPosition,
      tags_json: JSON.stringify(article.tags),
      is_archived: article.isArchived ? 1 : 0,
      failure: failure,
      failure_message: message
    };
    await store.insert(ARTICLE_TABLE, values, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
  }

  async readArticleHtml(articleId: string): Promise<string | undefined> {
    const content: ArticleContent | undefined = await this.getArticleContent(articleId);
    return content === undefined ? undefined : await fileIo.readText(content.htmlPath);
  }

  async readArticleMarkdown(articleId: string): Promise<string | undefined> {
    const content: ArticleContent | undefined = await this.getArticleContent(articleId);
    return content === undefined ? undefined : await fileIo.readText(content.markdownPath);
  }

  async getArticle(articleId: string): Promise<SavedArticle | undefined> {
    const store: relationalStore.RdbStore = this.requireStore();
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(ARTICLE_TABLE);
    predicates.equalTo('id', articleId);
    const result: relationalStore.ResultSet = await store.query(predicates);
    try {
      return result.goToFirstRow() ? this.readSavedArticle(result) : undefined;
    } finally {
      result.close();
    }
  }

  async findArticleByCanonicalUrl(canonicalUrl: string): Promise<SavedArticle | undefined> {
    const store: relationalStore.RdbStore = this.requireStore();
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(ARTICLE_TABLE);
    predicates.equalTo('canonical_url', canonicalUrl);
    const result: relationalStore.ResultSet = await store.query(predicates);
    try {
      return result.goToFirstRow() ? this.readSavedArticle(result) : undefined;
    } finally {
      result.close();
    }
  }

  async findArticleBySourceUrl(sourceUrl: string): Promise<SavedArticle | undefined> {
    const store: relationalStore.RdbStore = this.requireStore();
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(ARTICLE_TABLE);
    predicates.equalTo('source_url', sourceUrl);
    const result: relationalStore.ResultSet = await store.query(predicates);
    try {
      return result.goToFirstRow() ? this.readSavedArticle(result) : undefined;
    } finally {
      result.close();
    }
  }

  async updateReadingPosition(articleId: string, readingPosition: number): Promise<void> {
    const store: relationalStore.RdbStore = this.requireStore();
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(ARTICLE_TABLE);
    predicates.equalTo('id', articleId);
    await store.update({
      reading_position: Math.max(0, readingPosition),
      updated_at: Date.now()
    }, predicates);
  }

  async updateTags(articleId: string, tags: string[]): Promise<void> {
    const store: relationalStore.RdbStore = this.requireStore();
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(ARTICLE_TABLE);
    predicates.equalTo('id', articleId);
    await store.update({ tags_json: JSON.stringify(tags), updated_at: Date.now() }, predicates);
  }

  async setArchived(articleId: string, isArchived: boolean): Promise<void> {
    const store: relationalStore.RdbStore = this.requireStore();
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(ARTICLE_TABLE);
    predicates.equalTo('id', articleId);
    await store.update({ is_archived: isArchived ? 1 : 0, updated_at: Date.now() }, predicates);
  }

  async getArticleContent(articleId: string): Promise<ArticleContent | undefined> {
    const store: relationalStore.RdbStore = this.requireStore();
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(CONTENT_TABLE);
    predicates.equalTo('article_id', articleId);
    const result: relationalStore.ResultSet = await store.query(predicates);
    try {
      if (!result.goToFirstRow()) {
        return undefined;
      }
      return {
        articleId: result.getString(result.getColumnIndex('article_id')),
        htmlPath: result.getString(result.getColumnIndex('html_path')),
        markdownPath: result.getString(result.getColumnIndex('markdown_path')),
        imageDirectoryPath: result.getString(result.getColumnIndex('image_directory_path')),
        extractedAt: result.getLong(result.getColumnIndex('extracted_at')),
        imageSavedCount: result.getLong(result.getColumnIndex('image_saved_count')),
        imageFailedCount: result.getLong(result.getColumnIndex('image_failed_count'))
      };
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
        articles.push(this.readSavedArticle(result));
      }
      return articles;
    } finally {
      result.close();
    }
  }

  async searchArticles(query: string): Promise<SavedArticle[]> {
    const terms: string[] = normalizeArticleSearchTerms(query);
    const articles: SavedArticle[] = await this.listArticles();
    const matches: SavedArticle[] = [];
    for (const article of articles) {
      const markdown: string | undefined = await this.readArticleMarkdown(article.id);
      if (articleMatchesSearch(article, markdown ?? '', terms)) {
        matches.push(article);
      }
    }
    return matches;
  }

  async saveNote(note: ArticleNote): Promise<void> {
    const store: relationalStore.RdbStore = this.requireStore();
    await store.insert('article_note', {
      id: note.id,
      article_id: note.articleId,
      body: note.body,
      created_at: note.createdAt,
      updated_at: note.updatedAt
    }, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
  }

  async createNote(articleId: string, body: string): Promise<ArticleNote> {
    const now: number = Date.now();
    const note: ArticleNote = {
      id: createArticleRecordId('note', now), articleId: articleId, body: body,
      createdAt: now, updatedAt: now
    };
    await this.saveNote(note);
    return note;
  }

  async listNotes(articleId: string): Promise<ArticleNote[]> {
    const store: relationalStore.RdbStore = this.requireStore();
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('article_note');
    predicates.equalTo('article_id', articleId).orderByDesc('updated_at');
    const result: relationalStore.ResultSet = await store.query(predicates);
    const notes: ArticleNote[] = [];
    try {
      while (result.goToNextRow()) {
        notes.push(cloneArticleNote({
          id: result.getString(result.getColumnIndex('id')),
          articleId: result.getString(result.getColumnIndex('article_id')),
          body: result.getString(result.getColumnIndex('body')),
          createdAt: result.getLong(result.getColumnIndex('created_at')),
          updatedAt: result.getLong(result.getColumnIndex('updated_at'))
        }));
      }
      return notes;
    } finally {
      result.close();
    }
  }

  async saveHighlight(highlight: ArticleHighlight): Promise<void> {
    const store: relationalStore.RdbStore = this.requireStore();
    await store.insert('article_highlight', {
      id: highlight.id,
      article_id: highlight.articleId,
      text_quote: highlight.textQuote,
      prefix: highlight.prefix,
      suffix: highlight.suffix,
      dom_path: highlight.domPath,
      state: highlight.state,
      created_at: highlight.createdAt
    }, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
  }

  async listHighlights(articleId: string): Promise<ArticleHighlight[]> {
    const store: relationalStore.RdbStore = this.requireStore();
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('article_highlight');
    predicates.equalTo('article_id', articleId).orderByAsc('created_at');
    const result: relationalStore.ResultSet = await store.query(predicates);
    const highlights: ArticleHighlight[] = [];
    try {
      while (result.goToNextRow()) {
        highlights.push(cloneArticleHighlight({
          id: result.getString(result.getColumnIndex('id')),
          articleId: result.getString(result.getColumnIndex('article_id')),
          textQuote: result.getString(result.getColumnIndex('text_quote')),
          prefix: result.getString(result.getColumnIndex('prefix')),
          suffix: result.getString(result.getColumnIndex('suffix')),
          domPath: result.getString(result.getColumnIndex('dom_path')),
          state: result.getLong(result.getColumnIndex('state')) as ArticleHighlightState,
          createdAt: result.getLong(result.getColumnIndex('created_at'))
        }));
      }
      return highlights;
    } finally {
      result.close();
    }
  }

  async restoreHighlights(articleId: string, text: string): Promise<ArticleHighlight[]> {
    const highlights: ArticleHighlight[] = await this.listHighlights(articleId);
    const restored: ArticleHighlight[] = [];
    for (const highlight of highlights) {
      const next: ArticleHighlight = restoreArticleHighlight(highlight, text);
      if (next.state !== highlight.state) {
        await this.saveHighlight(next);
      }
      restored.push(next);
    }
    return restored;
  }

  async createTopic(name: string): Promise<Topic | undefined> {
    const normalizedName: string = name.trim().replace(/\s+/g, ' ');
    if (normalizedName.length === 0) {
      return undefined;
    }
    const existing: Topic | undefined = await this.findTopicByName(normalizedName);
    if (existing !== undefined) {
      return existing;
    }
    const topic: Topic = {
      id: createArticleRecordId('topic'), name: normalizedName, createdAt: Date.now()
    };
    const store: relationalStore.RdbStore = this.requireStore();
    await store.insert('topic', {
      id: topic.id, name: topic.name, created_at: topic.createdAt
    }, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
    return topic;
  }

  async listTopics(): Promise<Topic[]> {
    const store: relationalStore.RdbStore = this.requireStore();
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('topic');
    predicates.orderByAsc('name');
    const result: relationalStore.ResultSet = await store.query(predicates);
    const topics: Topic[] = [];
    try {
      while (result.goToNextRow()) {
        topics.push(cloneTopic({
          id: result.getString(result.getColumnIndex('id')),
          name: result.getString(result.getColumnIndex('name')),
          createdAt: result.getLong(result.getColumnIndex('created_at'))
        }));
      }
      return topics;
    } finally {
      result.close();
    }
  }

  async assignTopic(articleId: string, topicId: string): Promise<void> {
    const store: relationalStore.RdbStore = this.requireStore();
    await store.insert('article_topic', {
      article_id: articleId, topic_id: topicId
    }, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
  }

  async listTopicsForArticle(articleId: string): Promise<Topic[]> {
    const store: relationalStore.RdbStore = this.requireStore();
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('article_topic');
    predicates.equalTo('article_id', articleId);
    const result: relationalStore.ResultSet = await store.query(predicates, ['topic_id']);
    const topics: Topic[] = [];
    try {
      while (result.goToNextRow()) {
        const topic: Topic | undefined = await this.getTopic(result.getString(0));
        if (topic !== undefined) {
          topics.push(topic);
        }
      }
      return topics;
    } finally {
      result.close();
    }
  }

  private async findTopicByName(name: string): Promise<Topic | undefined> {
    const store: relationalStore.RdbStore = this.requireStore();
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('topic');
    predicates.equalTo('name', name);
    const result: relationalStore.ResultSet = await store.query(predicates);
    try {
      if (!result.goToFirstRow()) {
        return undefined;
      }
      return this.readTopic(result);
    } finally {
      result.close();
    }
  }

  private async getTopic(topicId: string): Promise<Topic | undefined> {
    const store: relationalStore.RdbStore = this.requireStore();
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('topic');
    predicates.equalTo('id', topicId);
    const result: relationalStore.ResultSet = await store.query(predicates);
    try {
      return result.goToFirstRow() ? this.readTopic(result) : undefined;
    } finally {
      result.close();
    }
  }

  private async createSchema(store: relationalStore.RdbStore): Promise<void> {
    await store.executeSql(`CREATE TABLE IF NOT EXISTS ${ARTICLE_TABLE} (
      id TEXT PRIMARY KEY, source_url TEXT NOT NULL, canonical_url TEXT NOT NULL,
      title TEXT NOT NULL, author TEXT NOT NULL DEFAULT '', excerpt TEXT NOT NULL,
      created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
      reading_position INTEGER NOT NULL DEFAULT 0, tags_json TEXT NOT NULL DEFAULT '[]',
      is_archived INTEGER NOT NULL DEFAULT 0, failure INTEGER NOT NULL, failure_message TEXT NOT NULL
    )`);
    await store.executeSql(`CREATE TABLE IF NOT EXISTS ${CONTENT_TABLE} (
      article_id TEXT PRIMARY KEY, html_path TEXT NOT NULL, markdown_path TEXT NOT NULL,
      image_directory_path TEXT NOT NULL, extracted_at INTEGER NOT NULL,
      image_saved_count INTEGER NOT NULL DEFAULT 0, image_failed_count INTEGER NOT NULL DEFAULT 0
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

  private async migrateSchema(store: relationalStore.RdbStore): Promise<void> {
    await this.addColumnIfMissing(store, ARTICLE_TABLE, 'author', "TEXT NOT NULL DEFAULT ''");
    await this.addColumnIfMissing(store, ARTICLE_TABLE, 'reading_position', 'INTEGER NOT NULL DEFAULT 0');
    await this.addColumnIfMissing(store, ARTICLE_TABLE, 'tags_json', "TEXT NOT NULL DEFAULT '[]'");
    await this.addColumnIfMissing(store, ARTICLE_TABLE, 'is_archived', 'INTEGER NOT NULL DEFAULT 0');
    await this.addColumnIfMissing(store, CONTENT_TABLE, 'image_saved_count', 'INTEGER NOT NULL DEFAULT 0');
    await this.addColumnIfMissing(store, CONTENT_TABLE, 'image_failed_count', 'INTEGER NOT NULL DEFAULT 0');
  }

  private async addColumnIfMissing(
    store: relationalStore.RdbStore,
    table: string,
    column: string,
    definition: string
  ): Promise<void> {
    const result: relationalStore.ResultSet = await store.querySql(`PRAGMA table_info(${table})`, []);
    let exists: boolean = false;
    try {
      while (result.goToNextRow()) {
        if (result.getString(result.getColumnIndex('name')) === column) {
          exists = true;
          break;
        }
      }
    } finally {
      result.close();
    }
    if (!exists) {
      await store.executeSql(`ALTER TABLE ${table} ADD COLUMN ${column} ${definition}`);
      Logger.info(TAG, `Migrated ${table}.${column}`);
    }
  }

  private readSavedArticle(result: relationalStore.ResultSet): SavedArticle {
    return cloneSavedArticle({
      id: result.getString(result.getColumnIndex('id')),
      sourceUrl: result.getString(result.getColumnIndex('source_url')),
      canonicalUrl: result.getString(result.getColumnIndex('canonical_url')),
      title: result.getString(result.getColumnIndex('title')),
      author: result.getString(result.getColumnIndex('author')),
      excerpt: result.getString(result.getColumnIndex('excerpt')),
      createdAt: result.getLong(result.getColumnIndex('created_at')),
      updatedAt: result.getLong(result.getColumnIndex('updated_at')),
      readingPosition: result.getLong(result.getColumnIndex('reading_position')),
      tags: this.decodeTags(result.getString(result.getColumnIndex('tags_json'))),
      isArchived: result.getLong(result.getColumnIndex('is_archived')) === 1,
      failure: result.getLong(result.getColumnIndex('failure')) as ArticleSaveFailure,
      failureMessage: result.getString(result.getColumnIndex('failure_message'))
    });
  }

  private readTopic(result: relationalStore.ResultSet): Topic {
    return cloneTopic({
      id: result.getString(result.getColumnIndex('id')),
      name: result.getString(result.getColumnIndex('name')),
      createdAt: result.getLong(result.getColumnIndex('created_at'))
    });
  }

  private decodeTags(raw: string): string[] {
    try {
      const decoded: Object = JSON.parse(raw) as Object;
      return Array.isArray(decoded)
        ? decoded.filter((tag: Object): boolean => typeof tag === 'string').map((tag: Object): string => String(tag))
        : [];
    } catch (error) {
      Logger.warn(TAG, `Saved article tags were invalid: ${String(error)}`);
      return [];
    }
  }

  private async writeContent(
    articleId: string,
    html: string,
    markdown: string,
    images: ArticleImageAsset[]
  ): Promise<ArticleContent> {
    const articleDirectory: string = `${this.filesDirectory}/${articleId}`;
    const imageDirectoryPath: string = `${articleDirectory}/images`;
    await fileIo.mkdir(imageDirectoryPath, true);
    const htmlPath: string = `${articleDirectory}/article.html`;
    const markdownPath: string = `${articleDirectory}/article.md`;
    await this.writeText(htmlPath, html);
    await this.writeText(markdownPath, markdown);
    const imageResult: ArticleImageStoreResult = await ArticleImageStore.persist(images, imageDirectoryPath);
    return {
      articleId: articleId,
      htmlPath: htmlPath,
      markdownPath: markdownPath,
      imageDirectoryPath: imageDirectoryPath,
      extractedAt: Date.now(),
      imageSavedCount: imageResult.savedCount,
      imageFailedCount: imageResult.failedCount
    };
  }

  private async writeText(path: string, content: string): Promise<void> {
    const file: fileIo.File = await fileIo.open(path, fileIo.OpenMode.READ_WRITE |
      fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    try {
      await fileIo.write(file.fd, content);
    } finally {
      await fileIo.close(file.fd);
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
