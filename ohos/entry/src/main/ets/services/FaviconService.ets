import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { http } from '@kit.NetworkKit';
import fs from '@ohos.file.fs';
import { rawHost } from '../utils/UrlUtils';
import { Logger } from '../utils/Logger';
import {
  faviconCacheFileName,
  faviconFileUri,
  isCachedIconFresh,
  isShortcutIconLargeEnough
} from './FaviconPolicy';
import { faviconCandidates, faviconMetadataCandidates } from './FaviconMetadataPolicy';

const TAG: string = 'FaviconService';
const CACHE_DIRECTORY: string = 'favicons-v3';
const MAX_ICON_BYTES: number = 256 * 1024;
const MAX_PAGE_CHARACTERS: number = 512 * 1024;
const CONNECT_TIMEOUT_MS: number = 6000;
const READ_TIMEOUT_MS: number = 8000;
const BROWSER_USER_AGENT: string = 'Mozilla/5.0 (Linux; HarmonyOS) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36';

/** Resolves clear site-owned artwork and caches it for start-page shortcut tiles. */
export class FaviconService {
  private static directory: string = '';
  private static resolved: Map<string, string> = new Map();
  private static inFlight: Map<string, Promise<string>> = new Map();

  static async initialize(context: common.UIAbilityContext): Promise<void> {
    if (FaviconService.directory.length > 0) {
      return;
    }
    const directory: string = `${context.cacheDir}/${CACHE_DIRECTORY}`;
    try {
      if (!await fs.access(directory)) {
        await fs.mkdir(directory);
      }
      FaviconService.directory = directory;
    } catch (error) {
      Logger.warn(TAG, `Favicon cache unavailable: ${String(error)}`);
    }
  }

  /** Returns a file URI for Image, or an empty string so the caller can show its letter tile. */
  static async iconFor(url: string): Promise<string> {
    const host: string = rawHost(url);
    if (host.length === 0 || FaviconService.directory.length === 0) {
      return '';
    }
    const remembered: string | undefined = FaviconService.resolved.get(host);
    if (remembered !== undefined) {
      return remembered;
    }
    const pending: Promise<string> | undefined = FaviconService.inFlight.get(host);
    if (pending !== undefined) {
      return pending;
    }
    const request: Promise<string> = FaviconService.resolve(host, url);
    FaviconService.inFlight.set(host, request);
    try {
      return await request;
    } finally {
      FaviconService.inFlight.delete(host);
    }
  }

  /** Forgets the session's negative result so an explicit retry can reach the network. */
  static forget(url: string): void {
    const host: string = rawHost(url);
    if (host.length > 0) {
      FaviconService.resolved.delete(host);
    }
  }

  private static async resolve(host: string, url: string): Promise<string> {
    const path: string = `${FaviconService.directory}/${faviconCacheFileName(host)}`;
    if (await FaviconService.isCacheUsable(path)) {
      const uri: string = faviconFileUri(path);
      FaviconService.resolved.set(host, uri);
      return uri;
    }
    const candidates: string[] = await FaviconService.candidatesFor(url);
    for (const candidate of candidates) {
      const bytes: Uint8Array | undefined = await FaviconService.fetchIcon(candidate);
      if (bytes !== undefined) {
        const uri: string = faviconFileUri(await FaviconService.writeIcon(path, bytes));
        FaviconService.resolved.set(host, uri);
        return uri;
      }
    }
    FaviconService.resolved.set(host, '');
    return '';
  }

  private static async candidatesFor(url: string): Promise<string[]> {
    const candidates: string[] = (await FaviconService.fetchMetadataCandidates(url))
      .concat(faviconCandidates(url));
    const seen: Set<string> = new Set();
    return candidates.filter((candidate: string): boolean => {
      if (seen.has(candidate)) {
        return false;
      }
      seen.add(candidate);
      return true;
    });
  }

  private static async fetchMetadataCandidates(url: string): Promise<string[]> {
    const request: http.HttpRequest = http.createHttp();
    try {
      const response: http.HttpResponse = await request.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: CONNECT_TIMEOUT_MS,
        readTimeout: READ_TIMEOUT_MS,
        header: {
          'accept': 'text/html,application/xhtml+xml',
          'user-agent': BROWSER_USER_AGENT
        }
      });
      const code: number = Number(response.responseCode);
      if (code < 200 || code >= 300) {
        return [];
      }
      const html: string = typeof response.result === 'string'
        ? response.result
        : new util.TextDecoder().decodeToString(new Uint8Array(response.result as ArrayBuffer));
      return faviconMetadataCandidates(html.substring(0, MAX_PAGE_CHARACTERS), url);
    } catch (error) {
      Logger.warn(TAG, `Favicon metadata fetch failed for ${url}: ${String(error)}`);
      return [];
    } finally {
      request.destroy();
    }
  }

  private static async isCacheUsable(path: string): Promise<boolean> {
    try {
      if (!await fs.access(path)) {
        return false;
      }
      const stat: fs.Stat = await fs.stat(path);
      return stat.size > 0 && isCachedIconFresh(stat.mtime * 1000, Date.now());
    } catch (error) {
      Logger.warn(TAG, `Cached icon unreadable: ${String(error)}`);
      return false;
    }
  }

  private static async fetchIcon(url: string): Promise<Uint8Array | undefined> {
    const request: http.HttpRequest = http.createHttp();
    try {
      const response: http.HttpResponse = await request.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: CONNECT_TIMEOUT_MS,
        readTimeout: READ_TIMEOUT_MS,
        header: {
          'accept': 'image/*',
          'user-agent': BROWSER_USER_AGENT
        }
      });
      const code: number = Number(response.responseCode);
      if (code < 200 || code >= 300 || !(response.result instanceof ArrayBuffer)) {
        return undefined;
      }
      const bytes: Uint8Array = new Uint8Array(response.result as ArrayBuffer);
      if (bytes.length === 0 || bytes.length > MAX_ICON_BYTES || !isShortcutIconLargeEnough(bytes)) {
        return undefined;
      }
      return bytes;
    } catch (error) {
      Logger.warn(TAG, `Favicon fetch failed for ${url}: ${String(error)}`);
      return undefined;
    } finally {
      request.destroy();
    }
  }

  private static async writeIcon(path: string, bytes: Uint8Array): Promise<string> {
    try {
      const file: fs.File = await fs.open(
        path,
        fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC
      );
      try {
        await fs.write(file.fd, bytes.buffer as ArrayBuffer);
      } finally {
        await fs.close(file.fd);
      }
      return path;
    } catch (error) {
      Logger.warn(TAG, `Failed to cache icon: ${String(error)}`);
      return '';
    }
  }
}
