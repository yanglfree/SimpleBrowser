import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import fs from '@ohos.file.fs';
import picker from '@ohos.file.picker';
import { ArticleHighlight, ArticleNote, SavedArticle, Topic } from '../models/ArticleLibraryModels';
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

export interface ArticleExportExtras {
  notes: ArticleNote[];
  topics: Topic[];
  highlights: ArticleHighlight[];
  imageFailedCount: number;
}

const EMPTY_EXPORT_EXTRAS: ArticleExportExtras = {
  notes: [],
  topics: [],
  highlights: [],
  imageFailedCount: 0
};

/** Exports only content already stored in the local article library. */
export class ArticleExportService {
  static async exportToPicker(
    context: common.UIAbilityContext,
    article: SavedArticle,
    markdown: string,
    html: string,
    imageDirectoryPath: string,
    format: ArticleExportFormat,
    extras: ArticleExportExtras = EMPTY_EXPORT_EXTRAS
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
        ? ArticleExportService.markdownDocument(article,
          await ArticleExportService.inlineLocalImages(markdown, imageDirectoryPath), extras)
        : ArticleExportService.standaloneHtmlDocument(article,
          await ArticleExportService.inlineLocalImages(html, imageDirectoryPath), extras);
      const file: fs.File = fs.openSync(uris[0], fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(file.fd, text);
      } finally {
        fs.closeSync(file.fd);
      }
      return { format: format, uri: uris[0], fileName: fileName };
    } catch (error) {
      Logger.warn(TAG, 'Article export failed');
      throw new Error('Article export failed');
    }
  }

  static markdownDocument(
    article: SavedArticle,
    markdown: string,
    extras: ArticleExportExtras = EMPTY_EXPORT_EXTRAS
  ): string {
    const source: string = article.canonicalUrl.length > 0 ? article.canonicalUrl : article.sourceUrl;
    const metadata: string[] = [`Source: ${source}`];
    if (article.author.length > 0) {
      metadata.push(`Author: ${article.author}`);
    }
    if (article.tags.length > 0) {
      metadata.push(`Tags: ${article.tags.join(', ')}`);
    }
    if (extras.topics.length > 0) {
      metadata.push(`Topics: ${extras.topics.map((topic: Topic): string => topic.name).join(', ')}`);
    }
    return [
      `# ${article.title}`,
      metadata.join('\n'),
      markdown.trim(),
      ArticleExportService.markdownAnnotations(extras)
    ].filter((section: string): boolean => section.length > 0).join('\n\n') + '\n';
  }

  static standaloneHtmlDocument(
    article: SavedArticle,
    html: string,
    extras: ArticleExportExtras = EMPTY_EXPORT_EXTRAS
  ): string {
    const baseUrl: string = ArticleExportService.escapeAttribute(
      article.canonicalUrl.length > 0 ? article.canonicalUrl : article.sourceUrl
    );
    const title: string = ArticleExportService.escapeHtml(article.title);
    const annotations: string = ArticleExportService.htmlAnnotations(extras);
    const cleanedHtml: string = html.replace(/<head\b[^>]*>[\s\S]*?<\/head>/gi, '')
      .replace(/<(script|style|iframe|object|embed|form)\b[^>]*>[\s\S]*?<\/\1>/gi, '')
      .replace(/<\/?(?:html|body|head|meta|base|link|script|iframe|object|embed)\b[^>]*>/gi, '')
      .replace(/<!doctype[^>]*>/gi, '')
      .replace(/\s+on[\w-]+\s*=\s*(?:"[^"]*"|'[^']*'|[^\s>]+)/gi, '');
    const policy: string = "default-src 'none'; img-src data:; style-src 'unsafe-inline'; " +
      "script-src 'none'; frame-src 'none'; object-src 'none'; form-action 'none'; base-uri https: http:; sandbox allow-same-origin";
    const style: string = 'html{color-scheme:light dark}body{margin:0;padding:22px;font:17px/1.8 system-ui;' +
      'overflow-wrap:anywhere}main{max-width:720px;margin:auto}img{max-width:100%;height:auto}' +
      'h1{font-size:26px;line-height:1.4}pre{overflow:auto;white-space:pre-wrap}table{max-width:100%;border-collapse:collapse}' +
      'td,th{border:1px solid #888;padding:6px}blockquote{margin-left:0;border-left:3px solid #2e6b5c;padding-left:16px}' +
      'a{color:#438c79}mark{background:#f2d479;color:#222}';
    return `<!doctype html>\n<html><head><meta charset="utf-8">` +
      `<meta http-equiv="Content-Security-Policy" content="${policy}">` +
      `<meta name="viewport" content="width=device-width,initial-scale=1"><base href="${baseUrl}">` +
      `<title>${title}</title><style>${style}</style></head><body><main>` +
      `<h1>${title}</h1><p><a href="${baseUrl}">${baseUrl}</a></p>` +
      `<div id="article-content">${cleanedHtml}</div>${annotations}</main></body></html>`;
  }

  private static markdownAnnotations(extras: ArticleExportExtras): string {
    const sections: string[] = [];
    if (extras.notes.length > 0) {
      sections.push(`## Notes\n\n${extras.notes.map((note: ArticleNote): string => `- ${note.body}`).join('\n')}`);
    }
    if (extras.highlights.length > 0) {
      sections.push(`## Highlights\n\n${extras.highlights
        .map((highlight: ArticleHighlight): string => `> ${highlight.textQuote}`).join('\n\n')}`);
    }
    if (extras.imageFailedCount > 0) {
      sections.push(`> ${extras.imageFailedCount} image(s) could not be saved for offline export.`);
    }
    return sections.join('\n\n');
  }

  private static htmlAnnotations(extras: ArticleExportExtras): string {
    const sections: string[] = [];
    if (extras.notes.length > 0) {
      const notes: string = extras.notes.map((note: ArticleNote): string =>
        `<li>${ArticleExportService.escapeHtml(note.body)}</li>`).join('');
      sections.push(`<section><h2>Notes</h2><ul>${notes}</ul></section>`);
    }
    if (extras.highlights.length > 0) {
      const highlights: string = extras.highlights.map((highlight: ArticleHighlight): string =>
        `<blockquote>${ArticleExportService.escapeHtml(highlight.textQuote)}</blockquote>`).join('');
      sections.push(`<section><h2>Highlights</h2>${highlights}</section>`);
    }
    if (extras.imageFailedCount > 0) {
      sections.push(`<p>${extras.imageFailedCount} image(s) could not be saved for offline export.</p>`);
    }
    return sections.length > 0 ? `<aside data-zhuoyue-annotations>${sections.join('')}</aside>` : '';
  }

  /** Replaces captured relative image paths with data URLs so the HTML is portable as one file. */
  static async inlineLocalImages(html: string, imageDirectoryPath: string): Promise<string> {
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
        output = output.split(`images/${name}`).join(dataUrl);
      } else {
        output = output.split(`images/${name}`).join('data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw==');
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

  private static escapeAttribute(value: string): string {
    return value.replace(/&/g, '&amp;').replace(/"/g, '&quot;');
  }

  private static escapeHtml(value: string): string {
    return ArticleExportService.escapeAttribute(value).replace(/</g, '&lt;').replace(/>/g, '&gt;');
  }
}
