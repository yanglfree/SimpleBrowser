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
  var adRe = new RegExp("(^|[\\s_-])ads?([\\s_-]|$)|advert|adsbygoogle|sponsor|promotion|banner-?ad|gg-?wrap", 'i');

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
})(true);
