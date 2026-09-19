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
  assert.match(scripts.TRACKER_BLOCK_SCRIPT, /resources/);
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

test('tracker pass never mutates loaded resources or reports observations as blocks', async () => {
  const script = await extractTemplateConst('TRACKER_BLOCK_SCRIPT');
  const nodes = [
    'https://developer.huawei.com/consumer/cn/service/josp/agc/static/js/index.js',
    'https://example.com/images/soundtrack-cover.png',
    'https://example.com/images/pixel-art.png',
    'https://example.com/docs/phishing-awareness.png',
    'https://notgoogle-analytics.example.org/app.js',
    'https://www.google-analytics.com/analytics.js'
  ].map(src => ({ src, hasAttribute: () => false,
    setAttribute() { throw new Error(`Modified resource: ${src}`); },
    remove() { throw new Error(`Removed resource: ${src}`); } }));
  const run = Function('document', 'window', 'navigator', `return ${script.trim()}`);
  const document = { querySelectorAll: () => nodes };
  const window = {};
  const navigator = {};
  for (let pass = 0; pass < 3; pass++) {
    assert.deepEqual(JSON.parse(run(document, window, navigator)), {
      trackers: 0, malicious: 0, resources: []
    });
  }
});

test('tracker pass preserves beacon payloads, receiver, return values and exceptions', async () => {
  const script = await extractTemplateConst('TRACKER_BLOCK_SCRIPT');
  const calls = [];
  const failure = new TypeError('Invalid beacon URL');
  const navigator = {
    sendBeacon(url, body) {
      assert.equal(this, navigator);
      calls.push({ url, body });
      if (url === 'invalid:') throw failure;
      return url !== '/queue-full';
    }
  };
  const original = navigator.sendBeacon;
  const run = Function('document', 'window', 'navigator', `return ${script.trim()}`);
  const window = {};
  const body = new Uint8Array([1, 2, 3]);
  for (let pass = 0; pass < 3; pass++) {
    run({}, window, navigator);
    assert.equal(navigator.sendBeacon, original);
    assert.equal(navigator.sendBeacon('/api/save-draft', body), true);
    assert.equal(navigator.sendBeacon('/queue-full', body), false);
    assert.throws(() => navigator.sendBeacon('invalid:', body), error => error === failure);
  }
  assert.equal(calls.length, 9);
  assert.ok(calls.every(call => call.body === body));
  assert.deepEqual(JSON.parse(run({}, window, navigator)), {
    trackers: 0, malicious: 0, resources: []
  });
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

test('hash link clicks sync location.hash without destructive page reloads', async () => {
  const script = await extractTemplateConst('BLOCKED_LINK_GUARD_SCRIPT');
  const store = {};
  const location = {
    origin: 'https://developer.huawei.com',
    pathname: '/consumer/cn/service/josp/agc/index.html',
    search: '',
    hash: '#/',
    reload() { store.reloaded = true; }
  };
  Object.defineProperty(location, 'href', {
    configurable: true,
    get() {
      return `https://developer.huawei.com${location.pathname}${location.search}${location.hash}`;
    }
  });
  const clickHandlers = [];
  const events = [];
  const document = {
    referrer: 'https://id1.cloud.huawei.com/CAS/portal/loginAuth.html',
    addEventListener(type, handler, options) {
      if (type === 'click') clickHandlers.push({ handler, options });
    },
    querySelectorAll() { return []; },
    getElementById() { return null; },
    createElement() { return { set textContent(_) {} }; },
    head: { appendChild() {} }
  };
  const window = {
    location,
    open: () => null,
    dispatchEvent(event) { events.push(event?.type || 'event'); return true; },
    history: { state: null }
  };
  const sessionStorage = {
    getItem(key) { return store[key] || null; },
    setItem(key, value) { store[key] = String(value); }
  };
  const timers = [];
  const run = Function(
    'document',
    'window',
    'URL',
    'sessionStorage',
    'setTimeout',
    `return ${script.trim()}`
  );
  run(document, window, URL, sessionStorage, (callback) => timers.push(callback));

  const bubble = clickHandlers.find((item) => item.options === false);
  assert.ok(bubble, 'expected a bubble-phase hash click handler');
  const link = {
    href: 'https://developer.huawei.com/consumer/cn/service/josp/agc/index.html#/analysis',
    tagName: 'A',
    getAttribute(name) { return name === 'href' ? '#/analysis' : ''; },
    closest() { return link; }
  };
  bubble.handler({ target: link, button: 0 });
  assert.equal(location.hash, '#/');
  for (const callback of timers) callback();
  assert.equal(location.hash, '#/analysis');
  assert.equal(store.reloaded, undefined, 'must not reload the page');
  assert.deepEqual(events, ['hashchange']);
});

test('window.open applies same-document hash via location.hash instead of href', async () => {
  const script = await extractTemplateConst('BLOCKED_LINK_GUARD_SCRIPT');
  const location = {
    origin: 'https://developer.huawei.com',
    pathname: '/consumer/cn/service/josp/agc/index.html',
    search: '',
    hash: '#/'
  };
  let hrefAssigned = '';
  Object.defineProperty(location, 'href', {
    configurable: true,
    get() {
      return `https://developer.huawei.com${location.pathname}${location.search}${location.hash}`;
    },
    set(value) {
      hrefAssigned = value;
    }
  });
  const document = {
    addEventListener() {},
    querySelectorAll() { return []; },
    getElementById() { return null; },
    createElement() { return { set textContent(_) {} }; },
    head: { appendChild() {} },
    referrer: ''
  };
  const window = {
    location,
    open: () => null,
    dispatchEvent() { return true; },
    history: { state: null }
  };
  const run = Function('document', 'window', 'URL', `return ${script.trim()}`);
  run(document, window, URL);

  const opened = window.open(
    'https://developer.huawei.com/consumer/cn/service/josp/agc/index.html#/myApp'
  );
  assert.equal(opened, window);
  assert.equal(location.hash, '#/myApp');
  assert.equal(hrefAssigned, '');

  const relative = window.open('#/analytics');
  assert.equal(relative, window);
  assert.equal(location.hash, '#/analytics');
  assert.equal(hrefAssigned, '');

  window.open('https://developer.huawei.com/consumer/cn/doc/index.html');
  assert.equal(hrefAssigned, 'https://developer.huawei.com/consumer/cn/doc/index.html');
});

test('blank Huawei OAuth callbacks recover only when login state is missing or stale', async () => {
  const script = await extractTemplateConst('BLOCKED_LINK_GUARD_SCRIPT');
  const runCallback = (pathname, search, cookie) => {
    const timers = [];
    const listeners = {};
    const location = {
      origin: 'https://developer.huawei.com',
      pathname,
      search,
      href: `https://developer.huawei.com${pathname}${search}`
    };
    const document = {
      activeElement: null,
      body: { innerText: '' },
      cookie,
      addEventListener(type, handler) { listeners[type] = handler; },
      querySelectorAll() { return []; },
      getElementById() { return null; },
      createElement() { return { set textContent(_) {} }; },
      head: { appendChild() {} }
    };
    const window = { location };
    const setTimeout = (callback) => timers.push(callback);
    const run = Function('document', 'window', 'setTimeout', `return ${script.trim()}`);
    run(document, window, setTimeout);
    for (const callback of timers) callback();
    return location.href;
  };

  assert.equal(
    runCallback('/consumer/cn/hdc-console/handleAllianceLogin.html', '?state=123', ''),
    'https://developer.huawei.com/consumer/cn/hdc-console/'
  );
  assert.equal(
    runCallback('/consumer/cn/service/josp/agc/handleAllianceLogin.html', '?state=123', 'state=stale'),
    'https://developer.huawei.com/consumer/cn/service/josp/agc/index.html'
  );
  assert.equal(
    runCallback('/consumer/cn/hdc-console/handleAllianceLogin.html', '?state=123', 'other=value; state=123'),
    'https://developer.huawei.com/consumer/cn/hdc-console/handleAllianceLogin.html?state=123'
  );
  assert.equal(
    runCallback('/consumer/cn/ordinary-blank.html', '?state=123', ''),
    'https://developer.huawei.com/consumer/cn/ordinary-blank.html?state=123'
  );
});

test('exported js snapshot matches AppConstants', async () => {
  await writeExportedScripts();
  const drift = await checkExportedScripts();
  assert.deepEqual(drift, []);
});
