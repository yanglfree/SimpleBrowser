import { HOME_URL, TRACKER_URL_PATTERNS } from '../constants/AppConstants';
import { SearchEngine } from '../models/BrowserModels';

const SEARCH_ENDPOINTS: string[] = [
  'https://www.bing.com/search?q=',
  'https://m.baidu.com/s?word=',
  'https://www.google.com/search?q=',
  'https://duckduckgo.com/?q='
];

export function searchEndpoint(engine: SearchEngine): string {
  const index: number = engine as number;
  return index >= 0 && index < SEARCH_ENDPOINTS.length ? SEARCH_ENDPOINTS[index] : SEARCH_ENDPOINTS[0];
}

export function isHomeUrl(url: string): boolean {
  return url.length === 0 || url === HOME_URL;
}

/** True when the input looks like an address rather than a search phrase. */
export function looksLikeUrl(input: string): boolean {
  const value: string = input.trim();
  if (value.length === 0 || value.includes(' ')) {
    return false;
  }
  if (value.includes('://') || value.startsWith('localhost')) {
    return true;
  }
  const dot: number = value.indexOf('.');
  return dot > 0 && dot < value.length - 1;
}

export function normalizeAddress(input: string, engine: SearchEngine): string {
  const value: string = input.trim();
  if (value.length === 0) {
    return HOME_URL;
  }
  if (value.includes('://')) {
    return value;
  }
  if (looksLikeUrl(value)) {
    return `https://${value}`;
  }
  return `${searchEndpoint(engine)}${encodeURIComponent(value)}`;
}

export function searchUrl(query: string, engine: SearchEngine): string {
  return `${searchEndpoint(engine)}${encodeURIComponent(query.trim())}`;
}

/** Host without the `www.`/`m.` prefix — what the capsule and cards display. */
export function displayHost(url: string): string {
  if (isHomeUrl(url)) {
    return '';
  }
  const match: RegExpMatchArray | null = url.match(/^[a-z][a-z0-9+.-]*:\/\/([^/?#]+)/i);
  const host: string = match === null ? url : match[1];
  const withoutPort: string = host.split(':')[0];
  if (withoutPort.startsWith('www.')) {
    return withoutPort.substring(4);
  }
  if (withoutPort.startsWith('m.')) {
    return withoutPort.substring(2);
  }
  return withoutPort;
}

/** Full host including any `www.` — the key used for per-site stats and allow-lists. */
export function rawHost(url: string): string {
  const match: RegExpMatchArray | null = url.match(/^[a-z][a-z0-9+.-]*:\/\/([^/?#]+)/i);
  if (match === null) {
    return '';
  }
  return match[1].split(':')[0].toLowerCase();
}

/** First character of a site name, used for the start-page tiles. */
export function siteBadge(title: string, url: string): string {
  const source: string = title.trim().length > 0 ? title.trim() : displayHost(url);
  return source.length === 0 ? '·' : source.substring(0, 1).toUpperCase();
}

export function isTrackerUrl(url: string): boolean {
  const value: string = url.toLowerCase();
  return TRACKER_URL_PATTERNS.some((pattern: string) => value.includes(pattern));
}
