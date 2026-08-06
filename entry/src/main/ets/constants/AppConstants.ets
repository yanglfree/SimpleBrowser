import { QuickSite } from '../models/BrowserModels';

/** Internal URL for the native start page. It is never handed to ArkWeb. */
export const HOME_URL: string = 'browser://home';
export const STORE_NAME: string = 'minimal_browser_store';
export const SESSION_KEY: string = 'browser_session';
export const TAB_ARCHIVE_KEY: string = 'tab_archive';
export const APP_VERSION: string = '1.2.0';

export const MAX_HISTORY_COUNT: number = 300;
export const MAX_BOOKMARK_COUNT: number = 200;
export const MAX_TAB_COUNT: number = 100;
export const MAX_SUGGESTION_COUNT: number = 6;
export const WEEKLY_WINDOW_DAYS: number = 7;
export const RESUME_WINDOW_DAYS: number = 30;
export const QUICK_SITE_COUNT: number = 6;

export const DESKTOP_USER_AGENT: string =
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

/** Reader typography bounds. Line height is stored x100 to stay an integer. */
export const READER_FONT_MIN: number = 15;
/** Four persisted sizes: 15, 17, 19 and 21sp. */
export const READER_FONT_MAX: number = 21;
export const READER_FONT_STEP: number = 2;
export const READER_LINE_HEIGHTS: number[] = [170, 205, 240];

/** Shown on a fresh install, before history has anything to rank. */
export const DEFAULT_QUICK_SITES: QuickSite[] = [
  { title: '知乎', url: 'https://www.zhihu.com', badge: '知', colorIndex: 0 },
  { title: '哔哩哔哩', url: 'https://m.bilibili.com', badge: '哔', colorIndex: 1 },
  { title: '少数派', url: 'https://sspai.com', badge: '派', colorIndex: 2 },
  { title: '微博', url: 'https://m.weibo.cn', badge: '微', colorIndex: 3 },
  { title: '豆瓣', url: 'https://m.douban.com', badge: '豆', colorIndex: 4 },
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

/** Undoes the tracker/cleanup passes for a site the user allow-listed. */
export const RESTORE_HIDDEN_SCRIPT: string = `
(function() {
  var nodes = document.querySelectorAll('[__mbCleaned]');
  for (var i = 0; i < nodes.length; i++) {
    nodes[i].removeAttribute('__mbCleaned');
    nodes[i].style.removeProperty('display');
  }
  return 'restored';
})();`;

export const READ_SCROLL_POSITION_SCRIPT: string = `
(function() {
  return String(Math.max(0, Math.round(window.scrollY || 0)));
})();`;

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
  meta.setAttribute('content', 'width=1024');
  return 'desktop';
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
      'article, main, [role="main"], [itemprop="articleBody"], .article, .article-content, ' +
      '.post, .post-content, .entry-content, .story-body, #content'
    );
    var best = null, bestScore = 0, bestLength = 0;
    for (var i = 0; i < candidates.length; i++) {
      var candidate = candidates[i];
      var text = (candidate.innerText || '').trim();
      var length = text.length;
      if (length < 240) continue;
      var paragraphs = candidate.querySelectorAll('p').length;
      var links = candidate.querySelectorAll('a').length;
      var linkText = 0;
      for (var linkIndex = 0; linkIndex < links; linkIndex++) {
        linkText += (candidate.querySelectorAll('a')[linkIndex].innerText || '').length;
      }
      var score = length + Math.min(paragraphs, 80) * 80 - Math.min(linkText, length) * 0.25;
      if (score > bestScore) {
        bestScore = score;
        bestLength = length;
        best = candidate;
      }
    }
    if (!best || bestLength < 240) return 'no-article';

    var heading = document.querySelector('h1');
    var headingText = heading ? heading.innerText : document.title;
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
    var noise = wrapper.querySelectorAll('script,style,iframe,noscript,form,button,nav,aside,video');
    for (var n = 0; n < noise.length; n++) { noise[n].remove(); }
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
