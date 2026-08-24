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
  now: number = Date.now()
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
    return request(now, normalized, normalized, title, []);
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
  return request(now, normalized, `${base}${suffix}${fragment}`, title, removed);
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

export function extractSharedUrl(uri: string | undefined, parameters: Record<string, Object> | undefined): string {
  if (isHttpUrl(uri ?? '')) {
    return (uri ?? '').trim();
  }
  const keys: string[] = ['url', 'uri', 'link', 'shareUrl', 'text'];
  for (const key of keys) {
    const candidate: string = String(parameters?.[key] ?? '').trim();
    if (isHttpUrl(candidate)) {
      return candidate;
    }
  }
  return '';
}

function request(
  now: number,
  rawUrl: string,
  cleanUrl: string,
  title: string,
  removedTrackingParameters: string[]
): ExternalOpenRequest {
  return {
    id: `external-${now}`,
    rawUrl: rawUrl,
    cleanUrl: cleanUrl,
    title: title.trim(),
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
