import { common } from '@kit.AbilityKit';
import fs from '@ohos.file.fs';
import picker from '@ohos.file.picker';
import { util } from '@kit.ArkTS';
import { SavedItem } from '../models/BrowserModels';
import { Logger } from '../utils/Logger';

const TAG: string = 'BookmarkTransferService';
const MAX_IMPORT_BYTES: number = 5 * 1024 * 1024;

/** Netscape bookmark HTML import/export with no dependency on a DOM runtime. */
export class BookmarkTransferService {
  static parse(html: string): SavedItem[] {
    const items: SavedItem[] = [];
    const anchorPattern: RegExp = /<a\b([^>]*)>([\s\S]*?)<\/a>/gi;
    let match: RegExpExecArray | null = anchorPattern.exec(html);
    let index: number = 0;
    while (match !== null) {
      const href: string | undefined = BookmarkTransferService.hrefAttribute(match[1]);
      const url: string = href === undefined ? '' : BookmarkTransferService.decode(href.trim());
      const title: string = BookmarkTransferService.decode(match[2].replace(/<[^>]*>/g, ' ').replace(/\s+/g, ' ').trim());
      if (/^https?:/i.test(url) && !items.some((item: SavedItem): boolean => item.url === url)) {
        const now: number = Date.now();
        items.push({
          id: `saved-import-${now}-${index}`,
          title: title,
          url: url,
          createdAt: now,
          updatedAt: now,
          isRead: true,
          tags: BookmarkTransferService.tagsAttribute(match[1])
        });
        index += 1;
      }
      match = anchorPattern.exec(html);
    }
    return items;
  }

  static export(items: SavedItem[]): string {
    const lines: string[] = [
      '<!DOCTYPE NETSCAPE-Bookmark-file-1>',
      '<META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">',
      '<TITLE>Bookmarks</TITLE>',
      '<H1>Bookmarks</H1>',
      '<DL><p>'
    ];
    for (const item of items) {
      const tags: string = BookmarkTransferService.normalizedTags(item.tags).join(',');
      const tagsAttribute: string = tags.length > 0
        ? ` TAGS="${BookmarkTransferService.escape(tags)}"`
        : '';
      lines.push(`    <DT><A HREF="${BookmarkTransferService.escape(item.url)}"${tagsAttribute}>${BookmarkTransferService.escape(item.title)}</A>`);
    }
    lines.push('</DL><p>');
    return lines.join('\n');
  }

  static async importFromPicker(context: common.UIAbilityContext): Promise<SavedItem[]> {
    try {
      const options: picker.DocumentSelectOptions = {
        fileSuffixFilters: ['.html,.htm'],
        maxSelectNumber: 1
      };
      const uris: string[] = await new picker.DocumentViewPicker(context).select(options);
      if (uris.length === 0) {
        return [];
      }
      return BookmarkTransferService.parse(BookmarkTransferService.readPickedText(uris[0]));
    } catch (error) {
      Logger.warn(TAG, `Bookmark import unavailable: ${String(error)}`);
      return [];
    }
  }

  static async exportToPicker(context: common.UIAbilityContext, items: SavedItem[]): Promise<boolean> {
    try {
      const options: picker.DocumentSaveOptions = {
        newFileNames: ['browser-bookmarks.html'],
        fileSuffixChoices: ['HTML|.html']
      };
      const uris: string[] = await new picker.DocumentViewPicker(context).save(options);
      if (uris.length === 0) {
        return false;
      }
      const file: fs.File = fs.openSync(uris[0], fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, BookmarkTransferService.export(items));
      fs.closeSync(file.fd);
      return true;
    } catch (error) {
      Logger.warn(TAG, `Bookmark export unavailable: ${String(error)}`);
      return false;
    }
  }

  private static escape(value: string): string {
    return value.replace(/&/g, '&amp;')
      .replace(/"/g, '&quot;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;');
  }

  private static hrefAttribute(attributes: string): string | undefined {
    const match: RegExpMatchArray | null = attributes.match(/\bhref\s*=\s*["']([^"']*)["']/i);
    return match === null ? undefined : match[1];
  }

  private static tagsAttribute(attributes: string): string[] {
    const match: RegExpMatchArray | null = attributes.match(/\btags\s*=\s*["']([^"']*)["']/i);
    if (match === null) {
      return [];
    }
    return BookmarkTransferService.normalizedTags(
      BookmarkTransferService.decode(match[1]).split(',')
    );
  }

  private static normalizedTags(tags: string[]): string[] {
    const normalized: string[] = [];
    for (const tag of tags) {
      const value: string = tag.trim();
      if (value.length > 0 && !normalized.includes(value)) {
        normalized.push(value);
      }
    }
    return normalized;
  }

  private static readPickedText(uri: string): string {
    const file: fs.File = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    try {
      const size: number = fs.statSync(file.fd).size;
      if (size <= 0) {
        return '';
      }
      if (size > MAX_IMPORT_BYTES) {
        throw new Error('Bookmark import exceeds the supported size');
      }
      const buffer: ArrayBuffer = new ArrayBuffer(size);
      const bytesRead: number = fs.readSync(file.fd, buffer);
      return new util.TextDecoder().decodeToString(new Uint8Array(buffer, 0, bytesRead));
    } finally {
      fs.closeSync(file.fd);
    }
  }

  private static decode(value: string): string {
    return value.replace(/&amp;/g, '&')
      .replace(/&quot;/g, '"')
      .replace(/&#39;/g, "'")
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>');
  }
}
