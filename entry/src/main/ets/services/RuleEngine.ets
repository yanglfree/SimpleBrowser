export interface RuleMatchContext {
  url: string;
  pageUrl?: string;
  resourceType?: string;
}

export interface RuleMatchResult {
  blocked: boolean;
  exception: boolean;
  ruleSource: string;
}

export interface SerializedRule {
  source: string;
  regexSource: string;
  indexKey: string;
  domains: string[];
  excludedDomains: string[];
  resourceTypes: string[];
  excludedResourceTypes: string[];
  thirdPartyOnly: boolean;
  firstPartyOnly: boolean;
}

export interface RuleCache {
  version: number;
  fingerprint: number;
  blocked: SerializedRule[];
  exceptions: SerializedRule[];
}

interface RuntimeRule extends SerializedRule {
  matcher: RegExp;
}

interface ParsedOptions {
  domains: string[];
  excludedDomains: string[];
  resourceTypes: string[];
  excludedResourceTypes: string[];
  thirdPartyOnly: boolean;
  firstPartyOnly: boolean;
  ignored: boolean;
}

const RULE_CACHE_VERSION: number = 1;
const GENERIC_INDEX_KEY: string = '*';

/**
 * Parses and matches the network subset of EasyList/AdGuard syntax.
 *
 * Native AdsBlockManager remains configured for system-level blocking. This
 * engine gives request callbacks a deterministic representation without
 * scanning every rule for each resource.
 */
export class RuleEngine {
  private readonly blockedRules: RuntimeRule[];
  private readonly exceptionRules: RuntimeRule[];
  private readonly blockedIndex: Map<string, RuntimeRule[]> = new Map();
  private readonly exceptionIndex: Map<string, RuntimeRule[]> = new Map();

  private constructor(blocked: RuntimeRule[], exceptions: RuntimeRule[]) {
    this.blockedRules = blocked;
    this.exceptionRules = exceptions;
    this.buildIndex(this.blockedRules, this.blockedIndex);
    this.buildIndex(this.exceptionRules, this.exceptionIndex);
  }

  static compile(text: string): RuleEngine {
    const blocked: RuntimeRule[] = [];
    const exceptions: RuntimeRule[] = [];
    const disabledRules: Map<string, boolean> = new Map();
    const lines: string[] = text.split(/\r?\n/);
    for (const line of lines) {
      const disabledIdentity: string = RuleEngine.badFilterIdentity(line);
      if (disabledIdentity.length > 0) {
        disabledRules.set(disabledIdentity, true);
      }
    }
    for (const line of lines) {
      const parsed: SerializedRule | undefined = RuleEngine.parseLine(line);
      if (parsed === undefined) {
        continue;
      }
      if (disabledRules.has(RuleEngine.ruleIdentity(parsed.source))) {
        continue;
      }
      const runtime: RuntimeRule | undefined = RuleEngine.toRuntimeRule(parsed);
      if (runtime === undefined) {
        continue;
      }
      if (line.trim().startsWith('@@')) {
        exceptions.push(runtime);
      } else {
        blocked.push(runtime);
      }
    }
    return new RuleEngine(blocked, exceptions);
  }

  static fromCache(cache: RuleCache): RuleEngine | undefined {
    if (cache.version !== RULE_CACHE_VERSION) {
      return undefined;
    }
    const blocked: RuntimeRule[] = RuleEngine.restoreRules(cache.blocked);
    const exceptions: RuntimeRule[] = RuleEngine.restoreRules(cache.exceptions);
    if (blocked.length !== cache.blocked.length || exceptions.length !== cache.exceptions.length) {
      return undefined;
    }
    return new RuleEngine(blocked, exceptions);
  }

  static fingerprint(text: string): number {
    let hash: number = 2166136261;
    for (let index: number = 0; index < text.length; index += 1) {
      hash ^= text.charCodeAt(index);
      hash = Math.imul(hash, 16777619) >>> 0;
    }
    return hash;
  }

  get ruleCount(): number {
    return this.blockedRules.length + this.exceptionRules.length;
  }

  serialize(fingerprint: number): RuleCache {
    return {
      version: RULE_CACHE_VERSION,
      fingerprint: fingerprint,
      blocked: this.blockedRules.map((rule: RuntimeRule): SerializedRule => RuleEngine.serialized(rule)),
      exceptions: this.exceptionRules.map((rule: RuntimeRule): SerializedRule => RuleEngine.serialized(rule))
    };
  }

  match(context: RuleMatchContext): RuleMatchResult {
    const url: string = context.url.toLowerCase();
    const exceptions: RuntimeRule[] = this.findCandidates(url, this.exceptionIndex);
    for (const rule of exceptions) {
      if (this.matchesRule(rule, url, context)) {
        return { blocked: false, exception: true, ruleSource: rule.source };
      }
    }

    const blocked: RuntimeRule[] = this.findCandidates(url, this.blockedIndex);
    for (const rule of blocked) {
      if (this.matchesRule(rule, url, context)) {
        return { blocked: true, exception: false, ruleSource: rule.source };
      }
    }
    return { blocked: false, exception: false, ruleSource: '' };
  }

  shouldBlock(context: RuleMatchContext): boolean {
    return this.match(context).blocked;
  }

  private static parseLine(rawLine: string): SerializedRule | undefined {
    let line: string = rawLine.trim();
    if (line.length === 0 || line.startsWith('!') || line.startsWith('[')) {
      return undefined;
    }
    if (line.includes('##') || line.includes('#@#') || line.includes('#?#')) {
      return undefined;
    }

    const exception: boolean = line.startsWith('@@');
    if (exception) {
      line = line.slice(2);
    }
    const optionStart: number = RuleEngine.optionStart(line);
    const pattern: string = optionStart < 0 ? line : line.slice(0, optionStart);
    const optionsText: string = optionStart < 0 ? '' : line.slice(optionStart + 1);
    if (pattern.length === 0) {
      return undefined;
    }
    const options: ParsedOptions = RuleEngine.parseOptions(optionsText);
    if (options.ignored) {
      return undefined;
    }

    let normalized: string = pattern;
    let domainAnchor: boolean = false;
    let startsWith: boolean = false;
    let endsWith: boolean = false;
    if (normalized.startsWith('||')) {
      domainAnchor = true;
      normalized = normalized.slice(2);
    } else if (normalized.startsWith('|')) {
      startsWith = true;
      normalized = normalized.slice(1);
    }
    if (normalized.endsWith('|')) {
      endsWith = true;
      normalized = normalized.slice(0, normalized.length - 1);
    }
    if (normalized.length === 0) {
      return undefined;
    }

    const regexRule: boolean = pattern.startsWith('/') && pattern.lastIndexOf('/') > 0;
    const regexSource: string = regexRule
      ? RuleEngine.regexSourceFromLiteral(pattern)
      : RuleEngine.regexSourceFromPattern(normalized, domainAnchor, startsWith, endsWith);
    if (regexSource.length === 0) {
      return undefined;
    }
    return {
      source: `${exception ? '@@' : ''}${pattern}${optionsText.length > 0 ? `$${optionsText}` : ''}`,
      regexSource: regexSource,
      indexKey: RuleEngine.indexKey(normalized, regexRule),
      domains: options.domains,
      excludedDomains: options.excludedDomains,
      resourceTypes: options.resourceTypes,
      excludedResourceTypes: options.excludedResourceTypes,
      thirdPartyOnly: options.thirdPartyOnly,
      firstPartyOnly: options.firstPartyOnly
    };
  }

  private static optionStart(line: string): number {
    if (line.startsWith('/')) {
      const closingSlash: number = line.lastIndexOf('/');
      return closingSlash > 0 ? line.indexOf('$', closingSlash) : line.indexOf('$');
    }
    return line.indexOf('$');
  }

  private static badFilterIdentity(line: string): string {
    const optionStart: number = line.indexOf('$');
    if (optionStart < 0) {
      return '';
    }
    const options: string[] = line.slice(optionStart + 1).toLowerCase().split(',');
    return options.includes('badfilter') ? line.slice(0, optionStart).trim() : '';
  }

  private static ruleIdentity(source: string): string {
    const optionStart: number = source.indexOf('$');
    return optionStart < 0 ? source : source.slice(0, optionStart);
  }

  private static parseOptions(text: string): ParsedOptions {
    const parsed: ParsedOptions = {
      domains: [],
      excludedDomains: [],
      resourceTypes: [],
      excludedResourceTypes: [],
      thirdPartyOnly: false,
      firstPartyOnly: false,
      ignored: false
    };
    if (text.length === 0) {
      return parsed;
    }
    for (const option of text.toLowerCase().split(',')) {
      if (option === 'badfilter' || option === 'generichide' || option === 'genericblock') {
        parsed.ignored = true;
      } else if (option === 'third-party') {
        parsed.thirdPartyOnly = true;
      } else if (option === '~third-party') {
        parsed.firstPartyOnly = true;
      } else if (option.startsWith('domain=')) {
        RuleEngine.parseDomainOptions(option.slice(7), parsed);
      } else if (RuleEngine.isResourceType(option)) {
        parsed.resourceTypes.push(option);
      } else if (option.startsWith('~') && RuleEngine.isResourceType(option.slice(1))) {
        parsed.excludedResourceTypes.push(option.slice(1));
      }
    }
    return parsed;
  }

  private static parseDomainOptions(value: string, target: ParsedOptions): void {
    for (const domain of value.split('|')) {
      if (domain.length < 2) {
        continue;
      }
      if (domain.startsWith('~')) {
        target.excludedDomains.push(domain.slice(1));
      } else {
        target.domains.push(domain);
      }
    }
  }

  private static isResourceType(value: string): boolean {
    const types: string[] = [
      'script', 'image', 'stylesheet', 'object', 'subdocument', 'xmlhttprequest',
      'object-subrequest', 'media', 'font', 'websocket', 'document', 'ping', 'other'
    ];
    return types.includes(value);
  }

  private static regexSourceFromLiteral(pattern: string): string {
    const closingSlash: number = pattern.lastIndexOf('/');
    if (closingSlash <= 1) {
      return '';
    }
    return pattern.slice(1, closingSlash);
  }

  private static regexSourceFromPattern(
    pattern: string,
    domainAnchor: boolean,
    startsWith: boolean,
    endsWith: boolean
  ): string {
    let source: string = startsWith ? '^' : '';
    if (domainAnchor) {
      source += '(^|[/:.])';
    }
    for (let index: number = 0; index < pattern.length; index += 1) {
      const character: string = pattern.charAt(index);
      if (character === '*') {
        source += '.*';
      } else if (character === '^') {
        source += '[^a-zA-Z0-9_\\-.%]';
      } else {
        source += RuleEngine.escapeRegexCharacter(character);
      }
    }
    if (endsWith) {
      source += '$';
    }
    return source;
  }

  private static escapeRegexCharacter(character: string): string {
    return '.+?()[]{}\\$|'.includes(character) ? `\\${character}` : character;
  }

  private static indexKey(pattern: string, regexRule: boolean): string {
    if (regexRule) {
      return GENERIC_INDEX_KEY;
    }
    const literals: RegExpMatchArray | null = pattern.toLowerCase().match(/[a-z0-9]{3,}/g);
    return literals === null || literals.length === 0 ? GENERIC_INDEX_KEY : literals[0];
  }

  private static toRuntimeRule(rule: SerializedRule): RuntimeRule | undefined {
    try {
      return {
        source: rule.source,
        regexSource: rule.regexSource,
        indexKey: rule.indexKey,
        domains: rule.domains,
        excludedDomains: rule.excludedDomains,
        resourceTypes: rule.resourceTypes,
        excludedResourceTypes: rule.excludedResourceTypes,
        thirdPartyOnly: rule.thirdPartyOnly,
        firstPartyOnly: rule.firstPartyOnly,
        matcher: new RegExp(rule.regexSource, 'i')
      };
    } catch (_error) {
      return undefined;
    }
  }

  private static restoreRules(rules: SerializedRule[]): RuntimeRule[] {
    const restored: RuntimeRule[] = [];
    for (const rule of rules) {
      const runtime: RuntimeRule | undefined = RuleEngine.toRuntimeRule(rule);
      if (runtime !== undefined) {
        restored.push(runtime);
      }
    }
    return restored;
  }

  private static serialized(rule: RuntimeRule): SerializedRule {
    return {
      source: rule.source,
      regexSource: rule.regexSource,
      indexKey: rule.indexKey,
      domains: rule.domains,
      excludedDomains: rule.excludedDomains,
      resourceTypes: rule.resourceTypes,
      excludedResourceTypes: rule.excludedResourceTypes,
      thirdPartyOnly: rule.thirdPartyOnly,
      firstPartyOnly: rule.firstPartyOnly
    };
  }

  private buildIndex(rules: RuntimeRule[], index: Map<string, RuntimeRule[]>): void {
    for (const rule of rules) {
      const bucket: RuntimeRule[] = index.get(rule.indexKey) ?? [];
      bucket.push(rule);
      index.set(rule.indexKey, bucket);
    }
  }

  private findCandidates(url: string, index: Map<string, RuntimeRule[]>): RuntimeRule[] {
    const keys: string[] = RuleEngine.urlKeys(url);
    const candidates: RuntimeRule[] = [];
    const seen: Map<string, boolean> = new Map();
    for (const key of keys) {
      const bucket: RuntimeRule[] | undefined = index.get(key);
      if (bucket === undefined) {
        continue;
      }
      for (const rule of bucket) {
        if (!seen.has(rule.source)) {
          seen.set(rule.source, true);
          candidates.push(rule);
        }
      }
    }
    const generic: RuntimeRule[] | undefined = index.get(GENERIC_INDEX_KEY);
    if (generic !== undefined) {
      for (const rule of generic) {
        if (!seen.has(rule.source)) {
          seen.set(rule.source, true);
          candidates.push(rule);
        }
      }
    }
    return candidates;
  }

  private static urlKeys(url: string): string[] {
    const keys: string[] = [];
    const hostMatch: RegExpMatchArray | null = url.match(/^[a-z][a-z0-9+.-]*:\/\/([^/?#]+)/i);
    if (hostMatch !== null) {
      const host: string = hostMatch[1].split(':')[0].replace(/^\.|\.$/g, '');
      const labels: string[] = host.split('.');
      keys.push(host);
      for (let index: number = 1; index < labels.length - 1; index += 1) {
        keys.push(labels.slice(index).join('.'));
      }
    }
    const literals: RegExpMatchArray | null = url.match(/[a-z0-9]{3,}/gi);
    if (literals !== null) {
      for (const literal of literals) {
        if (!keys.includes(literal.toLowerCase())) {
          keys.push(literal.toLowerCase());
        }
      }
    }
    return keys;
  }

  private matchesRule(rule: RuntimeRule, url: string, context: RuleMatchContext): boolean {
    const requestHost: string = RuleEngine.host(url);
    const pageHost: string = RuleEngine.host(context.pageUrl ?? '');
    if (!RuleEngine.matchesDomainOptions(rule, pageHost)) {
      return false;
    }
    if (!RuleEngine.matchesResourceOptions(rule, context.resourceType ?? '')) {
      return false;
    }
    if (rule.thirdPartyOnly && !RuleEngine.isThirdParty(requestHost, pageHost)) {
      return false;
    }
    if (rule.firstPartyOnly && RuleEngine.isThirdParty(requestHost, pageHost)) {
      return false;
    }
    return rule.matcher.test(url);
  }

  private static matchesDomainOptions(rule: RuntimeRule, pageHost: string): boolean {
    for (const excluded of rule.excludedDomains) {
      if (RuleEngine.hostMatches(pageHost, excluded)) {
        return false;
      }
    }
    if (rule.domains.length === 0) {
      return true;
    }
    return rule.domains.some((domain: string): boolean => RuleEngine.hostMatches(pageHost, domain));
  }

  private static matchesResourceOptions(rule: RuntimeRule, resourceType: string): boolean {
    if (rule.resourceTypes.length > 0 && !rule.resourceTypes.includes(resourceType)) {
      return false;
    }
    return !rule.excludedResourceTypes.includes(resourceType);
  }

  private static host(url: string): string {
    const match: RegExpMatchArray | null = url.toLowerCase().match(/^[a-z][a-z0-9+.-]*:\/\/([^/?#]+)/i);
    return match === null ? '' : match[1].split(':')[0].replace(/^\.|\.$/g, '');
  }

  private static hostMatches(host: string, domain: string): boolean {
    const normalized: string = domain.replace(/^\.|\.$/g, '');
    return host === normalized || host.endsWith(`.${normalized}`);
  }

  private static isThirdParty(requestHost: string, pageHost: string): boolean {
    if (requestHost.length === 0 || pageHost.length === 0) {
      return false;
    }
    return requestHost !== pageHost && !requestHost.endsWith(`.${pageHost}`);
  }
}
