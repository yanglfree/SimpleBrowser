import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
export const repositoryRoot = path.resolve(here, '../..');
export const constantsPath = path.join(
  repositoryRoot,
  'ohos/entry/src/main/ets/constants/AppConstants.ets'
);

/** Static template literals exported from AppConstants.ets. */
export const STATIC_SCRIPT_NAMES = [
  'FORCE_ZOOM_SCRIPT',
  'LONG_PRESS_TARGET_SCRIPT',
  'RESTORE_HIDDEN_SCRIPT',
  'READ_SCROLL_POSITION_SCRIPT',
  'READ_FORM_DRAFT_SCRIPT',
  'READ_FAVICON_SCRIPT',
  'DESKTOP_VIEWPORT_SCRIPT',
  'PASSWORD_FIELD_WATCHER_SCRIPT',
  'BLOCKED_LINK_GUARD_SCRIPT',
  'READER_EXTRACTION_CORE_SCRIPT',
  'READER_EXIT_SCRIPT'
];

export const FILE_NAMES = Object.freeze({
  FORCE_ZOOM_SCRIPT: 'force-zoom.js',
  LONG_PRESS_TARGET_SCRIPT: 'long-press-target.js',
  RESTORE_HIDDEN_SCRIPT: 'restore-hidden.js',
  READ_SCROLL_POSITION_SCRIPT: 'read-scroll-position.js',
  READ_FORM_DRAFT_SCRIPT: 'read-form-draft.js',
  READ_FAVICON_SCRIPT: 'read-favicon.js',
  DESKTOP_VIEWPORT_SCRIPT: 'desktop-viewport.js',
  PASSWORD_FIELD_WATCHER_SCRIPT: 'password-field-watcher.js',
  BLOCKED_LINK_GUARD_SCRIPT: 'blocked-link-guard.js',
  READER_EXTRACTION_CORE_SCRIPT: 'reader-extraction-core.js',
  READER_EXIT_SCRIPT: 'reader-exit.js',
  TRACKER_BLOCK_SCRIPT: 'tracker-block.js',
  CONTENT_CLEANUP_STANDARD_SCRIPT: 'content-cleanup-standard.js',
  CONTENT_CLEANUP_STRICT_SCRIPT: 'content-cleanup-strict.js',
  ARTICLE_CAPTURE_SCRIPT: 'article-capture.js'
});

let cachedSource = null;

export async function constantsSource() {
  if (cachedSource === null) {
    cachedSource = await readFile(constantsPath, 'utf8');
  }
  return cachedSource;
}

export function resetConstantsCache() {
  cachedSource = null;
}

function skipWhitespace(source, index) {
  let cursor = index;
  while (cursor < source.length && /\s/.test(source[cursor])) {
    cursor += 1;
  }
  return cursor;
}

function extractQuoted(source, start) {
  const quote = source[start];
  if (quote !== "'" && quote !== '"') {
    throw new Error('expected quoted string');
  }
  let end = start + 1;
  while (end < source.length) {
    if (source[end] === '\\') {
      end += 2;
      continue;
    }
    if (source[end] === quote) {
      return source.slice(start, end + 1);
    }
    end += 1;
  }
  throw new Error('unterminated quoted string');
}

function extractTemplateBody(source, name) {
  const prefix = `export const ${name}: string`;
  const start = source.indexOf(prefix);
  if (start < 0) {
    throw new Error(`missing const ${name}`);
  }
  const assign = source.indexOf('=', start + prefix.length);
  if (assign < 0) {
    throw new Error(`missing assignment for ${name}`);
  }
  const bodyStart = skipWhitespace(source, assign + 1);
  if (source[bodyStart] !== '`') {
    throw new Error(`${name} is not a template literal`);
  }
  let cursor = bodyStart + 1;
  while (cursor < source.length) {
    const ch = source[cursor];
    if (ch === '\\') {
      cursor += 2;
      continue;
    }
    if (ch === '`') {
      return source.slice(bodyStart + 1, cursor);
    }
    cursor += 1;
  }
  throw new Error(`unterminated template ${name}`);
}

function evaluateTemplate(template, bindings = {}) {
  const names = Object.keys(bindings);
  const values = names.map((name) => bindings[name]);
  return Function(...names, `return \`${template}\`;`)(...values);
}

export async function extractStringArray(name) {
  const source = await constantsSource();
  const prefix = `export const ${name}: string[] = [`;
  const start = source.indexOf(prefix);
  if (start < 0) {
    throw new Error(`missing array ${name}`);
  }
  const contentStart = start + prefix.length;
  const contentEnd = source.indexOf('];', contentStart);
  if (contentEnd < 0) {
    throw new Error(`unterminated array ${name}`);
  }
  const body = source.slice(contentStart, contentEnd);
  return Function(`return [${body}];`)();
}

export async function extractStringConst(name) {
  const source = await constantsSource();
  const prefix = `export const ${name}: string`;
  const start = source.indexOf(prefix);
  if (start < 0) {
    throw new Error(`missing const ${name}`);
  }
  const assign = source.indexOf('=', start + prefix.length);
  if (assign < 0) {
    throw new Error(`missing assignment for ${name}`);
  }
  const quoted = extractQuoted(source, skipWhitespace(source, assign + 1));
  return Function(`return ${quoted};`)();
}

export async function extractTemplateConst(name) {
  const source = await constantsSource();
  const template = extractTemplateBody(source, name);
  if (name === 'ARTICLE_CAPTURE_SCRIPT') {
    const core = await extractTemplateConst('READER_EXTRACTION_CORE_SCRIPT');
    return evaluateTemplate(template, { READER_EXTRACTION_CORE_SCRIPT: core });
  }
  return evaluateTemplate(template);
}

export async function loadStaticScripts() {
  const scripts = {};
  for (const name of STATIC_SCRIPT_NAMES) {
    scripts[name] = await extractTemplateConst(name);
  }
  scripts.TRACKER_BLOCK_SCRIPT = await extractTemplateConst('TRACKER_BLOCK_SCRIPT');
  scripts.CONTENT_CLEANUP_STANDARD_SCRIPT = await contentCleanupScript(false);
  scripts.CONTENT_CLEANUP_STRICT_SCRIPT = await contentCleanupScript(true);
  scripts.ARTICLE_CAPTURE_SCRIPT = await extractTemplateConst('ARTICLE_CAPTURE_SCRIPT');
  return scripts;
}

export async function contentCleanupScript(strict) {
  const source = await constantsSource();
  const functionStart = source.indexOf('export function contentCleanupScript(');
  if (functionStart < 0) {
    throw new Error('missing contentCleanupScript');
  }
  const prefix = '  return `';
  const contentStart = source.indexOf(prefix, functionStart) + prefix.length;
  const contentEnd = source.indexOf('`;\n}', contentStart);
  if (contentEnd < 0) {
    throw new Error('unterminated contentCleanupScript');
  }
  const template = source.slice(contentStart, contentEnd);
  const pattern = await extractStringConst('STRICT_AD_TOKEN_PATTERN');
  return Function('STRICT_AD_TOKEN_PATTERN', 'strict', `return \`${template}\`;`)(
    pattern,
    strict
  );
}

export async function readerApplyScript(
  fontSize = 17,
  lineHeight = 205,
  paperBackground = '#ffffff',
  bodyColor = '#222222',
  titleColor = '#111111',
  accentColor = '#2e6b5c'
) {
  const source = await constantsSource();
  const functionStart = source.indexOf('export function readerApplyScript(');
  if (functionStart < 0) {
    throw new Error('missing readerApplyScript');
  }
  const prefix = '  return `';
  const contentStart = source.indexOf(prefix, functionStart) + prefix.length;
  const contentEnd = source.indexOf('`;\n}', contentStart);
  if (contentEnd < 0) {
    throw new Error('unterminated readerApplyScript');
  }
  const template = source.slice(contentStart, contentEnd);
  const core = await extractTemplateConst('READER_EXTRACTION_CORE_SCRIPT');
  const lineHeightRatio = (lineHeight / 100).toFixed(2);
  return Function(
    'READER_EXTRACTION_CORE_SCRIPT',
    'fontSize',
    'lineHeightRatio',
    'paperBackground',
    'bodyColor',
    'titleColor',
    'accentColor',
    `return \`${template}\`;`
  )(core, fontSize, lineHeightRatio, paperBackground, bodyColor, titleColor, accentColor);
}

export async function findCountScript(query) {
  const serialized = JSON.stringify(query.trim().toLowerCase());
  return `(function(q) {
  if (!q) return '0';
  var text = (document.body.innerText || '').toLowerCase();
  var count = 0, offset = 0, index = -1;
  while ((index = text.indexOf(q, offset)) >= 0) {
    count += 1;
    offset = index + q.length;
  }
  return String(count);
})(${serialized});`;
}
