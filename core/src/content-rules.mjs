/**
 * Compile a subset of Adblock Plus lists into Safari WKContentRuleList JSON.
 *
 * Supported:
 * - `||host^` and `||host^path` network blocks
 * - `domain[,domain]##selector` cosmetic hide
 *
 * Skipped: comments, regex rules (`/…/`), exception rules (`@@`), and
 * option-heavy filters (`$script,domain=…`). Those stay on Harmony's
 * AdsBlockManager / RuleEngine until a later compiler pass.
 */

const RESOURCE_TYPES = ['document', 'image', 'style-sheet', 'script', 'font', 'raw', 'svg-document', 'media', 'popup'];

export function parseFilterList(text) {
  const network = [];
  const cosmetic = [];
  const skipped = [];
  const lines = text.split(/\r?\n/);
  for (const raw of lines) {
    const line = raw.trim();
    if (line.length === 0 || line.startsWith('!') || line.startsWith('[')) {
      continue;
    }
    if (line.startsWith('@@')) {
      skipped.push({ line, reason: 'exception' });
      continue;
    }
    const cosmeticIndex = line.indexOf('##');
    if (cosmeticIndex > 0 && !line.startsWith('|') && !line.startsWith('/')) {
      const domains = line.slice(0, cosmeticIndex).split(',').map((part) => part.trim()).filter(Boolean);
      const selector = line.slice(cosmeticIndex + 2).trim();
      if (domains.length === 0 || selector.length === 0 || domains.some((domain) => domain.startsWith('~'))) {
        skipped.push({ line, reason: 'cosmetic-unsupported' });
        continue;
      }
      cosmetic.push({ domains, selector, line });
      continue;
    }
    if (line.startsWith('||') && !line.includes('$')) {
      const body = line.slice(2);
      const separator = body.indexOf('^');
      if (separator < 0) {
        skipped.push({ line, reason: 'network-no-separator' });
        continue;
      }
      const host = body.slice(0, separator).toLowerCase();
      const path = body.slice(separator + 1);
      if (!/^[a-z0-9.-]+$/.test(host) || host.includes('..')) {
        skipped.push({ line, reason: 'network-host' });
        continue;
      }
      network.push({ host, path, line });
      continue;
    }
    skipped.push({ line, reason: 'unsupported' });
  }
  return { network, cosmetic, skipped };
}

function escapeRegex(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function pathToRegex(path) {
  if (path.length === 0) {
    return '([:/].*)?';
  }
  const escaped = path.split('*').map((part) => escapeRegex(part)).join('.*');
  return escaped.startsWith('/') ? escaped : `/${escaped}`;
}

export function networkRuleToContentRule(rule) {
  const host = escapeRegex(rule.host);
  const path = pathToRegex(rule.path);
  return {
    trigger: {
      'url-filter': `^https?://([^/]*\\.)?${host}${path}`,
      'resource-type': RESOURCE_TYPES
    },
    action: { type: 'block' }
  };
}

export function cosmeticRuleToContentRule(rule) {
  return {
    trigger: {
      'url-filter': '.*',
      'if-domain': rule.domains.map((domain) => `*${domain.replace(/^\*/, '')}`)
    },
    action: {
      type: 'css-display-none',
      selector: rule.selector
    }
  };
}

export function compileContentRules(text, options = {}) {
  const parsed = parseFilterList(text);
  const rules = [];
  for (const rule of parsed.network) {
    rules.push(networkRuleToContentRule(rule));
  }
  for (const rule of parsed.cosmetic) {
    rules.push(cosmeticRuleToContentRule(rule));
  }
  const maxRules = options.maxRules ?? 50000;
  return {
    rules: rules.slice(0, maxRules),
    truncated: rules.length > maxRules,
    parsed
  };
}

export function compileContentRulesJson(text, options = {}) {
  const compiled = compileContentRules(text, options);
  return {
    json: JSON.stringify(compiled.rules),
    count: compiled.rules.length,
    truncated: compiled.truncated,
    skipped: compiled.parsed.skipped.length,
    network: compiled.parsed.network.length,
    cosmetic: compiled.parsed.cosmetic.length
  };
}
