import { HOME_URL, TRACKER_URL_PATTERNS } from '../constants/AppConstants';
import { SearchEngine } from '../models/BrowserModels';

const SEARCH_ENDPOINTS: string[] = [
  'https://www.bing.com/search?q=',
  'https://m.baidu.com/s?word=',
  'https://www.google.com/search?q=',
  'https://duckduckgo.com/?q='
];

interface SearchPrefix {
  prefix: string;
  engine: SearchEngine;
}

const SEARCH_PREFIXES: SearchPrefix[] = [
  { prefix: 'g', engine: SearchEngine.Google },
  { prefix: 'b', engine: SearchEngine.Baidu },
  { prefix: 'ddg', engine: SearchEngine.DuckDuckGo },
  { prefix: 'bing', engine: SearchEngine.Bing }
];

export function searchEndpoint(engine: SearchEngine): string {
  const index: number = engine as number;
  return index >= 0 && index < SEARCH_ENDPOINTS.length ? SEARCH_ENDPOINTS[index] : SEARCH_ENDPOINTS[0];
}

export function isHomeUrl(url: string): boolean {
  return url.length === 0 || url === HOME_URL;
}

function hasExplicitScheme(value: string): boolean {
  return value.match(/^[a-z][a-z0-9+.-]*:\/\//i) !== null;
}

function validPort(value: string): boolean {
  if (value.length === 0 || value.match(/^\d+$/) === null) {
    return false;
  }
  const port: number = Number(value);
  return port > 0 && port <= 65535;
}

function validIpv4(host: string): boolean {
  const parts: string[] = host.split('.');
  if (parts.length !== 4) {
    return false;
  }
  return parts.every((part: string): boolean => {
    if (part.length === 0 || part.match(/^\d{1,3}$/) === null) {
      return false;
    }
    const octet: number = Number(part);
    return octet >= 0 && octet <= 255;
  });
}

function validDomain(host: string): boolean {
  if (host.length > 253 || host.startsWith('.') || host.endsWith('.')) {
    return false;
  }
  const labels: string[] = host.split('.');
  if (labels.length < 2) {
    return false;
  }
  return labels.every((label: string): boolean => {
    return label.length > 0 && label.length <= 63 && !label.startsWith('-') && !label.endsWith('-') &&
      label.match(/^[^\s\/:?#.]+$/) !== null;
  });
}

function addressHost(value: string): string {
  const boundary: number = value.search(/[/?#]/);
  const authority: string = boundary < 0 ? value : value.substring(0, boundary);
  if (authority.startsWith('[')) {
    const bracket: number = authority.indexOf(']');
    if (bracket <= 1) {
      return '';
    }
    const suffix: string = authority.substring(bracket + 1);
    return suffix.length === 0 || (suffix.startsWith(':') && validPort(suffix.substring(1)))
      ? authority.substring(0, bracket + 1)
      : '';
  }
  const firstColon: number = authority.indexOf(':');
  const lastColon: number = authority.lastIndexOf(':');
  if (firstColon >= 0) {
    if (firstColon !== lastColon || !validPort(authority.substring(lastColon + 1))) {
      return '';
    }
    return authority.substring(0, lastColon);
  }
  return authority;
}

function isAddressHost(host: string): boolean {
  const lower: string = host.toLowerCase();
  if (lower === 'localhost') {
    return true;
  }
  if (host.startsWith('[') && host.endsWith(']')) {
    return host.substring(1, host.length - 1).includes(':');
  }
  const numericDotted: boolean = host.match(/^\d+(\.\d+){3}$/) !== null;
  return numericDotted ? validIpv4(host) : validDomain(host);
}

/** True when the input looks like an address rather than a search phrase. */
export function looksLikeUrl(input: string): boolean {
  const value: string = input.trim();
  if (value.length === 0 || value.match(/\s/) !== null) {
    return false;
  }
  if (hasExplicitScheme(value)) {
    return true;
  }
  return isAddressHost(addressHost(value));
}

/** Returns a navigable URL, or an empty string when the value is a search phrase. */
export function normalizeUrlInput(input: string): string {
  const value: string = input.trim();
  if (!looksLikeUrl(value)) {
    return '';
  }
  if (hasExplicitScheme(value)) {
    return value;
  }
  const host: string = addressHost(value).toLowerCase();
  const localOrIp: boolean = host === 'localhost' || host.startsWith('[') || validIpv4(host);
  return `${localOrIp ? 'http' : 'https'}://${value}`;
}

export function normalizeAddress(input: string, engine: SearchEngine, customTemplate: string = ''): string {
  const value: string = input.trim();
  if (value.length === 0) {
    return HOME_URL;
  }
  const normalizedUrl: string = normalizeUrlInput(value);
  if (normalizedUrl.length > 0) {
    return normalizedUrl;
  }
  return searchUrl(value, engine, customTemplate);
}

export function searchUrl(query: string, engine: SearchEngine, customTemplate: string = ''): string {
  const value: string = query.trim();
  const parts: string[] = value.split(/\s+/);
  let resolvedEngine: SearchEngine = engine;
  let searchTerms: string = value;
  let hasPrefix: boolean = false;
  if (parts.length > 1) {
    const prefix: SearchPrefix | undefined = SEARCH_PREFIXES.find(
      (item: SearchPrefix): boolean => item.prefix === parts[0].toLowerCase()
    );
    if (prefix !== undefined) {
      resolvedEngine = prefix.engine;
      searchTerms = value.substring(parts[0].length).trim();
      hasPrefix = true;
    }
  }
  const template: string = customTemplate.trim();
  if (!hasPrefix && template.includes('%s')) {
    return template.replace('%s', encodeURIComponent(searchTerms));
  }
  return `${searchEndpoint(resolvedEngine)}${encodeURIComponent(searchTerms)}`;
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

/**
 * The label a tab carries. A page that never rendered — offline, an error, a bare
 * directory listing — is reported by the kernel with its own URL as the title, and
 * a raw URL with its query string is unreadable in the width a tab has. Fall back
 * to the host, which is what the tab is about either way.
 *
 * The test is deliberately narrow: a title is only treated as a URL when it carries
 * a scheme or opens with the page's own host, so a legitimate `Node.js` or
 * `and/or` keeps the title its author wrote.
 */
export function tabDisplayTitle(title: string, url: string): string {
  const value: string = title.trim();
  if (value.length === 0 || value === url.trim()) {
    return displayHost(url);
  }
  if (value.match(/^[a-z][a-z0-9+.-]*:\/\//i) !== null) {
    return displayHost(url);
  }
  const host: string = rawHost(url);
  if (host.length > 0 && value.includes('/') && value.toLowerCase().startsWith(host)) {
    return displayHost(url);
  }
  return value;
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
