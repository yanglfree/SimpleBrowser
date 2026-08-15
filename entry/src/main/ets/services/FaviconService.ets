import { common } from '@kit.AbilityKit';
import { http } from '@kit.NetworkKit';
import fs from '@ohos.file.fs';
import { rawHost } from '../utils/UrlUtils';
import { Logger } from '../utils/Logger';

const TAG: string = 'FaviconService';
const CACHE_DIRECTORY: string = 'favicons';
const MAX_ICON_BYTES: number = 256 * 1024;
const CONNECT_TIMEOUT_MS: number = 6000;
const READ_TIMEOUT_MS: number = 8000;
/**
 * A tile the user never revisits should not re-request its icon on every start
 * page, and a cached one should not go stale forever. Two weeks is the same
 * order as a bookmark's useful life and costs one request per site per fortnight.
 */
const CACHE_TTL_MS: number = 14 * 24 * 60 * 60 * 1000;

/**
 * Icon endpoints in the order they are worth trying. Everything is fetched from
 * the site itself: the usual third-party favicon proxies (Google's above all)
 * are not reachable from the mainland, so a proxy would fail for exactly the
 * sites the start page ships with.
 */
export function faviconCandidates(url: string): string[] {
  const host: string = rawHost(url);
  if (host.length === 0) {
    return [];
  }
  const scheme: string = url.startsWith('http://') ? 'http' : 'https';
  return [
    `${scheme}://${host}/favicon.ico`,
    `${scheme}://${host}/apple-touch-icon.png`,
    `${scheme}://${host}/apple-touch-icon-precomposed.png`
  ];
}

/** One file per host, with the separators a path cannot carry folded away. */
export function faviconCacheFileName(host: string): string {
  const safe: string = host.toLowerCase().replace(/[^a-z0-9.-]/g, '_');
  return safe.length > 0 ? `${safe}.icon` : '';
}

/**
 * Accepts what a favicon actually arrives as. A site that answers a missing
 * /favicon.ico with its HTML 404 page is the common failure, and it is only
 * detectable from the bytes: the content type on such a response is text/html
 * but plenty of correct icons are served as application/octet-stream.
 */
export function looksLikeIconData(bytes: Uint8Array): boolean {
  if (bytes.length < 4) {
    return false;
  }
  // PNG
  if (bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e && bytes[3] === 0x47) {
    return true;
  }
  // ICO / CUR: reserved 0, type 1 or 2
  if (bytes[0] === 0x00 && bytes[1] === 0x00 && (bytes[2] === 0x01 || bytes[2] === 0x02) && bytes[3] === 0x00) {
    return true;
  }
  // JPEG
  if (bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) {
    return true;
  }
  // GIF
  if (bytes[0] === 0x47 && bytes[1] === 0x49 && bytes[2] === 0x46 && bytes[3] === 0x38) {
    return true;
  }
  // RIFF/WEBP
  if (bytes[0] === 0x52 && bytes[1] === 0x49 && bytes[2] === 0x46 && bytes[3] === 0x46) {
    return true;
  }
  // BMP
  if (bytes[0] === 0x42 && bytes[1] === 0x4d) {
    return true;
  }
  return false;
}

export function isCachedIconFresh(modifiedAtMs: number, nowMs: number): boolean {
  return modifiedAtMs > 0 && nowMs - modifiedAtMs < CACHE_TTL_MS;
}

/** Image only accepts a sandbox file as a URI, never as a bare path. */
export function faviconFileUri(path: string): string {
  return path.length > 0 ? `file://${path}` : '';
}

/**
 * Real site icons for the start page tiles, cached on disk so a second launch
 * costs no request. Callers fall back to the lettered tile whenever this returns
 * an empty string — an icon is a nicety, never a precondition for the shortcut.
 */
export class FaviconService {
  private static directory: string = '';
  /** Hosts already resolved this session, path or the empty string for "no icon". */
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

  /**
   * Resolves to a `file://` URI ready for Image, or an empty string when the
   * site has no icon worth showing. Never throws: the tile has a working
   * fallback either way.
   */
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

  /** Forgets the session's negative results so a retry can reach the network. */
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
    for (const candidate of faviconCandidates(url)) {
      const bytes: Uint8Array | undefined = await FaviconService.fetchIcon(candidate);
      if (bytes !== undefined) {
        const uri: string = faviconFileUri(await FaviconService.writeIcon(path, bytes));
        FaviconService.resolved.set(host, uri);
        return uri;
      }
    }
    // Remembered as "no icon" for the session so a start page that redraws on
    // every tab change does not re-run three failed requests each time.
    FaviconService.resolved.set(host, '');
    return '';
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
        header: { 'accept': 'image/*' }
      });
      const code: number = Number(response.responseCode);
      if (code < 200 || code >= 300 || !(response.result instanceof ArrayBuffer)) {
        return undefined;
      }
      const bytes: Uint8Array = new Uint8Array(response.result as ArrayBuffer);
      if (bytes.length === 0 || bytes.length > MAX_ICON_BYTES || !looksLikeIconData(bytes)) {
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
