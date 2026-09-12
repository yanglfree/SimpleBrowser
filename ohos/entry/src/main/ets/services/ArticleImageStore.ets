import { http } from '@kit.NetworkKit';
import fs from '@ohos.file.fs';
import { ArticleImageAsset } from '../models/ArticleLibraryModels';
import { Logger } from '../utils/Logger';

const TAG: string = 'ArticleImageStore';
const MAX_IMAGE_COUNT: number = 30;
const MAX_IMAGE_BYTES: number = 5 * 1024 * 1024;
const MAX_TOTAL_IMAGE_BYTES: number = 20 * 1024 * 1024;
const IMAGE_TIME_BUDGET_MS: number = 15000;

export interface ArticleImageStoreResult {
  savedCount: number;
  failedCount: number;
}

export function isPersistableArticleImage(asset: ArticleImageAsset): boolean {
  return /^https?:\/\//i.test(asset.url) && /^image-\d+\.(jpg|jpeg|png|gif|webp|avif|svg)$/i.test(asset.fileName);
}

/** Downloads non-authenticated article images into the article's private directory. */
export class ArticleImageStore {
  static async persist(images: ArticleImageAsset[], directory: string): Promise<ArticleImageStoreResult> {
    let savedCount: number = 0;
    let failedCount: number = Math.max(0, images.length - MAX_IMAGE_COUNT);
    const deadline: number = Date.now() + IMAGE_TIME_BUDGET_MS;
    let totalBytes: number = 0;
    for (const image of images.slice(0, MAX_IMAGE_COUNT)) {
      if (!isPersistableArticleImage(image) || Date.now() >= deadline || totalBytes >= MAX_TOTAL_IMAGE_BYTES) {
        failedCount += 1;
        continue;
      }
      const bytes: Uint8Array | undefined = await ArticleImageStore.fetch(image.url, deadline - Date.now());
      if (bytes === undefined || totalBytes + bytes.length > MAX_TOTAL_IMAGE_BYTES) {
        failedCount += 1;
        continue;
      }
      if (await ArticleImageStore.write(`${directory}/${image.fileName}`, bytes)) {
        savedCount += 1;
        totalBytes += bytes.length;
      } else {
        failedCount += 1;
      }
    }
    return { savedCount: savedCount, failedCount: failedCount };
  }

  private static async fetch(url: string, remainingMs: number): Promise<Uint8Array | undefined> {
    const request: http.HttpRequest = http.createHttp();
    try {
      const response: http.HttpResponse = await request.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: Math.max(1, Math.min(5000, remainingMs)),
        readTimeout: Math.max(1, Math.min(5000, remainingMs)),
        maxLimit: MAX_IMAGE_BYTES,
        header: { 'accept': 'image/*' }
      });
      const status: number = Number(response.responseCode);
      if (status < 200 || status >= 300 || !(response.result instanceof ArrayBuffer)) {
        return undefined;
      }
      const bytes: Uint8Array = new Uint8Array(response.result as ArrayBuffer);
      return bytes.length > 0 && bytes.length <= MAX_IMAGE_BYTES ? bytes : undefined;
    } catch (error) {
      Logger.warn(TAG, `Article image fetch failed: ${String(error)}`);
      return undefined;
    } finally {
      request.destroy();
    }
  }

  private static async write(path: string, bytes: Uint8Array): Promise<boolean> {
    try {
      const file: fs.File = await fs.open(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      try {
        await fs.write(file.fd, bytes.buffer as ArrayBuffer);
      } finally {
        await fs.close(file.fd);
      }
      return true;
    } catch (error) {
      Logger.warn(TAG, `Article image write failed: ${String(error)}`);
      return false;
    }
  }
}
