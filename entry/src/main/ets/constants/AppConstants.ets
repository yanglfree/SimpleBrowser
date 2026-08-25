import { QuickSite, QUICK_SITE_LIMIT_MAX } from '../models/BrowserModels';

/** Internal URL for the native start page. It is never handed to ArkWeb. */
export const HOME_URL: string = 'browser://home';
export const STORE_NAME: string = 'minimal_browser_store';
export const SESSION_KEY: string = 'browser_session';
export const TAB_ARCHIVE_KEY: string = 'tab_archive';

export const MAX_HISTORY_COUNT: number = 300;
export const MAX_BOOKMARK_COUNT: number = 200;
export const MAX_TAB_COUNT: number = 100;
export const MAX_SUGGESTION_COUNT: number = 6;
export const WEEKLY_WINDOW_DAYS: number = 7;
export const RESUME_WINDOW_DAYS: number = 30;
/** The resume snackbar is an offer, not a question: it leaves on its own. */
export const RESUME_PROMPT_TIMEOUT_MS: number = 7000;
export const QUICK_SITE_COUNT: number = QUICK_SITE_LIMIT_MAX;

export const DESKTOP_USER_AGENT: string =
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

/** Reader typography bounds. Line height is stored x100 to stay an integer. */
export const READER_FONT_MIN: number = 15;
/** Four persisted sizes: 15, 17, 19 and 21sp. */
export const READER_FONT_MAX: number = 21;
export const READER_FONT_STEP: number = 2;
export const READER_LINE_HEIGHTS: number[] = [170, 205, 240];

/** Shipped shortcuts that fill start-page slots after user bookmarks. */
export const DEFAULT_QUICK_SITES: QuickSite[] = [
  { title: '知乎', url: 'https://www.zhihu.com', badge: '知', colorIndex: 0 },
  { title: '哔哩哔哩', url: 'https://www.bilibili.com', badge: '哔', colorIndex: 1 },
  { title: '少数派', url: 'https://sspai.com', badge: '派', colorIndex: 2 },
  { title: '微博', url: 'https://weibo.com', badge: '微', colorIndex: 3 },
  { title: '豆瓣', url: 'https://www.douban.com', badge: '豆', colorIndex: 4 },
  { title: '36氪', url: 'https://36kr.com', badge: '氪', colorIndex: 5 }
];

/**
 * URL fragments that identify a blocked request as analytics/telemetry rather
 * than a display ad. Used to split ArkWeb's blocked-request list into the
 * "广告" and "追踪器" buckets shown in the blocking panel.
 */
export const TRACKER_URL_PATTERNS: string[] = [
  'google-analytics', 'googletagmanager', 'analytics.', '/analytics',
  'hm.baidu.com', 'cnzz.com', 'umeng.com', 'talkingdata',
  'scorecardresearch', 'quantserve', 'mixpanel', 'segment.io', 'segment.com',
  'amplitude', 'hotjar', 'clarity.ms', 'sentry.io', 'bugsnag',
  'matomo', 'piwik', 'newrelic', 'track', 'beacon', 'telemetry',
  'pixel', 'collect?', '/stat', 'sensorsdata'
];

/**
 * Hides ad slots, floating overlays and cookie walls that survive the network
 * blocker, and reports what it removed so the blocking panel shows real counts.
 *
 * Idempotent: every node it touches is tagged, so repeated runs report 0.
 * Returns `{"ads":n,"popups":n,"cookieBanners":n}`.
 */
export function contentCleanupScript(strict: boolean): string {
  return `
(function(strict) {
  var TAG = '__mbCleaned';
  var ads = 0, popups = 0, cookieBanners = 0;

  function hide(node) {
    if (!node || node.nodeType !== 1 || node.hasAttribute(TAG)) return false;
    if (node === document.body || node === document.documentElement) return false;
    node.setAttribute(TAG, '1');
    node.style.setProperty('display', 'none', 'important');
    return true;
  }

  var cookieRe = /cookie|consent|gdpr|隐私政策|隐私声明/i;
  var popupRe = /modal|popup|pop-up|overlay|interstitial|lightbox|mask-layer|open-?app|download-?app|下载app|打开app|立即下载/i;
  var adRe = /(^|[-_])ads?([-_]|$)|advert|adsbygoogle|sponsor|promotion|banner-?ad|gg-?wrap/i;

  var viewport = Math.max(1, window.innerWidth * window.innerHeight);
  var documentText = Math.max(1, (document.body.innerText || '').length);

  function tokens(node) {
    return (node.id || '') + ' ' + (typeof node.className === 'string' ? node.className : '');
  }

  // Single-page apps often wrap the whole document in a fixed, full-viewport
  // element. Hiding one of those would blank the page, so anything holding a
  // meaningful share of the text is never treated as an overlay.
  function isPageChrome(node, text) {
    return text.length > documentText * 0.25;
  }

  // Floating overlays and cookie walls are always position:fixed/sticky, so the
  // expensive computed-style check only runs on that much smaller set.
  var floating = document.querySelectorAll('div,section,aside,dialog,ins,iframe');
  var limit = Math.min(floating.length, 2500);
  for (var i = 0; i < limit; i++) {
    var node = floating[i];
    if (node.hasAttribute(TAG)) continue;
    var style = null;
    try { style = window.getComputedStyle(node); } catch (e) { continue; }
    if (!style || style.display === 'none') continue;
    var fixed = style.position === 'fixed' || style.position === 'sticky';
    var text = node.innerText || '';
    if (fixed && !isPageChrome(node, text)) {
      var box = node.getBoundingClientRect();
      var area = Math.max(0, box.width) * Math.max(0, box.height);
      if (cookieRe.test(text.slice(0, 400)) && area > viewport * 0.02) {
        if (hide(node)) cookieBanners++;
        continue;
      }
      // Naming, not size alone: a large fixed element is just as likely to be
      // the site's own layout as it is to be an interstitial.
      if (popupRe.test(tokens(node)) && area > viewport * 0.08) {
        if (hide(node)) popups++;
        continue;
      }
    }
    if (strict && adRe.test(tokens(node))) {
      if (hide(node)) ads++;
    }
  }

  if (strict) {
    var slots = document.querySelectorAll('ins.adsbygoogle,[data-ad-slot],[data-ad-client],[aria-label*="advert" i]');
    for (var j = 0; j < slots.length; j++) {
      if (hide(slots[j])) ads++;
    }
  }

  return JSON.stringify({ ads: ads, popups: popups, cookieBanners: cookieBanners });
})(${strict ? 'true' : 'false'});`;
}

/**
 * Neutralises analytics that already made it into the document: removes known
 * tracker <script> tags and stubs out the beacon APIs they use to phone home.
 * Returns `{"trackers":n}`.
 */
export const TRACKER_BLOCK_SCRIPT: string = `
(function() {
  var TAG = '__mbTracker';
  var patterns = ${JSON.stringify(TRACKER_URL_PATTERNS)};
  var removed = 0;

  var scripts = document.querySelectorAll('script[src],img[src],iframe[src]');
  for (var i = 0; i < scripts.length; i++) {
    var node = scripts[i];
    if (node.hasAttribute(TAG)) continue;
    var src = (node.getAttribute('src') || '').toLowerCase();
    if (!src) continue;
    for (var p = 0; p < patterns.length; p++) {
      if (src.indexOf(patterns[p]) >= 0) {
        node.setAttribute(TAG, '1');
        node.remove();
        removed++;
        break;
      }
    }
  }

  if (!window.__mbBeaconPatched) {
    window.__mbBeaconPatched = true;
    window.__mbBeaconCount = 0;
    if (navigator.sendBeacon) {
      navigator.sendBeacon = function() { window.__mbBeaconCount++; return true; };
    }
  }
  removed += window.__mbBeaconCount || 0;
  window.__mbBeaconCount = 0;

  return JSON.stringify({ trackers: removed });
})();`;

/** Overrides restrictive viewport declarations so native pinch zoom remains available. */
export const FORCE_ZOOM_SCRIPT: string = `
(function() {
  var head = document.head || document.documentElement;
  if (!head) return 'no-head';
  var meta = document.querySelector('meta[name="viewport"]');
  if (!meta) {
    meta = document.createElement('meta');
    meta.setAttribute('name', 'viewport');
    head.appendChild(meta);
  }
  var content = meta.getAttribute('content') || '';
  var parts = content.split(',');
  var kept = [];
  for (var i = 0; i < parts.length; i++) {
    var part = parts[i].trim().toLowerCase();
    if (part.indexOf('user-scalable') === 0 || part.indexOf('maximum-scale') === 0 ||
        part.indexOf('minimum-scale') === 0) {
      continue;
    }
    if (part.length > 0) kept.push(parts[i].trim());
  }
  kept.push('user-scalable=yes');
  kept.push('minimum-scale=0.25');
  kept.push('maximum-scale=5');
  meta.setAttribute('content', kept.join(', '));
  return 'ok';
})();`;

/** Records the link or image under a 500ms touch without preventing page input. */
export const LONG_PRESS_TARGET_SCRIPT: string = `
(function() {
  if (window.__mbLongPressTargetInstalled) return 'ready';
  window.__mbLongPressTargetInstalled = true;
  var timer = 0;
  function cancel() {
    if (timer !== 0) window.clearTimeout(timer);
    timer = 0;
  }
  document.addEventListener('touchstart', function(event) {
    cancel();
    window.__mbLongPressTarget = '';
    var touch = event.touches && event.touches[0];
    if (!touch) return;
    var x = touch.clientX;
    var y = touch.clientY;
    timer = window.setTimeout(function() {
      var node = document.elementFromPoint(x, y);
      if (!node) return;
      var image = node.closest ? node.closest('img') : null;
      var anchor = node.closest ? node.closest('a[href]') : null;
      var target = null;
      if (image && (image.currentSrc || image.src)) {
        target = { kind: 'image', url: image.currentSrc || image.src,
          title: image.alt || document.title || '' };
      } else if (anchor && anchor.href) {
        target = { kind: 'link', url: anchor.href,
          title: (anchor.innerText || anchor.getAttribute('aria-label') || '').trim() };
      }
      if (target && /^(https?):/i.test(target.url)) {
        window.__mbLongPressTarget = JSON.stringify(target);
      }
    }, 500);
  }, { passive: true });
  document.addEventListener('touchend', cancel, { passive: true });
  document.addEventListener('touchcancel', cancel, { passive: true });
  return 'ready';
})();`;

/** Starts a browser-managed download for an image chosen from the context menu. */
export function triggerDownloadScript(url: string): string {
  return `(function() {
    var link = document.createElement('a');
    link.href = ${JSON.stringify(url)};
    link.download = '';
    link.rel = 'noopener';
    document.body.appendChild(link);
    link.click();
    link.remove();
    return 'ok';
  })();`;
}

/**
 * Undoes the tracker/cleanup passes for a site the user allow-listed, including
 * the cosmetic stylesheet — leaving it behind would keep hiding elements on a
 * site whose blocking the user just switched off.
 */
export const RESTORE_HIDDEN_SCRIPT: string = `
(function() {
  // Hiding reaches into every shadow root the page owns, so undoing it has to
  // walk them too, or switching blocking off would leave the deep ones hidden.
  var removed = 0;
  function strip(root, depth) {
    if (depth > 12) return;
    var style = root === document
      ? document.getElementById('__minimalBrowserCosmeticRules')
      : root.__mbCosmeticNode;
    if (style && style.parentNode) {
      style.parentNode.removeChild(style);
      removed++;
    }
    if (root !== document) {
      root.__mbCosmetic = undefined;
      root.__mbCosmeticNode = undefined;
    }
    var cleaned = root.querySelectorAll('[__mbCleaned]');
    for (var i = 0; i < cleaned.length; i++) {
      cleaned[i].removeAttribute('__mbCleaned');
      cleaned[i].style.removeProperty('display');
    }
    var all = root.querySelectorAll('*');
    for (var j = 0; j < all.length; j++) {
      if (all[j].shadowRoot) strip(all[j].shadowRoot, depth + 1);
    }
  }
  if (window.__mbCosmeticObserver) {
    window.__mbCosmeticObserver.disconnect();
    window.__mbCosmeticObserver = undefined;
  }
  strip(document, 0);
  return 'restored ' + removed;
})();`;

export const READ_SCROLL_POSITION_SCRIPT: string = `
(function() {
  return String(Math.max(0, Math.round(window.scrollY || 0)));
})();`;

/**
 * Reports '1' when the content under the given viewport point is scrolled away
 * from the top — the document itself or any scrollable ancestor of the touched
 * element. The document-level onScroll event never fires for inner scroll
 * containers, so without this check a downward drag on a scrolled list would
 * be mistaken for a pull-to-refresh. Falls back to scanning every scrollable
 * element when no point is supplied, and to '1' (block the pull) on error so
 * the gesture errs on the side of not refreshing mid-list.
 */
export function scrolledFromTopScript(x: number, y: number): string {
  const px: number = Math.max(0, Math.round(x));
  const py: number = Math.max(0, Math.round(y));
  const usePoint: boolean = x >= 0 && y >= 0;
  const pointQuery: string = usePoint
    ? `
    var el = document.elementFromPoint(${px}, ${py});
    while (el && el !== doc) {
      if (el.scrollTop > 8) return '1';
      el = el.parentElement;
    }`
    : `
    var all = document.querySelectorAll('*');
    for (var i = 0; i < all.length; i++) {
      var node = all[i];
      if (node.scrollTop > 8 && node.scrollHeight - node.clientHeight > 8) return '1';
    }`;
  return `
(function() {
  try {
    var doc = document.scrollingElement || document.documentElement;
    if (doc.scrollTop > 8) return '1';${pointQuery}
    return '0';
  } catch (e) {
    return '1';
  }
})();`;
}

export const READ_FORM_DRAFT_SCRIPT: string = `
(function() {
  var fields = document.querySelectorAll('input:not([type="password"]),textarea,select');
  var draft = [];
  for (var i = 0; i < fields.length && draft.length < 80; i++) {
    var field = fields[i];
    var key = field.id || field.name || ('field-' + i);
    var value = field.value || '';
    if (value.length > 0) draft.push({ key: key, value: value });
  }
  return JSON.stringify(draft);
})();`;

export const READ_FAVICON_SCRIPT: string = `
(function() {
  var links = document.querySelectorAll('link[rel~="icon"],link[rel="shortcut icon"],link[rel="apple-touch-icon"]');
  for (var i = 0; i < links.length; i++) {
    var href = links[i].href || links[i].getAttribute('href') || '';
    if (href.length > 0) return href;
  }
  return '';
})();`;

export function restoreScrollPositionScript(position: number): string {
  const safePosition: number = Math.max(0, Math.round(position));
  return `
(function() {
  window.scrollTo(0, ${safePosition});
  return 'restored';
})();`;
}

export function restoreFormDraftScript(draft: string): string {
  const payload: string = JSON.stringify(draft);
  return `(function(serialized) {
  var fields = document.querySelectorAll('input:not([type="password"]),textarea,select');
  var draft = [];
  try { draft = JSON.parse(serialized || '[]'); } catch (e) { return 'invalid'; }
  for (var i = 0; i < fields.length; i++) {
    var field = fields[i];
    var key = field.id || field.name || ('field-' + i);
    for (var j = 0; j < draft.length; j++) {
      if (draft[j].key === key) { field.value = draft[j].value || ''; break; }
    }
  }
  return 'restored';
})(${payload});`;
}

/** Makes a mobile page lay out at desktop width once the desktop UA is set. */
export const DESKTOP_VIEWPORT_SCRIPT: string = `
(function() {
  var meta = document.querySelector('meta[name="viewport"]');
  if (!meta) {
    meta = document.createElement('meta');
    meta.setAttribute('name', 'viewport');
    document.head.appendChild(meta);
  }
  meta.setAttribute('content', 'width=device-width, initial-scale=1');
  return 'desktop';
})();`;

/**
 * Watches for password fields being focused. On insecure (HTTP) pages this is
 * the only way to warn the user, since there is no browser-level indicator the
 * page controls.
 */
export const PASSWORD_FIELD_WATCHER_SCRIPT: string = `
(function() {
  if (window.__mbPasswordWatcher) return 'watching';
  window.__mbPasswordWatcher = true;
  document.addEventListener('focusin', function(event) {
    var target = event.target;
    if (target && target.tagName === 'INPUT' && (target.type === 'password')) {
      if (window.dolphinSecurity && window.dolphinSecurity.notifyPasswordFocus) {
        window.dolphinSecurity.notifyPasswordFocus();
      }
    }
  }, true);
  return 'armed';
})();`;

/**
 * Extracts the article on first run, then restyles it. Called again on every
 * font-size / line-height / paper change without re-extracting.
 */
export function readerApplyScript(
  fontSize: number,
  lineHeight: number,
  paperBackground: string,
  bodyColor: string,
  titleColor: string,
  accentColor: string
): string {
  const lineHeightRatio: string = (lineHeight / 100).toFixed(2);
  return `
(function(fontSize, lineHeight, paper, body, title, accent) {
  var S = window.__mbReader || (window.__mbReader = {});

  if (!S.active) {
    var candidates = document.querySelectorAll(
      'article, main, [role="main"], [itemprop="articleBody"], .article, .article-body, .article-content, ' +
      '.post, .post-body, .post-content, .entry-content, .story-body, .story-content, .content, #content'
    );
    var best = null, bestScore = 0, bestLength = 0;
    for (var i = 0; i < candidates.length; i++) {
      var candidate = candidates[i];
      var probe = candidate.cloneNode(true);
      var probeNoise = probe.querySelectorAll(
        'script,style,iframe,noscript,form,button,nav,aside,header,footer,' +
        '[role="navigation"],[role="complementary"],[aria-label*="comment"]'
      );
      for (var noiseIndex = 0; noiseIndex < probeNoise.length; noiseIndex++) {
        probeNoise[noiseIndex].remove();
      }
      // ArkWeb can return an empty innerText for detached clones. textContent
      // keeps candidate scoring on the complete DOM instead of falling back to
      // an arbitrary run of long paragraphs that may omit a valid short lead.
      var text = (probe.innerText || probe.textContent || '').trim();
      var length = text.length;
      if (length < 240) continue;
      var paragraphs = candidate.querySelectorAll('p').length;
      var linkNodes = candidate.querySelectorAll('a');
      var links = linkNodes.length;
      var linkText = 0;
      for (var linkIndex = 0; linkIndex < links; linkIndex++) {
        linkText += (linkNodes[linkIndex].innerText || linkNodes[linkIndex].textContent || '').length;
      }
      var punctuation = (text.match(/[。！？.!?]/g) || []).length;
      var paragraphDensity = paragraphs === 0 ? 0 : Math.min(1, punctuation / paragraphs / 2);
      var semanticBoost = /^(ARTICLE|MAIN)$/i.test(candidate.tagName) ? 240 : 0;
      var score = length + Math.min(paragraphs, 80) * 70 + punctuation * 8 +
        paragraphDensity * 260 + semanticBoost - Math.min(linkText, length) * 0.6;
      if (score > bestScore) {
        bestScore = score;
        bestLength = length;
        best = candidate;
      }
    }
    if (!best || bestLength < 240) {
      var paragraphNodes = document.querySelectorAll('p');
      var fallback = document.createElement('div');
      var fallbackLength = 0;
      for (var paragraphIndex = 0; paragraphIndex < paragraphNodes.length; paragraphIndex++) {
        var paragraph = paragraphNodes[paragraphIndex];
        var paragraphText = (paragraph.innerText || paragraph.textContent || '').trim();
        if (paragraphText.length < 24) continue;
        fallback.appendChild(paragraph.cloneNode(true));
        fallbackLength += paragraphText.length;
        if (fallbackLength >= 1600) break;
      }
      if (fallbackLength >= 240) {
        best = fallback;
        bestLength = fallbackLength;
      }
    }
    if (!best || bestLength < 240) return 'no-article';

    var heading = best.querySelector ? best.querySelector('h1') : null;
    var ogTitle = document.querySelector('meta[property="og:title"]');
    var headingText = heading ? (heading.innerText || heading.textContent || '') :
      (ogTitle ? ogTitle.getAttribute('content') : document.title);
    var content = best.innerHTML;

    S.body = document.body.innerHTML;
    S.bodyStyle = document.body.getAttribute('style') || '';
    S.scroll = window.scrollY;

    document.body.innerHTML = '';
    var article = document.createElement('article');
    article.id = '__mb-reader';

    var titleNode = document.createElement('h1');
    titleNode.textContent = headingText;
    article.appendChild(titleNode);

    var wrapper = document.createElement('div');
    wrapper.className = '__mb-reader-body';
    wrapper.innerHTML = content;
    var noise = wrapper.querySelectorAll(
      'script,style,iframe,noscript,form,button,nav,aside,header,footer,video,' +
      '[role="navigation"],[role="complementary"],[aria-label*="comment"]'
    );
    for (var n = 0; n < noise.length; n++) { noise[n].remove(); }
    var chrome = wrapper.querySelectorAll(
      '[class*="comment"],[class*="recommend"],[class*="related"],' +
      '[class*="breadcrumb"],[class*="sidebar"],[class*="advert"],[id*="comment"]'
    );
    for (var chromeIndex = 0; chromeIndex < chrome.length; chromeIndex++) {
      chrome[chromeIndex].remove();
    }
    if ((wrapper.innerText || wrapper.textContent || '').trim().length < 240) {
      document.body.innerHTML = S.body;
      document.body.setAttribute('style', S.bodyStyle);
      return 'no-article';
    }
    article.appendChild(wrapper);

    document.body.appendChild(article);
    window.scrollTo(0, 0);
    S.active = true;
  }

  var sheet = document.getElementById('__mb-reader-css');
  if (!sheet) {
    sheet = document.createElement('style');
    sheet.id = '__mb-reader-css';
    document.head.appendChild(sheet);
  }
  sheet.textContent =
    'html,body{background:' + paper + ' !important;margin:0 !important;padding:0 !important}' +
    '#__mb-reader{max-width:680px;margin:0 auto;padding:26px 22px 64px;' +
      'font-family:"Noto Serif SC","Songti SC",Georgia,serif;color:' + body + '}' +
    '#__mb-reader h1{font-size:' + (fontSize + 8) + 'px;line-height:1.55;font-weight:600;' +
      'color:' + title + ';margin:0 0 22px;text-wrap:pretty}' +
    '#__mb-reader .__mb-reader-body{font-size:' + fontSize + 'px;line-height:' + lineHeight + ';' +
      'text-align:justify;color:' + body + '}' +
    '#__mb-reader p{margin:0 0 ' + Math.round(fontSize * 1.3) + 'px}' +
    '#__mb-reader h2,#__mb-reader h3{color:' + title + ';line-height:1.5;margin:1.6em 0 .6em}' +
    '#__mb-reader img{max-width:100%;height:auto;border-radius:10px;display:block;margin:22px auto}' +
    '#__mb-reader a{color:' + accent + ';text-decoration:none}' +
    '#__mb-reader pre,#__mb-reader code{font-family:ui-monospace,Menlo,monospace;font-size:' +
      (fontSize - 3) + 'px}' +
    '#__mb-reader pre{overflow-x:auto;padding:14px;border-radius:10px;background:rgba(128,128,128,.12)}' +
    '#__mb-reader blockquote{margin:1.4em 0;padding-left:16px;border-left:2px solid ' + accent + ';opacity:.85}';

  document.body.setAttribute('style', 'margin:0;background:' + paper + ';');
  return 'reader';
})(${fontSize}, '${lineHeightRatio}', '${paperBackground}', '${bodyColor}', '${titleColor}', '${accentColor}');`;
}

/** Puts the original document back. */
export const READER_EXIT_SCRIPT: string = `
(function() {
  var S = window.__mbReader;
  if (!S || !S.active) return 'not-reader';
  var sheet = document.getElementById('__mb-reader-css');
  if (sheet) sheet.remove();
  document.body.innerHTML = S.body;
  document.body.setAttribute('style', S.bodyStyle);
  window.scrollTo(0, S.scroll || 0);
  S.active = false;
  return 'restored';
})();`;

/** Extracts the best readable article candidate into a detached, script-free snapshot. */
export const ARTICLE_CAPTURE_SCRIPT: string = `
(function() {
  var candidates = document.querySelectorAll(
    'article,main,[role="main"],[itemprop="articleBody"],.article,.article-body,.article-content,' +
    '.post,.post-body,.post-content,.entry-content,.story-body,.story-content,.content,#content'
  );
  var best = null;
  var bestScore = 0;
  for (var candidateIndex = 0; candidateIndex < candidates.length; candidateIndex++) {
    var candidate = candidates[candidateIndex];
    var probe = candidate.cloneNode(true);
    var probeNoise = probe.querySelectorAll(
      'script,style,noscript,iframe,form,button,nav,aside,header,footer,' +
      '[role="navigation"],[role="complementary"],[aria-label*="comment"]'
    );
    for (var probeIndex = 0; probeIndex < probeNoise.length; probeIndex++) probeNoise[probeIndex].remove();
    var candidateText = (probe.innerText || probe.textContent || '').trim();
    if (candidateText.length < 240) continue;
    var paragraphs = candidate.querySelectorAll('p').length;
    var linkText = 0;
    var links = candidate.querySelectorAll('a');
    for (var linkIndex = 0; linkIndex < links.length; linkIndex++) {
      linkText += (links[linkIndex].innerText || links[linkIndex].textContent || '').length;
    }
    var punctuation = (candidateText.match(/[。！？.!?]/g) || []).length;
    var semanticBoost = /^(ARTICLE|MAIN)$/i.test(candidate.tagName) ? 240 : 0;
    var score = candidateText.length + Math.min(paragraphs, 80) * 70 + punctuation * 8 +
      semanticBoost - Math.min(linkText, candidateText.length) * 0.6;
    if (score > bestScore) {
      bestScore = score;
      best = candidate;
    }
  }
  if (!best) {
    return JSON.stringify({ title: document.title || '', author: '', canonicalUrl: location.href,
      html: '', text: '', markdown: '', images: [] });
  }

  var article = best.cloneNode(true);
  var blocked = article.querySelectorAll(
    'script,style,noscript,iframe,form,button,nav,aside,header,footer,video,' +
    '[role="navigation"],[role="complementary"],[aria-label*="comment"],' +
    '[class*="comment"],[class*="recommend"],[class*="related"],[class*="breadcrumb"],' +
    '[class*="sidebar"],[class*="advert"],[id*="comment"]'
  );
  for (var blockedIndex = 0; blockedIndex < blocked.length; blockedIndex++) blocked[blockedIndex].remove();

  var originalImages = best.querySelectorAll('img');
  var copiedImages = article.querySelectorAll('img');
  var images = [];
  for (var imageIndex = 0; imageIndex < copiedImages.length && imageIndex < originalImages.length; imageIndex++) {
    var source = originalImages[imageIndex].currentSrc || originalImages[imageIndex].src || '';
    if (!/^https?:\\/\\//i.test(source)) continue;
    var path = source.split('?')[0].split('#')[0];
    var extension = (path.match(/\\.([a-zA-Z0-9]+)$/) || [])[1] || 'jpg';
    extension = /^(jpg|jpeg|png|gif|webp|avif|svg)$/i.test(extension) ? extension.toLowerCase() : 'jpg';
    var fileName = 'image-' + imageIndex + '.' + extension;
    copiedImages[imageIndex].setAttribute('src', 'images/' + fileName);
    copiedImages[imageIndex].removeAttribute('srcset');
    copiedImages[imageIndex].removeAttribute('data-src');
    images.push({ index: imageIndex, url: source, fileName: fileName });
  }
  var elements = article.querySelectorAll('*');
  for (var elementIndex = 0; elementIndex < elements.length; elementIndex++) {
    var attributes = Array.prototype.slice.call(elements[elementIndex].attributes || []);
    for (var attributeIndex = 0; attributeIndex < attributes.length; attributeIndex++) {
      var attributeName = attributes[attributeIndex].name.toLowerCase();
      if (attributeName.indexOf('on') === 0 || attributeName === 'style') {
        elements[elementIndex].removeAttribute(attributes[attributeIndex].name);
      }
    }
    var href = elements[elementIndex].getAttribute('href') || '';
    if (/^javascript:/i.test(href)) elements[elementIndex].removeAttribute('href');
  }

  function normalizedText(node) {
    return (node.textContent || '').replace(/\\s+/g, ' ').trim();
  }
  function markdownFor(node) {
    if (!node) return '';
    if (node.nodeType === 3) return (node.nodeValue || '').replace(/\\s+/g, ' ');
    if (node.nodeType !== 1) return '';
    var tag = node.tagName.toLowerCase();
    if (tag === 'img') {
      var imageSource = node.getAttribute('src') || '';
      var imageAlt = (node.getAttribute('alt') || '').replace(/[\\[\\]]/g, '');
      return imageSource ? '![' + imageAlt + '](' + imageSource + ')' : '';
    }
    if (tag === 'pre') {
      var fence = String.fromCharCode(96, 96, 96);
      return '\\n\\n' + fence + '\\n' + (node.textContent || '').trim() + '\\n' + fence + '\\n\\n';
    }
    var childMarkdown = '';
    for (var childIndex = 0; childIndex < node.childNodes.length; childIndex++) {
      childMarkdown += markdownFor(node.childNodes[childIndex]);
    }
    childMarkdown = childMarkdown.trim();
    if (!childMarkdown) return '';
    if (/^h[1-6]$/.test(tag)) {
      return '\\n\\n' + new Array(Number(tag.substring(1)) + 1).join('#') + ' ' + childMarkdown + '\\n\\n';
    }
    if (tag === 'p' || tag === 'section' || tag === 'div') return '\\n\\n' + childMarkdown + '\\n\\n';
    if (tag === 'li') return '\\n- ' + childMarkdown;
    if (tag === 'blockquote') return '\\n\\n> ' + childMarkdown.replace(/\\n/g, '\\n> ') + '\\n\\n';
    if (tag === 'br') return '\\n';
    if (tag === 'strong' || tag === 'b') return '**' + childMarkdown + '**';
    if (tag === 'em' || tag === 'i') return '*' + childMarkdown + '*';
    if (tag === 'a') {
      var link = node.getAttribute('href') || '';
      return link ? '[' + childMarkdown + '](' + link + ')' : childMarkdown;
    }
    return childMarkdown;
  }
  var canonical = document.querySelector('link[rel="canonical"]');
  var authorMeta = document.querySelector(
    'meta[name="author"],meta[property="article:author"],[rel="author"],[itemprop="author"]'
  );
  var author = authorMeta ? (authorMeta.getAttribute('content') || normalizedText(authorMeta)) : '';
  var heading = best.querySelector('h1');
  var title = heading ? normalizedText(heading) : (document.title || '');
  var text = normalizedText(article);
  var markdown = markdownFor(article).replace(/\\n{3,}/g, '\\n\\n').trim();
  return JSON.stringify({
    title: title,
    author: author,
    canonicalUrl: canonical && canonical.href ? canonical.href : location.href,
    html: article.outerHTML || '',
    text: text,
    markdown: markdown,
    images: images
  });
})();`;

/** Counts visible text matches while ArkWeb owns native highlighting/navigation. */
export function findCountScript(query: string): string {
  const serialized: string = JSON.stringify(query.trim().toLowerCase());
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
