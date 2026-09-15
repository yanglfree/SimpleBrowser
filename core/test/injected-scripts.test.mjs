import test from 'node:test';
import assert from 'node:assert/strict';
import {
  FILE_NAMES,
  contentCleanupScript,
  extractTemplateConst,
  findCountScript,
  loadStaticScripts,
  readerApplyScript
} from '../src/injected-scripts.mjs';
import { checkExportedScripts, writeExportedScripts } from '../src/export-js.mjs';

test('extracts document-start and reader scripts from AppConstants', async () => {
  const scripts = await loadStaticScripts();
  assert.match(scripts.BLOCKED_LINK_GUARD_SCRIPT, /__zhuoBlockedLinkGuard/);
  assert.match(scripts.LONG_PRESS_TARGET_SCRIPT, /__mbLongPressTarget/);
  assert.match(scripts.FORCE_ZOOM_SCRIPT, /user-scalable=yes/);
  assert.match(scripts.READER_EXTRACTION_CORE_SCRIPT, /__zhuoReaderExtract/);
  assert.match(scripts.TRACKER_BLOCK_SCRIPT, /google-analytics/);
  assert.match(scripts.PASSWORD_FIELD_WATCHER_SCRIPT, /messageHandlers\.zhuoSecurity/);
  assert.match(scripts.ARTICLE_CAPTURE_SCRIPT, /__zhuoReaderExtract/);
  for (const name of Object.keys(FILE_NAMES)) {
    assert.equal(typeof scripts[name], 'string');
    assert.ok(scripts[name].length > 20, name);
  }
});

test('builders still produce parameterized scripts', async () => {
  const cleanup = await contentCleanupScript(true);
  assert.match(cleanup, /\(function\(strict\)/);
  assert.match(cleanup, /true\)\s*;\s*$/);
  const reader = await readerApplyScript(17, 205, '#ffffff', '#222222', '#111111', '#2e6b5c');
  assert.match(reader, /__mb-reader/);
  assert.equal(await findCountScript('Hello'), await findCountScript('  HELLO '));
});

test('tracker cleanup reports observed malicious resources separately and stays idempotent', async () => {
  const script = await extractTemplateConst('TRACKER_BLOCK_SCRIPT');
  const makeNode = (src) => {
    const attributes = new Set();
    return {
      src,
      removed: false,
      hasAttribute: (name) => attributes.has(name),
      getAttribute: (name) => name === 'src' ? src : '',
      setAttribute: (name) => attributes.add(name),
      remove() { this.removed = true; }
    };
  };
  const nodes = [
    makeNode('https://evil.example/phishing/payload.js'),
    makeNode('https://www.google-analytics.com/analytics.js'),
    makeNode('https://cdn.example/app.js')
  ];
  const document = { querySelectorAll: () => nodes };
  const window = {};
  const navigator = {};
  const run = Function('document', 'window', 'navigator', `return ${script.trim()}`);

  assert.deepEqual(JSON.parse(run(document, window, navigator)), {
    trackers: 1,
    malicious: 1,
    resources: [
      { url: 'https://evil.example/phishing/payload.js', category: 'malicious' },
      { url: 'https://www.google-analytics.com/analytics.js', category: 'tracker' }
    ]
  });
  assert.deepEqual(JSON.parse(run(document, window, navigator)), {
    trackers: 0,
    malicious: 0,
    resources: []
  });
  assert.deepEqual(nodes.map((node) => node.removed), [true, true, false]);
});

test('reader extraction core stays a closed IIFE', async () => {
  const core = await extractTemplateConst('READER_EXTRACTION_CORE_SCRIPT');
  assert.match(core.trim(), /^\(function\(\)/);
  assert.match(core, /window\.__zhuoReaderExtract/);
});

test('blocked link guard dropdown click handler does not blur external input fields', async () => {
  const script = await extractTemplateConst('BLOCKED_LINK_GUARD_SCRIPT');
  let blurCalled = false;
  const inputElement = {
    tagName: 'INPUT',
    blur() { blurCalled = true; }
  };
  const listeners = {};
  const document = {
    activeElement: inputElement,
    addEventListener(type, handler) { listeners[type] = handler; },
    querySelectorAll(selector) {
      if (selector === '[data-zhuo-dropdown="open"]') {
        return [];
      }
      return [];
    },
    getElementById() { return null; },
    createElement() { return { set textContent(_) {} }; },
    head: { appendChild() {} }
  };
  const window = {};

  const run = Function('document', 'window', `return ${script.trim()}`);
  run(document, window);

  assert.ok(typeof listeners.click === 'function');
  // Simulate clicking an input element while activeElement is the input
  listeners.click({ target: inputElement });
  assert.equal(blurCalled, false, 'inputElement should not be blurred when no dropdown is open');

  // Now test with an open dropdown that does NOT contain activeElement
  let containerClosed = false;
  const openContainer = {
    setAttribute(name, value) {
      if (name === 'data-zhuo-dropdown' && value === 'closed') {
        containerClosed = true;
      }
    },
    contains(node) {
      return node !== inputElement;
    }
  };
  document.querySelectorAll = (selector) => {
    if (selector === '[data-zhuo-dropdown="open"]') {
      return [openContainer];
    }
    return [];
  };

  listeners.click({ target: inputElement });
  assert.equal(containerClosed, true, 'open dropdown should be closed');
  assert.equal(blurCalled, false, 'external inputElement should still not be blurred');

  // Only active elements contained inside the container should be blurred
  let innerBlurCalled = false;
  const innerElement = {
    blur() { innerBlurCalled = true; }
  };
  document.activeElement = innerElement;
  openContainer.contains = (node) => node === innerElement;

  listeners.click({ target: inputElement });
  assert.equal(innerBlurCalled, true, 'inner element inside closed dropdown should be blurred');
});

test('exported js snapshot matches AppConstants', async () => {
  await writeExportedScripts();
  const drift = await checkExportedScripts();
  assert.deepEqual(drift, []);
});
