import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import fs from '@ohos.file.fs';
import picker from '@ohos.file.picker';
import { SavedArticle } from '../models/ArticleLibraryModels';
import { Logger } from '../utils/Logger';

const TAG: string = 'ArticleExportService';

export enum ArticleExportFormat {
  Markdown = 0,
  StandaloneHtml = 1
}

export interface ArticleExportResult {
  format: ArticleExportFormat;
  uri: string;
  fileName: string;
}

/** Exports only content already stored in the local article library. */
export class ArticleExportService {
  static async exportToPicker(
    context: common.UIAbilityContext,
    article: SavedArticle,
    markdown: string,
    html: string,
    imageDirectoryPath: string,
    format: ArticleExportFormat
  ): Promise<ArticleExportResult | undefined> {
    try {
      const fileName: string = ArticleExportService.fileNameFor(article, format);
      const options: picker.DocumentSaveOptions = {
        newFileNames: [fileName],
        fileSuffixChoices: format === ArticleExportFormat.Markdown ? ['Markdown|.md'] : ['HTML|.html']
      };
      const uris: string[] = await new picker.DocumentViewPicker(context).save(options);
      if (uris.length === 0) {
        return undefined;
      }
      const text: string = format === ArticleExportFormat.Markdown
        ? ArticleExportService.markdownDocument(article, markdown)
        : ArticleExportService.standaloneHtmlDocument(article,
          await ArticleExportService.inlineLocalImages(html, imageDirectoryPath));
      const file: fs.File = fs.openSync(uris[0], fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(file.fd, text);
      } finally {
        fs.closeSync(file.fd);
      }
      return { format: format, uri: uris[0], fileName: fileName };
    } catch (error) {
      Logger.warn(TAG, `Article export unavailable: ${String(error)}`);
      return undefined;
    }
  }

  static markdownDocument(article: SavedArticle, markdown: string): string {
    const source: string = article.canonicalUrl.length > 0 ? article.canonicalUrl : article.sourceUrl;
    return `# ${article.title}\n\nSource: ${source}\n\n${markdown.trim()}\n`;
  }

  static standaloneHtmlDocument(article: SavedArticle, html: string): string {
    const baseUrl: string = ArticleExportService.escapeAttribute(
      article.canonicalUrl.length > 0 ? article.canonicalUrl : article.sourceUrl
    );
    const title: string = ArticleExportService.escapeHtml(article.title);
    const cleanedHtml: string = html.replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, '');
    if (/<!doctype\s+html/i.test(cleanedHtml)) {
      return ArticleExportService.addDocumentMetadata(cleanedHtml, baseUrl, title);
    }
    if (/<html\b/i.test(cleanedHtml)) {
      return `<!doctype html>\n${ArticleExportService.addDocumentMetadata(cleanedHtml, baseUrl, title)}`;
    }
    return `<!doctype html>\n<html lang="en"><head><meta charset="utf-8"><base href="${baseUrl}"><title>${title}</title></head><body>${cleanedHtml}</body></html>`;
  }

  /** Replaces captured relative image paths with data URLs so the HTML is portable as one file. */
  private static async inlineLocalImages(html: string, imageDirectoryPath: string): Promise<string> {
    const names: string[] = [];
    const pattern: RegExp = /images\/(image-\d+\.(?:jpg|jpeg|png|gif|webp|avif|svg))/gi;
    let match: RegExpExecArray | null = pattern.exec(html);
    while (match !== null) {
      if (!names.includes(match[1])) {
        names.push(match[1]);
      }
      match = pattern.exec(html);
    }
    let output: string = html;
    for (const name of names) {
      const dataUrl: string | undefined = await ArticleExportService.readImageDataUrl(`${imageDirectoryPath}/${name}`, name);
      if (dataUrl !== undefined) {
        output = output.replace(new RegExp(`images/${name}`, 'gi'), dataUrl);
      }
    }
    return output;
  }

  private static async readImageDataUrl(path: string, fileName: string): Promise<string | undefined> {
    try {
      const stat: fs.Stat = fs.statSync(path);
      if (stat.size <= 0) {
        return undefined;
      }
      const file: fs.File = fs.openSync(path, fs.OpenMode.READ_ONLY);
      try {
        const bytes: ArrayBuffer = new ArrayBuffer(stat.size);
        const length: number = fs.readSync(file.fd, bytes, { offset: 0, length: stat.size });
        if (length <= 0) {
          return undefined;
        }
        const base64: string = new util.Base64Helper().encodeToStringSync(
          new Uint8Array(bytes.slice(0, length))
        );
        return `data:${ArticleExportService.imageMimeType(fileName)};base64,${base64}`;
      } finally {
        fs.closeSync(file.fd);
      }
    } catch (error) {
      Logger.warn(TAG, `Saved article image was not embedded: ${String(error)}`);
      return undefined;
    }
  }

  private static imageMimeType(fileName: string): string {
    const extension: string = fileName.substring(fileName.lastIndexOf('.') + 1).toLowerCase();
    if (extension === 'jpg' || extension === 'jpeg') {
      return 'image/jpeg';
    }
    if (extension === 'svg') {
      return 'image/svg+xml';
    }
    return `image/${extension}`;
  }

  private static fileNameFor(article: SavedArticle, format: ArticleExportFormat): string {
    const baseName: string = article.title.replace(/[^\w\u4e00-\u9fff-]+/g, '-').replace(/^-+|-+$/g, '');
    const safeBaseName: string = baseName.length > 0 ? baseName.substring(0, 80) : article.id;
    return `${safeBaseName}.${format === ArticleExportFormat.Markdown ? 'md' : 'html'}`;
  }

  private static addDocumentMetadata(html: string, baseUrl: string, title: string): string {
    const metadata: string = `<meta charset="utf-8"><base href="${baseUrl}"><title>${title}</title>`;
    if (/<head\b[^>]*>/i.test(html)) {
      return html.replace(/<head\b[^>]*>/i, (head: string): string => `${head}${metadata}`);
    }
    return html.replace(/<html\b[^>]*>/i, (root: string): string => `${root}<head>${metadata}</head>`);
  }

  private static escapeAttribute(value: string): string {
    return value.replace(/&/g, '&amp;').replace(/"/g, '&quot;');
  }

  private static escapeHtml(value: string): string {
    return ArticleExportService.escapeAttribute(value).replace(/</g, '&lt;').replace(/>/g, '&gt;');
  }
}
