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

const GENERIC_INDEX_KEY: string = '*';

const RESOURCE_TYPES: string[] = [
  'script', 'image', 'stylesheet', 'object', 'subdocument', 'xmlhttprequest',
  'object-subrequest', 'media', 'font', 'websocket', 'document', 'ping', 'other'
];

/** uBlock/AdGuard shorthands for the option names EasyList spells out. */
const RESOURCE_TYPE_ALIASES: Map<string, string> = new Map<string, string>([
  ['xhr', 'xmlhttprequest'],
  ['frame', 'subdocument'],
  ['css', 'stylesheet'],
  ['doc', 'document'],
  ['beacon', 'ping']
]);

/**
 * Options that constrain nothing we can act on but leave the rule a plain
 * block: keeping them costs nothing, dropping the rule would lose coverage.
 */
const NEUTRAL_OPTIONS: string[] = [
  'important', 'match-case', '~match-case', 'all', 'empty', 'mp4', 'strict1p', 'strict3p'
];

/**
 * Options that mean something other than "block this request" — a popup-only
 * rule, a query-string edit, a CSP header. Treating them as blocks is how an
 * ad blocker starts breaking pages, so the rules carrying them are dropped
 * rather than approximated.
 */
const UNSUPPORTED_OPTIONS: string[] = [
  'badfilter', 'generichide', 'genericblock', 'ghide', 'elemhide', 'ehide',
  'specifichide', 'shide', 'popup', 'popunder', 'inline-script', 'inline-font',
  'jsinject', 'urlblock', 'content', 'extension', 'stealth', 'cookie', 'network'
];

/** Same, for the `name=value` forms. */
const UNSUPPORTED_VALUE_OPTIONS: string[] = [
  'csp', 'removeparam', 'queryprune', 'replace', 'redirect-rule', 'permissions',
  'urltransform', 'header', 'denyallow', 'method', 'to', 'app', 'stealth'
];

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

  get ruleCount(): number {
    return this.blockedRules.length + this.exceptionRules.length;
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

    const regexRule: boolean = RuleEngine.isRegexLiteral(pattern);
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

  /**
   * A rule is a regular expression only when the whole pattern is wrapped in
   * slashes. Most EasyList path rules — `/in/track?data=`, `/a/?ad=` — merely
   * start with one, and reading those as regexes turns them into `/in/` and
   * `/a/`, which match nearly every URL and blank out whole pages.
   */
  private static isRegexLiteral(pattern: string): boolean {
    return pattern.length > 2 && pattern.startsWith('/') && pattern.endsWith('/');
  }

  private static optionStart(line: string): number {
    if (line.startsWith('/')) {
      const closingSlash: number = line.lastIndexOf('/');
      // Options of a regex rule start right after its closing slash.
      if (closingSlash > 0 && line.charAt(closingSlash + 1) === '$') {
        return closingSlash + 1;
      }
      if (closingSlash === line.length - 1) {
        return -1;
      }
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
      RuleEngine.applyOption(option.trim(), parsed);
    }
    return parsed;
  }

  /**
   * Anything this does not recognise drops the rule. Guessing wrong in the
   * permissive direction blocks a request the list never asked to block, and a
   * broken page is a worse failure than a missed ad.
   */
  private static applyOption(option: string, parsed: ParsedOptions): void {
    if (option.length === 0 || NEUTRAL_OPTIONS.includes(option)) {
      return;
    }
    const separator: number = option.indexOf('=');
    if (separator > 0) {
      const name: string = option.slice(0, separator);
      const value: string = option.slice(separator + 1);
      if (name === 'domain' || name === 'from') {
        RuleEngine.parseDomainOptions(value, parsed);
      } else if (name !== 'redirect' && name !== 'rewrite') {
        // redirect/rewrite still block the request before substituting a stub.
        parsed.ignored = true;
      }
      if (UNSUPPORTED_VALUE_OPTIONS.includes(name)) {
        parsed.ignored = true;
      }
      return;
    }
    if (UNSUPPORTED_OPTIONS.includes(option) || UNSUPPORTED_VALUE_OPTIONS.includes(option)) {
      parsed.ignored = true;
      return;
    }
    if (option === 'third-party' || option === '3p') {
      parsed.thirdPartyOnly = true;
      return;
    }
    if (option === '~third-party' || option === 'first-party' || option === '1p' || option === '~3p') {
      parsed.firstPartyOnly = true;
      return;
    }
    const negated: boolean = option.startsWith('~');
    const bare: string = negated ? option.slice(1) : option;
    const resolved: string = RESOURCE_TYPE_ALIASES.get(bare) ?? bare;
    if (!RuleEngine.isResourceType(resolved)) {
      parsed.ignored = true;
      return;
    }
    if (negated) {
      parsed.excludedResourceTypes.push(resolved);
    } else {
      parsed.resourceTypes.push(resolved);
    }
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
    return RESOURCE_TYPES.includes(value);
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
      // `||` anchors to a label boundary of the *host*. Matching a bare
      // separator instead would fire on the path too, so `||doubleclick.net^`
      // would block `https://safe.example/redir?u=/doubleclick.net/x`.
      source += '^[a-z][a-z0-9+.-]*:\\/\\/(?:[^\\/?#]*\\.)?';
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

  /**
   * The bucket a rule is filed under. Picking the longest literal rather than
   * the first one matters: leading words like `banner` or `track` are shared by
   * thousands of rules, so a request would drag every one of them through a
   * regex. On the shipped list this roughly halves candidates per request.
   */
  private static indexKey(pattern: string, regexRule: boolean): string {
    if (regexRule) {
      return GENERIC_INDEX_KEY;
    }
    const literals: RegExpMatchArray | null = pattern.toLowerCase().match(/[a-z0-9]{3,}/g);
    if (literals === null || literals.length === 0) {
      return GENERIC_INDEX_KEY;
    }
    let longest: string = literals[0];
    for (const literal of literals) {
      if (literal.length > longest.length) {
        longest = literal;
      }
    }
    return longest;
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
