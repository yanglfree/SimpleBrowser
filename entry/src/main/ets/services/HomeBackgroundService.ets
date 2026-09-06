import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { http } from '@kit.NetworkKit';
import fs from '@ohos.file.fs';
import {
  BING_DAILY_ARCHIVE_URL,
  isDailyWallpaperCacheFresh,
  isSupportedDailyWallpaper,
  resolveBingDailyImageUrl
} from '../models/BingDailyWallpaper';
import { Logger } from '../utils/Logger';

const TAG: string = 'HomeBackgroundService';
const CUSTOM_BACKGROUND_FILE: string = 'home_background_custom.image';
const DAILY_BACKGROUND_FILE: string = 'home_background_bing_daily.jpg';
const DAILY_BACKGROUND_TEMP_FILE: string = 'home_background_bing_daily.next.jpg';
const MAX_DAILY_BACKGROUND_BYTES: number = 20 * 1024 * 1024;
const CONNECT_TIMEOUT_MS: number = 6000;
const READ_TIMEOUT_MS: number = 12000;

export class HomeBackgroundService {
  static async selectCustomImage(context: common.UIAbilityContext): Promise<string | undefined> {
    try {
      const options: photoAccessHelper.PhotoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = 1;
      const result: photoAccessHelper.PhotoSelectResult =
        await new photoAccessHelper.PhotoViewPicker().select(options);
      if (result.photoUris.length === 0) {
        return undefined;
      }
      const targetPath: string = `${context.filesDir}/${CUSTOM_BACKGROUND_FILE}`;
      const source: fileIo.File = fileIo.openSync(result.photoUris[0], fileIo.OpenMode.READ_ONLY);
      try {
        const target: fileIo.File = fileIo.openSync(
          targetPath,
          fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC
        );
        try {
          fileIo.copyFileSync(source.fd, target.fd);
        } finally {
          fileIo.closeSync(target);
        }
      } finally {
        fileIo.closeSync(source);
      }
      return fileUri.getUriFromPath(targetPath);
    } catch (error) {
      Logger.warn(TAG, `Failed to import a custom background: ${String(error)}`);
      return undefined;
    }
  }

  /** Returns today's Bing image, or the last cached image when refresh fails. */
  static async dailyImage(context: common.UIAbilityContext): Promise<string> {
    const path: string = `${context.filesDir}/${DAILY_BACKGROUND_FILE}`;
    const cachedUri: string = HomeBackgroundService.cachedImageUri(path);
    if (cachedUri.length > 0 && await HomeBackgroundService.isFresh(path)) {
      return cachedUri;
    }

    const imageUrl: string | undefined = await HomeBackgroundService.fetchDailyImageUrl();
    if (imageUrl === undefined) {
      return cachedUri;
    }
    const bytes: Uint8Array | undefined = await HomeBackgroundService.fetchDailyImage(imageUrl);
    if (bytes === undefined) {
      return cachedUri;
    }
    const updatedPath: string | undefined = await HomeBackgroundService.writeDailyImage(context, bytes);
    return updatedPath === undefined ? cachedUri : fileUri.getUriFromPath(updatedPath);
  }

  private static cachedImageUri(path: string): string {
    try {
      return fs.accessSync(path) ? fileUri.getUriFromPath(path) : '';
    } catch (error) {
      Logger.warn(TAG, `Daily background cache unavailable: ${String(error)}`);
      return '';
    }
  }

  private static async isFresh(path: string): Promise<boolean> {
    try {
      const stat: fs.Stat = await fs.stat(path);
      return stat.size > 0 && isDailyWallpaperCacheFresh(stat.mtime * 1000, Date.now());
    } catch (error) {
      Logger.warn(TAG, `Daily background cache unreadable: ${String(error)}`);
      return false;
    }
  }

  private static async fetchDailyImageUrl(): Promise<string | undefined> {
    const request: http.HttpRequest = http.createHttp();
    try {
      const response: http.HttpResponse = await request.request(BING_DAILY_ARCHIVE_URL, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: CONNECT_TIMEOUT_MS,
        readTimeout: READ_TIMEOUT_MS,
        header: { 'accept': 'application/json' }
      });
      const status: number = Number(response.responseCode);
      if (status < 200 || status >= 300) {
        return undefined;
      }
      const payload: string = typeof response.result === 'string'
        ? response.result
        : new util.TextDecoder().decodeToString(new Uint8Array(response.result as ArrayBuffer));
      return resolveBingDailyImageUrl(payload);
    } catch (error) {
      Logger.warn(TAG, `Daily background metadata fetch failed: ${String(error)}`);
      return undefined;
    } finally {
      request.destroy();
    }
  }

  private static async fetchDailyImage(url: string): Promise<Uint8Array | undefined> {
    const request: http.HttpRequest = http.createHttp();
    try {
      const response: http.HttpResponse = await request.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: CONNECT_TIMEOUT_MS,
        readTimeout: READ_TIMEOUT_MS,
        maxLimit: MAX_DAILY_BACKGROUND_BYTES,
        header: { 'accept': 'image/jpeg' }
      });
      const status: number = Number(response.responseCode);
      if (status < 200 || status >= 300 || !(response.result instanceof ArrayBuffer)) {
        return undefined;
      }
      const bytes: Uint8Array = new Uint8Array(response.result as ArrayBuffer);
      return bytes.length <= MAX_DAILY_BACKGROUND_BYTES && isSupportedDailyWallpaper(bytes) ? bytes : undefined;
    } catch (error) {
      Logger.warn(TAG, `Daily background image fetch failed: ${String(error)}`);
      return undefined;
    } finally {
      request.destroy();
    }
  }

  private static async writeDailyImage(
    context: common.UIAbilityContext,
    bytes: Uint8Array
  ): Promise<string | undefined> {
    const path: string = `${context.filesDir}/${DAILY_BACKGROUND_FILE}`;
    const tempPath: string = `${context.filesDir}/${DAILY_BACKGROUND_TEMP_FILE}`;
    try {
      const file: fs.File = await fs.open(
        tempPath,
        fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC
      );
      try {
        await fs.write(file.fd, bytes.buffer as ArrayBuffer);
      } finally {
        await fs.close(file.fd);
      }
      await fs.rename(tempPath, path);
      return path;
    } catch (error) {
      Logger.warn(TAG, `Failed to cache daily background: ${String(error)}`);
      try {
        if (fs.accessSync(tempPath)) {
          fs.unlinkSync(tempPath);
        }
      } catch (cleanupError) {
        Logger.debug(TAG, `Daily background temporary file cleanup failed: ${String(cleanupError)}`);
      }
      return undefined;
    }
  }
}
