const MIN_SHORTCUT_ICON_PIXELS: number = 16;
const CACHE_TTL_MS: number = 14 * 24 * 60 * 60 * 1000;

export function faviconCacheFileName(host: string): string {
  const safe: string = host.toLowerCase().replace(/[^a-z0-9.-]/g, '_');
  return safe.length > 0 ? `${safe}.icon` : '';
}

function isSvgBytes(bytes: Uint8Array): boolean {
  if (bytes.length < 4) {
    return false;
  }
  const len: number = Math.min(bytes.length, 512);
  let head: string = '';
  for (let i = 0; i < len; i += 1) {
    head += String.fromCharCode(bytes[i]);
  }
  return head.includes('<svg') || (head.includes('<?xml') && head.includes('<svg'));
}

export function looksLikeIconData(bytes: Uint8Array): boolean {
  if (bytes.length < 4) {
    return false;
  }
  if (isSvgBytes(bytes)) {
    return true;
  }
  if (bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e && bytes[3] === 0x47) {
    return true;
  }
  if (bytes[0] === 0x00 && bytes[1] === 0x00 &&
    (bytes[2] === 0x01 || bytes[2] === 0x02) && bytes[3] === 0x00) {
    return true;
  }
  if (bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) {
    return true;
  }
  if (bytes[0] === 0x47 && bytes[1] === 0x49 && bytes[2] === 0x46 && bytes[3] === 0x38) {
    return true;
  }
  if (bytes[0] === 0x52 && bytes[1] === 0x49 && bytes[2] === 0x46 && bytes[3] === 0x46) {
    return true;
  }
  return bytes[0] === 0x42 && bytes[1] === 0x4d;
}

function bigEndian16(bytes: Uint8Array, offset: number): number {
  return (bytes[offset] << 8) | bytes[offset + 1];
}

function littleEndian16(bytes: Uint8Array, offset: number): number {
  return bytes[offset] | (bytes[offset + 1] << 8);
}

function bigEndian32(bytes: Uint8Array, offset: number): number {
  return (bytes[offset] * 0x1000000) + (bytes[offset + 1] << 16) +
    (bytes[offset + 2] << 8) + bytes[offset + 3];
}

function littleEndian32(bytes: Uint8Array, offset: number): number {
  return bytes[offset] + (bytes[offset + 1] << 8) +
    (bytes[offset + 2] << 16) + (bytes[offset + 3] * 0x1000000);
}

function icoPixelSize(bytes: Uint8Array): number {
  if (bytes.length < 22) {
    return 0;
  }
  const count: number = littleEndian16(bytes, 4);
  let largest: number = 0;
  for (let index: number = 0; index < count; index += 1) {
    const offset: number = 6 + index * 16;
    if (offset + 15 >= bytes.length) {
      break;
    }
    const width: number = bytes[offset] === 0 ? 256 : bytes[offset];
    const height: number = bytes[offset + 1] === 0 ? 256 : bytes[offset + 1];
    largest = Math.max(largest, Math.min(width, height));
  }
  return largest;
}

function jpegPixelSize(bytes: Uint8Array): number {
  let offset: number = 2;
  while (offset + 8 < bytes.length) {
    if (bytes[offset] !== 0xff) {
      offset += 1;
      continue;
    }
    const marker: number = bytes[offset + 1];
    const isStartOfFrame: boolean = (marker >= 0xc0 && marker <= 0xc3) ||
      (marker >= 0xc5 && marker <= 0xc7) || (marker >= 0xc9 && marker <= 0xcb) ||
      (marker >= 0xcd && marker <= 0xcf);
    if (isStartOfFrame) {
      return Math.min(bigEndian16(bytes, offset + 5), bigEndian16(bytes, offset + 7));
    }
    if (marker === 0xd8 || marker === 0xd9) {
      offset += 2;
      continue;
    }
    const segmentLength: number = bigEndian16(bytes, offset + 2);
    if (segmentLength < 2) {
      break;
    }
    offset += segmentLength + 2;
  }
  return 0;
}

function webpPixelSize(bytes: Uint8Array): number {
  if (bytes.length < 30) {
    return 0;
  }
  const variant: string = String.fromCharCode(bytes[12], bytes[13], bytes[14], bytes[15]);
  if (variant === 'VP8X') {
    const width: number = 1 + bytes[24] + (bytes[25] << 8) + (bytes[26] << 16);
    const height: number = 1 + bytes[27] + (bytes[28] << 8) + (bytes[29] << 16);
    return Math.min(width, height);
  }
  if (variant === 'VP8L' && bytes[20] === 0x2f) {
    const width: number = 1 + bytes[21] + ((bytes[22] & 0x3f) << 8);
    const height: number = 1 + ((bytes[22] & 0xc0) >> 6) + (bytes[23] << 2) +
      ((bytes[24] & 0x0f) << 10);
    return Math.min(width, height);
  }
  if (variant === 'VP8 ' && bytes[23] === 0x9d && bytes[24] === 0x01 && bytes[25] === 0x2a) {
    return Math.min(littleEndian16(bytes, 26) & 0x3fff, littleEndian16(bytes, 28) & 0x3fff);
  }
  return 0;
}

export function iconPixelSize(bytes: Uint8Array): number {
  if (!looksLikeIconData(bytes)) {
    return 0;
  }
  if (isSvgBytes(bytes)) {
    return 512;
  }
  if (bytes[0] === 0x89 && bytes.length >= 24) {
    return Math.min(bigEndian32(bytes, 16), bigEndian32(bytes, 20));
  }
  if (bytes[0] === 0x00 && bytes[1] === 0x00) {
    return icoPixelSize(bytes);
  }
  if (bytes[0] === 0xff && bytes[1] === 0xd8) {
    return jpegPixelSize(bytes);
  }
  if (bytes[0] === 0x47 && bytes.length >= 10) {
    return Math.min(littleEndian16(bytes, 6), littleEndian16(bytes, 8));
  }
  if (bytes[0] === 0x52 && bytes.length >= 30) {
    return webpPixelSize(bytes);
  }
  if (bytes[0] === 0x42 && bytes.length >= 26) {
    return Math.min(littleEndian32(bytes, 18), littleEndian32(bytes, 22));
  }
  return 0;
}

export function isShortcutIconLargeEnough(bytes: Uint8Array): boolean {
  return iconPixelSize(bytes) >= MIN_SHORTCUT_ICON_PIXELS;
}

export function isCachedIconFresh(modifiedAtMs: number, nowMs: number): boolean {
  return modifiedAtMs > 0 && nowMs - modifiedAtMs < CACHE_TTL_MS;
}

export function faviconFileUri(path: string): string {
  return path.length > 0 ? `file://${path}` : '';
}
