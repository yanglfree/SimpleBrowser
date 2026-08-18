import { rawHost } from '../utils/UrlUtils';

const MAX_METADATA_CANDIDATES: number = 8;

interface FaviconMetadataCandidate {
  url: string;
  score: number;
  order: number;
}

/** Site-owned fallback endpoints, ordered from likely high-resolution artwork to legacy favicon. */
export function faviconCandidates(url: string): string[] {
  const host: string = rawHost(url);
  if (host.length === 0) {
    return [];
  }
  const scheme: string = url.startsWith('http://') ? 'http' : 'https';
  return [
    `${scheme}://${host}/apple-touch-icon.png`,
    `${scheme}://${host}/apple-touch-icon-precomposed.png`,
    `${scheme}://${host}/favicon.ico`
  ];
}

function linkAttribute(tag: string, name: string): string {
  const expression: RegExp = new RegExp(
    `${name}\\s*=\\s*(?:"([^"]*)"|'([^']*)'|([^\\s"'=<>]+))`,
    'i'
  );
  const match: RegExpExecArray | null = expression.exec(tag);
  if (match === null) {
    return '';
  }
  return match[1] ?? match[2] ?? match[3] ?? '';
}

function normalizeAbsoluteUrl(url: string): string {
  const schemeEnd: number = url.indexOf('://');
  if (schemeEnd < 0) {
    return '';
  }
  const pathStart: number = url.indexOf('/', schemeEnd + 3);
  if (pathStart < 0) {
    return url;
  }
  const origin: string = url.substring(0, pathStart);
  const suffix: string = url.substring(pathStart);
  const queryStart: number = suffix.search(/[?#]/);
  const path: string = queryStart >= 0 ? suffix.substring(0, queryStart) : suffix;
  const tail: string = queryStart >= 0 ? suffix.substring(queryStart) : '';
  const segments: string[] = [];
  for (const segment of path.split('/')) {
    if (segment.length === 0 || segment === '.') {
      continue;
    }
    if (segment === '..') {
      segments.pop();
    } else {
      segments.push(segment);
    }
  }
  return `${origin}/${segments.join('/')}${tail}`;
}

function resolveIconUrl(href: string, pageUrl: string): string {
  const trimmed: string = href.trim();
  if (trimmed.startsWith('https://') || trimmed.startsWith('http://')) {
    return normalizeAbsoluteUrl(trimmed);
  }
  const host: string = rawHost(pageUrl);
  if (host.length === 0 || trimmed.length === 0 || trimmed.startsWith('data:')) {
    return '';
  }
  const scheme: string = pageUrl.startsWith('http://') ? 'http' : 'https';
  if (trimmed.startsWith('//')) {
    return normalizeAbsoluteUrl(`${scheme}:${trimmed}`);
  }
  const origin: string = `${scheme}://${host}`;
  if (trimmed.startsWith('/')) {
    return normalizeAbsoluteUrl(`${origin}${trimmed}`);
  }
  const cleanPage: string = pageUrl.split('#')[0].split('?')[0];
  const slash: number = cleanPage.lastIndexOf('/');
  const base: string = slash >= scheme.length + 3 + host.length
    ? cleanPage.substring(0, slash + 1)
    : `${origin}/`;
  return normalizeAbsoluteUrl(`${base}${trimmed}`);
}

function declaredIconSize(sizes: string): number {
  const matches: RegExpMatchArray | null = sizes.match(/(\d+)x(\d+)/gi);
  if (matches === null) {
    return 0;
  }
  let largest: number = 0;
  for (const value of matches) {
    const parts: string[] = value.toLowerCase().split('x');
    largest = Math.max(largest, Math.min(Number(parts[0]), Number(parts[1])));
  }
  return largest;
}

/** Extracts page-declared icons by size; touch-icon status only breaks equal-size ties. */
export function faviconMetadataCandidates(html: string, pageUrl: string): string[] {
  const candidates: FaviconMetadataCandidate[] = [];
  const seen: Set<string> = new Set();
  const expression: RegExp = /<link\b[^>]*>/gi;
  let match: RegExpExecArray | null = expression.exec(html);
  let order: number = 0;
  while (match !== null) {
    const tag: string = match[0];
    const rel: string = linkAttribute(tag, 'rel').toLowerCase();
    const type: string = linkAttribute(tag, 'type').toLowerCase();
    const url: string = resolveIconUrl(linkAttribute(tag, 'href'), pageUrl);
    const isSupportedType: boolean = type.length === 0 || type.includes('png') ||
      type.includes('icon') || type.includes('jpeg') || type.includes('webp');
    if (rel.includes('icon') && isSupportedType && url.length > 0 && !seen.has(url)) {
      const size: number = declaredIconSize(linkAttribute(tag, 'sizes'));
      const touchTieBreak: number = rel.includes('apple-touch-icon') ? 1 : 0;
      candidates.push({ url: url, score: size * 2 + touchTieBreak, order: order });
      seen.add(url);
      order += 1;
    }
    match = expression.exec(html);
  }
  candidates.sort((left: FaviconMetadataCandidate, right: FaviconMetadataCandidate): number => {
    return right.score - left.score || left.order - right.order;
  });
  return candidates.slice(0, MAX_METADATA_CANDIDATES)
    .map((candidate: FaviconMetadataCandidate): string => candidate.url);
}
