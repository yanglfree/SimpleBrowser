import { rawHost } from '../utils/UrlUtils';

interface CosmeticRuleSet {
  selectors: string[];
  exceptions: string[];
}

/**
 * Safety valve. EasyList's generic hide section alone is ~13.5k selectors; a
 * subscription that grew far past that would cost more in stylesheet parsing
 * than it saves in hidden ads.
 */
const MAX_SELECTORS: number = 20000;
/** Payloads are keyed by host; a browsing session touches few hosts at a time. */
const PAYLOAD_CACHE_LIMIT: number = 24;

/** Compiles the selector subset of EasyList/AdGuard cosmetic rules. */
export class CosmeticFilterService {
  private generic: CosmeticRuleSet = { selectors: [], exceptions: [] };
  private byHost: Map<string, CosmeticRuleSet> = new Map();
  /** Generic selectors minus generic exceptions, resolved once on first use. */
  private genericSelectors: string[] | undefined;
  private payloadCache: Map<string, string> = new Map();

  private constructor() {}

  static compile(text: string): CosmeticFilterService {
    const service: CosmeticFilterService = new CosmeticFilterService();
    for (const rawLine of text.split('\n')) {
      service.addRule(rawLine.trim());
    }
    return service;
  }

  selectorsFor(pageUrl: string): string[] {
    const host: string = rawHost(pageUrl);
    const hostRules: CosmeticRuleSet[] = this.rulesForHost(host);
    const exceptions: Set<string> = new Set<string>();
    for (const rules of hostRules) {
      for (const selector of rules.exceptions) {
        exceptions.add(selector);
      }
    }

    const selectors: string[] = [];
    const seen: Set<string> = new Set<string>();
    for (const selector of this.resolvedGenericSelectors()) {
      if (!exceptions.has(selector) && !seen.has(selector)) {
        seen.add(selector);
        selectors.push(selector);
      }
    }
    for (const rules of hostRules) {
      for (const selector of rules.selectors) {
        if (!exceptions.has(selector) && !seen.has(selector)) {
          seen.add(selector);
          selectors.push(selector);
        }
      }
    }
    return selectors.length > MAX_SELECTORS ? selectors.slice(0, MAX_SELECTORS) : selectors;
  }

  scriptFor(pageUrl: string): string {
    const payload: string = this.payloadFor(rawHost(pageUrl));
    if (payload.length === 0) {
      return '';
    }
    // The stylesheet is assembled inside the page: sending selectors costs a
    // fraction of sending the expanded CSS across the bridge.
    return `(function(selectors) {
  var root = document.head || document.documentElement;
  if (!root) return 'no-root';
  var id = '__minimalBrowserCosmeticRules';
  var style = document.getElementById(id);
  if (!style) {
    style = document.createElement('style');
    style.id = id;
    root.appendChild(style);
  }
  var parts = [];
  for (var i = 0; i < selectors.length; i++) {
    parts.push(selectors[i] + '{display:none!important;}');
  }
  style.textContent = parts.join('');
  return JSON.stringify({ selectors: selectors.length });
})(${payload});`;
  }

  /**
   * Resolving a host walks its labels instead of scanning every domain in the
   * subscription, and the result is memoised: a full list holds tens of
   * thousands of domains, and page loads repeat the same handful of hosts.
   */
  private payloadFor(host: string): string {
    const cached: string | undefined = this.payloadCache.get(host);
    if (cached !== undefined) {
      return cached;
    }
    const selectors: string[] = this.selectorsFor(`https://${host}/`);
    const payload: string = selectors.length === 0 ? '' : JSON.stringify(selectors);
    if (this.payloadCache.size >= PAYLOAD_CACHE_LIMIT) {
      const oldest: string | undefined = this.payloadCache.keys().next().value as string | undefined;
      if (oldest !== undefined) {
        this.payloadCache.delete(oldest);
      }
    }
    this.payloadCache.set(host, payload);
    return payload;
  }

  /** `a.b.example.com` is served by rules filed under it, `b.example.com`, … */
  private rulesForHost(host: string): CosmeticRuleSet[] {
    const matches: CosmeticRuleSet[] = [];
    if (host.length === 0) {
      return matches;
    }
    const labels: string[] = host.split('.');
    for (let index: number = 0; index < labels.length; index += 1) {
      const rules: CosmeticRuleSet | undefined = this.byHost.get(labels.slice(index).join('.'));
      if (rules !== undefined) {
        matches.push(rules);
      }
    }
    return matches;
  }

  private resolvedGenericSelectors(): string[] {
    let resolved: string[] | undefined = this.genericSelectors;
    if (resolved === undefined) {
      const excluded: Set<string> = new Set<string>(this.generic.exceptions);
      resolved = this.generic.selectors.filter((selector: string): boolean => !excluded.has(selector));
      this.genericSelectors = resolved;
    }
    return resolved;
  }

  private addRule(line: string): void {
    if (line.length === 0 || line.startsWith('!') || line.startsWith('[')) {
      return;
    }
    const exceptionIndex: number = line.indexOf('#@#');
    const normalIndex: number = line.indexOf('##');
    const isException: boolean = exceptionIndex >= 0 &&
      (normalIndex < 0 || exceptionIndex < normalIndex);
    const markerIndex: number = isException ? exceptionIndex : normalIndex;
    if (markerIndex < 0) {
      return;
    }
    const selector: string = line.substring(markerIndex + (isException ? 3 : 2)).trim();
    if (!this.isSafeSelector(selector)) {
      return;
    }
    const domainText: string = line.substring(0, markerIndex).trim();
    if (domainText.length === 0) {
      this.addToSet(this.generic, selector, isException);
      return;
    }
    for (const domain of domainText.split(',')) {
      const normalized: string = domain.trim().toLowerCase();
      if (normalized.length === 0 || normalized.startsWith('~')) {
        continue;
      }
      let rules: CosmeticRuleSet | undefined = this.byHost.get(normalized);
      if (rules === undefined) {
        rules = { selectors: [], exceptions: [] };
        this.byHost.set(normalized, rules);
      }
      this.addToSet(rules, selector, isException);
    }
  }

  private addToSet(rules: CosmeticRuleSet, selector: string, exception: boolean): void {
    const target: string[] = exception ? rules.exceptions : rules.selectors;
    target.push(selector);
  }

  private isSafeSelector(selector: string): boolean {
    return selector.length > 0 && selector.length <= 512 &&
      !selector.includes('<') && !selector.includes('javascript:');
  }
}
