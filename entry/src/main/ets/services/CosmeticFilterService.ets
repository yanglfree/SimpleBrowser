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
/**
 * How many host rules the in-page pass will match element by element. Sites
 * carry a handful; the cap keeps a pathological entry from turning every DOM
 * change into a long selector match.
 */
const HOST_SELECTOR_LIMIT: number = 64;

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

  /**
   * Only the rules written for this host. Inside a shadow root a stylesheet can
   * lose to the component's own `:host` rule, so those matches have to be hidden
   * element by element — affordable for a handful of site rules, not for the
   * thousands of generic ones.
   */
  hostSelectorsFor(pageUrl: string): string[] {
    const hostRules: CosmeticRuleSet[] = this.rulesForHost(rawHost(pageUrl));
    const exceptions: Set<string> = new Set<string>();
    for (const rules of hostRules) {
      for (const selector of rules.exceptions) {
        exceptions.add(selector);
      }
    }
    const selectors: string[] = [];
    for (const rules of hostRules) {
      for (const selector of rules.selectors) {
        if (!exceptions.has(selector) && !selectors.includes(selector)) {
          selectors.push(selector);
        }
      }
    }
    return selectors.slice(0, HOST_SELECTOR_LIMIT);
  }

  scriptFor(pageUrl: string): string {
    const payload: string = this.payloadFor(rawHost(pageUrl));
    if (payload.length === 0) {
      return '';
    }
    const hostSelectors: string[] = this.hostSelectorsFor(pageUrl);
    const hostPayload: string = JSON.stringify(hostSelectors.join(','));
    // The stylesheet is assembled inside the page: sending selectors costs a
    // fraction of sending the expanded CSS across the bridge.
    //
    // A stylesheet in the document does not cross a shadow boundary, and sites
    // built out of web components — MSN's feed, for one — keep every card
    // several roots deep, ad slots included. So the same sheet is planted in
    // each shadow root as well: attachShadow is wrapped to catch the roots the
    // page has yet to create, and the roots that already exist are swept once.
    return `(function(selectors, hostSelectors) {
  var id = '__minimalBrowserCosmeticRules';
  var css = '';
  for (var i = 0; i < selectors.length; i++) {
    css += selectors[i] + '{display:none!important;}';
  }
  var roots = [];
  var observer = null;

  function plant(root) {
    if (!root || root.__mbCosmetic === css) return false;
    var container = root === document ? (document.head || document.documentElement) : root;
    if (!container) return false;
    var style = root === document ? document.getElementById(id) : root.__mbCosmeticNode;
    if (!style || !style.isConnected) {
      style = document.createElement('style');
      style.id = id;
      container.appendChild(style);
      if (root !== document) root.__mbCosmeticNode = style;
    }
    style.textContent = css;
    root.__mbCosmetic = css;
    roots.push(root);
    // Changes inside a shadow root do not reach an observer watching the
    // document, so every root the sheet lands in is watched in its own right.
    if (observer) observer.observe(root === document ? document.documentElement : root,
      { childList: true, subtree: true });
    return true;
  }

  /**
   * A sheet in the root that holds the element still loses to the component's
   * own :host rule when that one is !important: on important declarations the
   * inner tree wins. Inline beats both, so the site's own rules are applied
   * element by element. Only the roots we planted in are visited, and only with
   * the handful of selectors written for this host.
   */
  function hideMatches() {
    if (!hostSelectors) return;
    for (var r = 0; r < roots.length; r++) {
      var matches;
      try { matches = roots[r].querySelectorAll(hostSelectors); } catch (e) { continue; }
      for (var k = 0; k < matches.length; k++) {
        var el = matches[k];
        if (el.getAttribute('__mbCleaned') === null) {
          el.setAttribute('__mbCleaned', '');
          el.style.setProperty('display', 'none', 'important');
        }
      }
    }
  }

  if (!window.__mbCosmeticObserver) {
    var pending = false;
    observer = new MutationObserver(function() {
      if (pending) return;
      pending = true;
      setTimeout(function() { pending = false; try { hideMatches(); } catch (e) {} }, 300);
    });
    window.__mbCosmeticObserver = observer;
  } else {
    observer = window.__mbCosmeticObserver;
  }

  plant(document);
  var proto = Element.prototype;
  if (!proto.__mbShadowPatched && typeof proto.attachShadow === 'function') {
    var original = proto.attachShadow;
    proto.attachShadow = function(init) {
      var root = original.call(this, init);
      try { plant(root); } catch (e) {}
      return root;
    };
    proto.__mbShadowPatched = true;
  }
  // Roots that already existed when this ran — the page's bootstrap, mostly.
  // Everything created afterwards arrives through the attachShadow wrapper, so
  // this walk happens once instead of on a timer.
  (function discover(root, depth) {
    if (depth > 12) return;
    var all = root.querySelectorAll('*');
    for (var j = 0; j < all.length; j++) {
      var shadow = all[j].shadowRoot;
      if (shadow) { plant(shadow); discover(shadow, depth + 1); }
    }
  })(document, 0);
  hideMatches();
  return JSON.stringify({ selectors: selectors.length, roots: roots.length });
})(${payload}, ${hostPayload});`;
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
