export interface CookiePair {
  name: string;
  value: string;
}

/** Thirty days. Long enough to survive process death; short enough to expire abandoned logins. */
export const SESSION_COOKIE_MAX_AGE_SEC: number = 30 * 24 * 60 * 60;

/**
 * ArkWeb on tablet, 2-in-1 and PC refuses to write session cookies to disk,
 * even through saveCookieSync. Phone builds persist them. Matching Huawei's
 * documented device split keeps promotion off where the kernel already does it.
 */
export function deviceDropsSessionCookies(deviceType: string): boolean {
  return deviceType === 'tablet' || deviceType === '2in1' || deviceType === 'pc';
}

export function originOf(url: string): string {
  const match: RegExpMatchArray | null = url.trim().match(/^(https?):\/\/[^/?#]+/i);
  return match === null ? '' : match[0];
}

export function isHttpsUrl(url: string): boolean {
  return url.trim().toLowerCase().startsWith('https:');
}

/**
 * Origins to re-persist, tabs first so the page the user is looking at wins
 * the cap. History covers OAuth hosts that are no longer the tab URL.
 */
export function cookieFlushUrls(tabUrls: string[], historyUrls: string[], limit: number): string[] {
  const seen: Record<string, boolean> = {};
  const urls: string[] = [];
  const sources: string[] = tabUrls.concat(historyUrls);
  const cap: number = limit < 1 ? 1 : limit;
  for (let index: number = 0; index < sources.length; index += 1) {
    const origin: string = originOf(sources[index]);
    if (origin.length === 0 || seen[origin] === true) {
      continue;
    }
    seen[origin] = true;
    urls.push(`${origin}/`);
    if (urls.length >= cap) {
      break;
    }
  }
  return urls;
}

export function parseCookiePairs(header: string): CookiePair[] {
  const pairs: CookiePair[] = [];
  const parts: string[] = header.split(';');
  for (let index: number = 0; index < parts.length; index += 1) {
    const item: string = parts[index].trim();
    const eq: number = item.indexOf('=');
    if (eq <= 0) {
      continue;
    }
    const name: string = item.substring(0, eq).trim();
    if (name.length === 0 || name.toLowerCase() === 'dpkeep') {
      continue;
    }
    pairs.push({
      name: name,
      value: item.substring(eq + 1).trim()
    });
  }
  return pairs;
}

/**
 * Set-Cookie line that turns a session cookie into a persistent one. Path=/
 * matches the usual login cookie; Secure follows the source URL so HTTP sites
 * are not upgraded into a flag they cannot send.
 */
export function persistentSetCookie(name: string, value: string, isHttps: boolean): string {
  const line: string = `${name}=${value}; Max-Age=${SESSION_COOKIE_MAX_AGE_SEC}; Path=/`;
  return isHttps ? `${line}; Secure` : line;
}
