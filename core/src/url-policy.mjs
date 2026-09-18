import { HOME_URL, SearchEngine } from './constants.mjs';

const SEARCH_ENDPOINTS = [
  'https://www.bing.com/search?q=',
  'https://m.baidu.com/s?word=',
  'https://www.google.com/search?q=',
  'https://duckduckgo.com/?q='
];

const SEARCH_PREFIXES = [
  { prefix: 'g', engine: SearchEngine.Google },
  { prefix: 'b', engine: SearchEngine.Baidu },
  { prefix: 'ddg', engine: SearchEngine.DuckDuckGo },
  { prefix: 'bing', engine: SearchEngine.Bing }
];

export function searchEndpoint(engine) {
  const index = engine;
  return index >= 0 && index < SEARCH_ENDPOINTS.length ? SEARCH_ENDPOINTS[index] : SEARCH_ENDPOINTS[0];
}

export function isHomeUrl(url) {
  return url.length === 0 || url === HOME_URL;
}

function hasExplicitScheme(value) {
  return value.match(/^[a-z][a-z0-9+.-]*:\/\//i) !== null;
}

function validPort(value) {
  if (value.length === 0 || value.match(/^\d+$/) === null) {
    return false;
  }
  const port = Number(value);
  return port > 0 && port <= 65535;
}

function validIpv4(host) {
  const parts = host.split('.');
  if (parts.length !== 4) {
    return false;
  }
  return parts.every((part) => {
    if (part.length === 0 || part.match(/^\d{1,3}$/) === null) {
      return false;
    }
    const octet = Number(part);
    return octet >= 0 && octet <= 255;
  });
}

function validDomain(host) {
  if (host.length > 253 || host.startsWith('.') || host.endsWith('.')) {
    return false;
  }
  const labels = host.split('.');
  if (labels.length < 2) {
    return false;
  }
  return labels.every((label) => {
    return label.length > 0 && label.length <= 63 && !label.startsWith('-') && !label.endsWith('-') &&
      label.match(/^[^\s\/:?#.]+$/) !== null;
  });
}

function addressHost(value) {
  const boundary = value.search(/[/?#]/);
  const authority = boundary < 0 ? value : value.substring(0, boundary);
  if (authority.startsWith('[')) {
    const bracket = authority.indexOf(']');
    if (bracket <= 1) {
      return '';
    }
    const suffix = authority.substring(bracket + 1);
    return suffix.length === 0 || (suffix.startsWith(':') && validPort(suffix.substring(1)))
      ? authority.substring(0, bracket + 1)
      : '';
  }
  const firstColon = authority.indexOf(':');
  const lastColon = authority.lastIndexOf(':');
  if (firstColon >= 0) {
    if (firstColon !== lastColon || !validPort(authority.substring(lastColon + 1))) {
      return '';
    }
    return authority.substring(0, lastColon);
  }
  return authority;
}

function isAddressHost(host) {
  const lower = host.toLowerCase();
  if (lower === 'localhost') {
    return true;
  }
  if (host.startsWith('[') && host.endsWith(']')) {
    return host.substring(1, host.length - 1).includes(':');
  }
  const numericDotted = host.match(/^\d+(\.\d+){3}$/) !== null;
  return numericDotted ? validIpv4(host) : validDomain(host);
}

export function looksLikeUrl(input) {
  const value = input.trim();
  if (value.length === 0 || value.match(/\s/) !== null) {
    return false;
  }
  if (hasExplicitScheme(value)) {
    return true;
  }
  return isAddressHost(addressHost(value));
}

export function normalizeUrlInput(input) {
  const value = input.trim();
  if (!looksLikeUrl(value)) {
    return '';
  }
  if (hasExplicitScheme(value)) {
    return value;
  }
  const host = addressHost(value).toLowerCase();
  const localOrIp = host === 'localhost' || host.startsWith('[') || validIpv4(host);
  return `${localOrIp ? 'http' : 'https'}://${value}`;
}

export function searchUrl(query, engine, customTemplate = '') {
  const value = query.trim();
  const parts = value.split(/\s+/);
  let resolvedEngine = engine;
  let searchTerms = value;
  let hasPrefix = false;
  if (parts.length > 1) {
    const prefix = SEARCH_PREFIXES.find((item) => item.prefix === parts[0].toLowerCase());
    if (prefix !== undefined) {
      resolvedEngine = prefix.engine;
      searchTerms = value.substring(parts[0].length).trim();
      hasPrefix = true;
    }
  }
  const template = customTemplate.trim();
  if (!hasPrefix && template.includes('%s')) {
    return template.replace('%s', encodeURIComponent(searchTerms));
  }
  return `${searchEndpoint(resolvedEngine)}${encodeURIComponent(searchTerms)}`;
}

export function normalizeAddress(input, engine, customTemplate = '') {
  const value = input.trim();
  if (value.length === 0) {
    return HOME_URL;
  }
  const normalizedUrl = normalizeUrlInput(value);
  if (normalizedUrl.length > 0) {
    return normalizedUrl;
  }
  return searchUrl(value, engine, customTemplate);
}

export function displayHost(url) {
  if (isHomeUrl(url)) {
    return '';
  }
  const match = url.match(/^[a-z][a-z0-9+.-]*:\/\/([^/?#]+)/i);
  const host = match === null ? url : match[1];
  const withoutPort = host.split(':')[0];
  if (withoutPort.startsWith('www.')) {
    return withoutPort.substring(4);
  }
  if (withoutPort.startsWith('m.')) {
    return withoutPort.substring(2);
  }
  return withoutPort;
}

export function rawHost(url) {
  const match = url.match(/^[a-z][a-z0-9+.-]*:\/\/([^/?#]+)/i);
  if (match === null) {
    return '';
  }
  return match[1].split(':')[0].toLowerCase();
}

export function documentIdentity(url) {
  const trimmed = url.trim();
  if (trimmed.length === 0) {
    return '';
  }
  const hashIndex = trimmed.indexOf('#');
  return hashIndex >= 0 ? trimmed.substring(0, hashIndex) : trimmed;
}

export function urlHash(url) {
  const hashIndex = url.indexOf('#');
  return hashIndex >= 0 ? url.substring(hashIndex) : '';
}

export function isSameDocumentUrl(currentUrl, nextUrl) {
  const currentDoc = documentIdentity(currentUrl);
  const nextDoc = documentIdentity(nextUrl);
  return currentDoc.length > 0 && currentDoc === nextDoc;
}

export function isSameDocumentHashNavigation(currentUrl, nextUrl) {
  return isSameDocumentUrl(currentUrl, nextUrl) && urlHash(currentUrl) !== urlHash(nextUrl);
}
