import { common } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor } from '@kit.ArkData';
import { image } from '@kit.ImageKit';
import { fileUri } from '@kit.CoreFileKit';
import fs from '@ohos.file.fs';
import { Logger } from '../utils/Logger';

const TAG: string = 'ShareService';
const SCREENSHOT_CACHE_PREFIX: string = 'minimal-browser-share-';
const SCREENSHOT_CACHE_SUFFIX: string = '.jpg';
export const SCREENSHOT_CACHE_RETENTION_MS: number = 10 * 60 * 1000;

export function buildLinkShareRecord(url: string, title: string): systemShare.SharedRecord {
  return {
    utd: uniformTypeDescriptor.UniformDataType.HYPERLINK,
    content: url,
    title: title.length > 0 ? title : url
  };
}

export function screenshotCacheFileName(timestamp: number): string {
  return `${SCREENSHOT_CACHE_PREFIX}${timestamp}${SCREENSHOT_CACHE_SUFFIX}`;
}

export function shouldRemoveScreenshotCacheFile(name: string, now: number): boolean {
  if (!name.startsWith(SCREENSHOT_CACHE_PREFIX) || !name.endsWith(SCREENSHOT_CACHE_SUFFIX)) {
    return false;
  }
  const timestampText: string = name.slice(
    SCREENSHOT_CACHE_PREFIX.length,
    name.length - SCREENSHOT_CACHE_SUFFIX.length
  );
  const timestamp: number = Number(timestampText);
  return !Number.isNaN(timestamp) && now - timestamp >= SCREENSHOT_CACHE_RETENTION_MS;
}

export enum ShareOutcome {
  Shared = 0,
  Copied = 1,
  Failed = 2
}

export class ShareService {
  /**
   * Hands the link to the system share sheet. Devices without one still get a
   * usable result: the URL lands on the clipboard and the caller shows a toast.
   */
  static async share(context: common.UIAbilityContext, url: string, title: string): Promise<ShareOutcome> {
    if (url.length === 0) {
      return ShareOutcome.Failed;
    }
    try {
      const record: systemShare.SharedRecord = buildLinkShareRecord(url, title);
      const controller: systemShare.ShareController =
        new systemShare.ShareController(new systemShare.SharedData(record));
      await controller.show(context, {
        selectionMode: systemShare.SelectionMode.SINGLE,
        previewMode: systemShare.SharePreviewMode.DETAIL
      });
      return ShareOutcome.Shared;
    } catch (error) {
      Logger.warn(TAG, `System share unavailable, copying instead: ${String(error)}`);
      return await ShareService.copy(url);
    }
  }

  static async copy(url: string): Promise<ShareOutcome> {
    try {
      const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, url);
      await pasteboard.getSystemPasteboard().setData(data);
      return ShareOutcome.Copied;
    } catch (error) {
      Logger.error(TAG, `Failed to copy link: ${String(error)}`);
      return ShareOutcome.Failed;
    }
  }

  static async readText(): Promise<string> {
    try {
      const data: pasteboard.PasteData = await pasteboard.getSystemPasteboard().getData();
      const text: string | undefined = data.getPrimaryText();
      return text === undefined ? '' : text.trim();
    } catch (error) {
      Logger.warn(TAG, `Failed to read clipboard text: ${String(error)}`);
      return '';
    }
  }

  /** Encodes an in-memory page snapshot to a short-lived cache file for Share Kit. */
  static async shareImage(
    context: common.UIAbilityContext,
    pixelMap: image.PixelMap,
    title: string
  ): Promise<ShareOutcome> {
    ShareService.cleanupExpiredScreenshots(context.cacheDir, Date.now());
    const path: string = `${context.cacheDir}/${screenshotCacheFileName(Date.now())}`;
    let file: fs.File | undefined = undefined;
    let shouldPreserveFile: boolean = false;
    try {
      file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      const packer: image.ImagePacker = image.createImagePacker();
      const options: image.PackingOption = { format: 'image/jpeg', quality: 92 };
      await packer.packToFile(pixelMap, file.fd, options);
      fs.closeSync(file.fd);
      file = undefined;

      const uri: string = fileUri.getUriFromPath(path);
      const record: systemShare.SharedRecord = {
        utd: uniformTypeDescriptor.getUniformDataTypeByFilenameExtension(
          '.jpg', uniformTypeDescriptor.UniformDataType.IMAGE),
        uri: uri,
        thumbnailUri: uri,
        title: title.length > 0 ? title : 'Browser page'
      };
      const controller: systemShare.ShareController =
        new systemShare.ShareController(new systemShare.SharedData(record));
      await controller.show(context, {
        selectionMode: systemShare.SelectionMode.SINGLE,
        previewMode: systemShare.SharePreviewMode.DETAIL
      });
      // Share targets may read the URI after the panel has returned control to
      // us. Keep it briefly, then reclaim it instead of deleting it immediately.
      shouldPreserveFile = true;
      ShareService.scheduleScreenshotCleanup(path);
      return ShareOutcome.Shared;
    } catch (error) {
      Logger.warn(TAG, `Page screenshot share unavailable: ${String(error)}`);
      return ShareOutcome.Failed;
    } finally {
      if (file !== undefined) {
        try {
          fs.closeSync(file.fd);
        } catch (_error) {
          Logger.warn(TAG, 'Failed to close screenshot cache file');
        }
      }
      if (!shouldPreserveFile) {
        ShareService.removeScreenshot(path);
      }
    }
  }

  static async shareFile(
    context: common.UIAbilityContext,
    path: string,
    title: string
  ): Promise<ShareOutcome> {
    if (path.length === 0) {
      return ShareOutcome.Failed;
    }
    try {
      const record: systemShare.SharedRecord = {
        utd: uniformTypeDescriptor.getUniformDataTypeByFilenameExtension(`.${ShareService.extension(path)}`),
        uri: fileUri.getUriFromPath(path),
        title: title.length > 0 ? title : path
      };
      const controller: systemShare.ShareController =
        new systemShare.ShareController(new systemShare.SharedData(record));
      await controller.show(context, {
        selectionMode: systemShare.SelectionMode.SINGLE,
        previewMode: systemShare.SharePreviewMode.DETAIL
      });
      return ShareOutcome.Shared;
    } catch (error) {
      Logger.warn(TAG, `File share unavailable: ${String(error)}`);
      return ShareOutcome.Failed;
    }
  }

  private static extension(path: string): string {
    const name: string = path.split('/').pop() ?? '';
    const dot: number = name.lastIndexOf('.');
    return dot >= 0 && dot < name.length - 1 ? name.slice(dot + 1).toLowerCase() : 'octet-stream';
  }

  private static cleanupExpiredScreenshots(cacheDir: string, now: number): void {
    try {
      const names: string[] = fs.listFileSync(cacheDir);
      for (const name of names) {
        if (shouldRemoveScreenshotCacheFile(name, now)) {
          ShareService.removeScreenshot(`${cacheDir}/${name}`);
        }
      }
    } catch (error) {
      Logger.warn(TAG, `Failed to inspect screenshot cache: ${String(error)}`);
    }
  }

  private static scheduleScreenshotCleanup(path: string): void {
    setTimeout((): void => ShareService.removeScreenshot(path), SCREENSHOT_CACHE_RETENTION_MS);
  }

  private static removeScreenshot(path: string): void {
    try {
      fs.unlinkSync(path);
    } catch (error) {
      // The cache directory is best-effort storage and may already be cleared.
      Logger.debug(TAG, `Screenshot cache already unavailable: ${String(error)}`);
    }
  }
}
