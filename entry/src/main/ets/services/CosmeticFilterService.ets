import { rawHost } from '../utils/UrlUtils';

interface CosmeticRuleSet {
  selectors: string[];
  exceptions: string[];
}

/** Compiles the selector subset of EasyList/AdGuard cosmetic rules. */
export class CosmeticFilterService {
  private generic: CosmeticRuleSet = { selectors: [], exceptions: [] };
  private byHost: Map<string, CosmeticRuleSet> = new Map();

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
    const selectors: string[] = this.generic.selectors.slice(0);
    const exceptions: string[] = this.generic.exceptions.slice(0);
    this.byHost.forEach((rules: CosmeticRuleSet, domain: string): void => {
      if (host === domain || host.endsWith(`.${domain}`)) {
        for (const selector of rules.selectors) {
          selectors.push(selector);
        }
        for (const selector of rules.exceptions) {
          exceptions.push(selector);
        }
      }
    });
    return selectors.filter((selector: string, index: number): boolean =>
      !exceptions.includes(selector) && selectors.indexOf(selector) === index);
  }

  scriptFor(pageUrl: string): string {
    const selectors: string[] = this.selectorsFor(pageUrl);
    if (selectors.length === 0) {
      return '';
    }
    const payload: string = JSON.stringify(selectors);
    return `(function(selectors) {
  var id = '__minimalBrowserCosmeticRules';
  var style = document.getElementById(id);
  if (!style) {
    style = document.createElement('style');
    style.id = id;
    (document.head || document.documentElement).appendChild(style);
  }
  var css = '';
  for (var i = 0; i < selectors.length; i++) {
    css += selectors[i] + '{display:none!important;visibility:hidden!important;}';
  }
  style.textContent = css;
  return JSON.stringify({ selectors: selectors.length });
})(${payload});`;
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
    if (!target.includes(selector)) {
      target.push(selector);
    }
  }

  private isSafeSelector(selector: string): boolean {
    return selector.length > 0 && selector.length <= 512 &&
      !selector.includes('<') && !selector.includes('>') &&
      !selector.includes('javascript:');
  }
}
