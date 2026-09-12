export const BING_DAILY_ARCHIVE_URL: string =
  'https://www.bing.com/HPImageArchive.aspx?format=js&idx=0&n=1&mkt=zh-CN';

interface BingArchiveImage {
  url?: string;
}

interface BingArchiveResponse {
  images?: BingArchiveImage[];
}

export function resolveBingDailyImageUrl(payload: string): string | undefined {
  try {
    const archive: BingArchiveResponse = JSON.parse(payload) as BingArchiveResponse;
    const path: string | undefined = archive.images?.[0]?.url;
    if (path === undefined || !/^\/th\?id=[A-Za-z0-9._%-]+(?:&[A-Za-z0-9._%=&-]+)*$/.test(path)) {
      return undefined;
    }
    return `https://www.bing.com${path}`;
  } catch (_error) {
    return undefined;
  }
}

export function isDailyWallpaperCacheFresh(modifiedAtMs: number, nowMs: number): boolean {
  if (modifiedAtMs <= 0 || nowMs < modifiedAtMs) {
    return false;
  }
  const modifiedAt: Date = new Date(modifiedAtMs);
  const now: Date = new Date(nowMs);
  return modifiedAt.getFullYear() === now.getFullYear() &&
    modifiedAt.getMonth() === now.getMonth() &&
    modifiedAt.getDate() === now.getDate();
}

export function isSupportedDailyWallpaper(bytes: Uint8Array): boolean {
  return bytes.length >= 4 && bytes[0] === 0xFF && bytes[1] === 0xD8 &&
    bytes[bytes.length - 2] === 0xFF && bytes[bytes.length - 1] === 0xD9;
}
