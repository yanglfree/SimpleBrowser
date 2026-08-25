/**
 * An inbound link is intentionally kept in memory only. A share target must not
 * become a browsing-history side effect before the reader chooses an action.
 */
export enum BrowseDisposition {
  Normal = 0,
  Private = 1,
  Disposable = 2
}

export enum ExternalOpenAction {
  CleanOpen = 0,
  PrivateOpen = 1,
  ReadAndClose = 2,
  SaveArticle = 3
}

export interface ExternalOpenRequest {
  id: string;
  rawUrl: string;
  cleanUrl: string;
  title: string;
  sourceApp: string;
  disposition: BrowseDisposition;
  autoReader: boolean;
  shouldSave: boolean;
  removedTrackingParameters: string[];
}

interface QueryPart {
  name: string;
  raw: string;
}

const MARKETING_PARAMETERS: string[] = [
  'fbclid',
  'gclid',
  'msclkid',
  'mc_cid',
  'mc_eid',
  'igshid',
  '_ga',
  '_gl'
];

export function createExternalOpenRequest(
  rawUrl: string,
  title: string = '',
  now: number = Date.now(),
  sourceApp: string = ''
): ExternalOpenRequest | undefined {
  const normalized: string = rawUrl.trim();
  if (!isHttpUrl(normalized)) {
    return undefined;
  }
  const split: number = normalized.indexOf('#');
  const beforeFragment: string = split >= 0 ? normalized.substring(0, split) : normalized;
  const fragment: string = split >= 0 ? normalized.substring(split) : '';
  const queryStart: number = beforeFragment.indexOf('?');
  if (queryStart < 0) {
    return request(now, normalized, normalized, title, sourceApp, []);
  }
  const base: string = beforeFragment.substring(0, queryStart);
  const query: string = beforeFragment.substring(queryStart + 1);
  const retained: string[] = [];
  const removed: string[] = [];
  for (const part of query.split('&')) {
    const parsed: QueryPart = parseQueryPart(part);
    if (isExplicitMarketingParameter(parsed.name)) {
      removed.push(parsed.name);
    } else if (part.length > 0) {
      retained.push(parsed.raw);
    }
  }
  const suffix: string = retained.length > 0 ? `?${retained.join('&')}` : '';
  return request(now, normalized, `${base}${suffix}${fragment}`, title, sourceApp, removed);
}

export function restoreTrackingParameters(request: ExternalOpenRequest): string {
  return request.rawUrl;
}

export function dispositionForExternalAction(action: ExternalOpenAction): BrowseDisposition {
  if (action === ExternalOpenAction.PrivateOpen) {
    return BrowseDisposition.Private;
  }
  if (action === ExternalOpenAction.ReadAndClose) {
    return BrowseDisposition.Disposable;
  }
  return BrowseDisposition.Normal;
}

export function withExternalOpenAction(
  request: ExternalOpenRequest,
  action: ExternalOpenAction
): ExternalOpenRequest {
  return {
    id: request.id,
    rawUrl: request.rawUrl,
    cleanUrl: request.cleanUrl,
    title: request.title,
    sourceApp: request.sourceApp,
    disposition: dispositionForExternalAction(action),
    autoReader: action === ExternalOpenAction.ReadAndClose,
    shouldSave: action === ExternalOpenAction.SaveArticle,
    removedTrackingParameters: request.removedTrackingParameters.slice(0)
  };
}

export function extractSharedUrl(uri: string | undefined, parameters: Record<string, Object> | undefined): string {
  const uriUrl: string = extractHttpUrl(uri ?? '');
  if (uriUrl.length > 0) {
    return uriUrl;
  }
  const keys: string[] = ['url', 'uri', 'link', 'shareUrl', 'text'];
  for (const key of keys) {
    const candidate: string = String(parameters?.[key] ?? '').trim();
    const candidateUrl: string = extractHttpUrl(candidate);
    if (candidateUrl.length > 0) {
      return candidateUrl;
    }
  }
  return '';
}

export function extractDroppedUrl(candidates: string[]): string {
  for (const candidate of candidates) {
    const url: string = extractHttpUrl(candidate);
    if (url.length > 0) {
      return url;
    }
  }
  return '';
}

export function extractDroppedInput(candidates: string[]): string {
  const url: string = extractDroppedUrl(candidates);
  if (url.length > 0) {
    return url;
  }
  for (const candidate of candidates) {
    const text: string = candidate.trim();
    if (text.length > 0) {
      return text.substring(0, 2048);
    }
  }
  return '';
}

function request(
  now: number,
  rawUrl: string,
  cleanUrl: string,
  title: string,
  sourceApp: string,
  removedTrackingParameters: string[]
): ExternalOpenRequest {
  return {
    id: `external-${now}`,
    rawUrl: rawUrl,
    cleanUrl: cleanUrl,
    title: title.trim(),
    sourceApp: sourceApp.trim(),
    disposition: BrowseDisposition.Normal,
    autoReader: false,
    shouldSave: false,
    removedTrackingParameters: removedTrackingParameters.slice(0)
  };
}

function parseQueryPart(raw: string): QueryPart {
  const equals: number = raw.indexOf('=');
  const encodedName: string = equals >= 0 ? raw.substring(0, equals) : raw;
  let name: string = encodedName;
  try {
    name = decodeURIComponent(encodedName.replace(/\+/g, ' '));
  } catch (_error) {
    // An invalid encoding is not a marketing signal and must be kept intact.
  }
  return {
    name: name.toLowerCase(),
    raw: raw
  };
}

function isExplicitMarketingParameter(name: string): boolean {
  return name.startsWith('utm_') || MARKETING_PARAMETERS.includes(name);
}

function isHttpUrl(value: string): boolean {
  return /^https?:\/\/[^\s/?#]+/i.test(value.trim());
}

function extractHttpUrl(value: string): string {
  const match: RegExpMatchArray | null = value.trim().match(/https?:\/\/[^\s<>"']+/i);
  if (match === null) {
    return '';
  }
  const candidate: string = match[0].replace(/[\])}>.,;!，。；！]+$/g, '');
  return isHttpUrl(candidate) ? candidate : '';
}
