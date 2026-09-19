(function() {
  if (window.__zhuoBlockedLinkGuard) return 'armed';
  window.__zhuoBlockedLinkGuard = true;
  var blocked = /^(?:javascript|arkweb|chrome|chrome-devtools|devtools):/i;
  var dummyJs = /^(?:javascript|#):?\s*(?:\/\*[\s\S]*?\*\/|\/\/.*[\r\n]*)*\s*(?:void\s*(?:\(\s*['"]?[0-9a-z_]*['"]?\s*\)|[0-9a-z_]+)|;|#|null|undefined|return\s+(?:false|true);?|false|true)?\s*;?\s*(?:\/\*[\s\S]*?\*\/)?$/i;

  function nearestLink(node) {
    if (!node || node === document) return null;
    if (node.closest) {
      try {
        return node.closest('a, area');
      } catch (_e) {}
    }
    while (node && node !== document) {
      var tag = (node.tagName || '').toUpperCase();
      if (tag === 'A' || tag === 'AREA') return node;
      node = node.parentNode;
    }
    return null;
  }

  function extractUrl(node, attr) {
    var raw = node && node.getAttribute ? (node.getAttribute(attr) || '').trim() : '';
    try {
      return decodeURIComponent(raw);
    } catch (_e) {
      return raw;
    }
  }

  function sameDocumentTarget(url) {
    try {
      var target = new URL(url, window.location.href);
      if (target.origin !== window.location.origin) return null;
      if (target.pathname !== window.location.pathname) return null;
      if (target.search !== window.location.search) return null;
      return target;
    } catch (_e) {
      return null;
    }
  }

  function dispatchSpaHash(hash) {
    if (window.location.hash !== hash) {
      var old = window.location.href;
      window.location.hash = hash;
      try {
        if (typeof HashChangeEvent !== 'undefined') {
          window.dispatchEvent(new HashChangeEvent('hashchange', { oldURL: old, newURL: window.location.href }));
        } else if (typeof CustomEvent !== 'undefined') {
          window.dispatchEvent(new CustomEvent('hashchange', { detail: { oldURL: old, newURL: window.location.href } }));
        } else if (document.createEvent) {
          var ev = document.createEvent('HTMLEvents');
          ev.initEvent('hashchange', true, true);
          window.dispatchEvent(ev);
        }
      } catch (_e) {}
    }
  }

  // Hash <a> clicks in SPAs where native anchor navigation was intercepted or suppressed.
  // Only sync if the hash actually differs, and never fire duplicate synthetic PopStateEvent
  // or window.location.reload() which break Vue Router 4 view mount/unmount lifecycles.
  document.addEventListener('click', function(event) {
    if (event.button && event.button !== 0) return;
    if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
    var link = nearestLink(event.target);
    if (!link) return;
    var resolved = sameDocumentTarget(link.href || extractUrl(link, 'href'));
    if (!resolved || !resolved.hash) return;
    var wanted = resolved.hash;
    setTimeout(function() {
      if (window.location.hash !== wanted) {
        dispatchSpaHash(wanted);
      }
    }, 0);
  }, false);

  function stopBlockedLink(event) {
    var link = nearestLink(event.target);
    var href = extractUrl(link, 'href');
    if (!blocked.test(href)) return;
    event.preventDefault();
    if (!dummyJs.test(href)) {
      event.stopImmediatePropagation();
    }
  }

  document.addEventListener('click', stopBlockedLink, true);
  document.addEventListener('auxclick', stopBlockedLink, true);
  document.addEventListener('submit', function(event) {
    var form = event.target;
    var action = extractUrl(form, 'action');
    if (!blocked.test(action)) return;
    event.preventDefault();
    if (!dummyJs.test(action)) {
      event.stopImmediatePropagation();
    }
  }, true);

  // Fallback for window.open when multi-window is disabled in webview.
  // Same-document hash targets must use location.hash: assigning location.href
  // (or letting ArkWeb loadUrl the fragment) updates history without
  // dispatching hashchange, so SPA tab clicks appear to do nothing.
  try {
    var origOpen = window.open;
    window.open = function(url, target, features) {
      if (url && typeof url === 'string') {
        var hashTarget = sameDocumentTarget(url.trim());
        if (hashTarget !== null && hashTarget.hash) {
          dispatchSpaHash(hashTarget.hash);
          return window;
        }
      }
      var result = null;
      try {
        if (origOpen) result = origOpen.call(window, url, target, features);
      } catch (_e) {}
      if (!result && url && typeof url === 'string') {
        var u = url.trim();
        if (u && !blocked.test(u)) {
          window.location.href = u;
          return window;
        }
      }
      return result;
    };
  } catch (_e) {}

  // Huawei's callback shells only contain scripts. When a callback arrives from
  // another browser, its state and return-location cookies are absent, so the
  // site's own code cannot recover and leaves a permanently blank document.
  // Keep this scoped to the two observed Huawei callbacks, and never interrupt
  // a callback whose state cookie still proves an in-browser login flow.
  try {
    var callbackPath = window.location.pathname || '';
    var callbackFile = 'handleAllianceLogin.html';
    var recoveryPath = '';
    if (callbackPath.indexOf('/service/josp/agc/' + callbackFile) !== -1) {
      recoveryPath = callbackPath.substring(0, callbackPath.length - callbackFile.length) + 'index.html';
    } else if (callbackPath.indexOf('/hdc-console/' + callbackFile) !== -1) {
      recoveryPath = callbackPath.substring(0, callbackPath.length - callbackFile.length);
    }
    if (recoveryPath) {
      setTimeout(function() {
        if (window.location.pathname === callbackPath) {
          var body = document.body;
          var hasContent = body && (body.innerText || '').trim().length > 0;
          var stateMatch = (window.location.search || '').match(/[?&]state=([^&]+)/);
          var cookieMatch = (document.cookie || '').match(/(?:^|;\s*)state=([^;]+)/);
          var queryState = stateMatch ? decodeURIComponent(stateMatch[1]) : '';
          var cookieState = cookieMatch ? decodeURIComponent(cookieMatch[1]) : '';
          var hasValidLoginState = queryState && cookieState && queryState === cookieState;
          if (!hasContent && !hasValidLoginState) {
            window.location.href = window.location.origin + recoveryPath;
          }
        }
      }, 2500);
    }
  } catch (_e) {}

  // Touch / pointer hover toggle helper:
  // When an element uses CSS :hover to show dropdowns (like .header-lang),
  // tapping on touch devices leaves :hover active indefinitely.
  // This helper tracks tap/click toggling on hover menus so tapping the trigger
  // toggles between open and closed, and tapping outside resets/closes it.
  function ensureHoverStyle() {
    try {
      if (!document.getElementById('__zhuo_touch_hover_style')) {
        var s = document.createElement('style');
        s.id = '__zhuo_touch_hover_style';
        s.textContent = [
          '.header-lang[data-zhuo-dropdown="open"] .header-lang-list { display: block !important; }',
          '.header-lang[data-zhuo-dropdown="open"] .header-icon-arrow-down { transform: rotateX(180deg) !important; -webkit-transform: rotateX(180deg) !important; }',
          '.header-lang[data-zhuo-dropdown="closed"] .header-lang-list { display: none !important; }',
          '.header-lang[data-zhuo-dropdown="closed"] .header-icon-arrow-down { transform: rotateX(0deg) !important; -webkit-transform: rotateX(0deg) !important; }',
          '.__zhuo_touch_closed .header-lang-list, .__zhuo_touch_closed .dropdown-menu { display: none !important; }'
        ].join(' ');
        (document.head || document.documentElement).appendChild(s);
      }
    } catch (_e) {}
  }
  ensureHoverStyle();

  function handleDropdownClick(event) {
    var target = event.target;
    if (!target) return;
    ensureHoverStyle();

    var langContainer = target.closest ? target.closest('.header-lang') : null;
    if (langContainer) {
      var menuItem = target.closest('.header-lang-item');
      if (menuItem) {
        // User clicked an actual language choice item
        langContainer.setAttribute('data-zhuo-dropdown', 'closed');
        return;
      }
      // User clicked on the language trigger or toggle area
      var currentState = langContainer.getAttribute('data-zhuo-dropdown');
      if (currentState === 'open') {
        langContainer.setAttribute('data-zhuo-dropdown', 'closed');
      } else {
        langContainer.setAttribute('data-zhuo-dropdown', 'open');
      }
      return;
    }

    // Clicked outside any language dropdown -> close open dropdowns without unfocusing page inputs
    var openContainers = document.querySelectorAll('[data-zhuo-dropdown="open"]');
    if (!openContainers || !openContainers.length) return;
    for (var i = 0; i < openContainers.length; i++) {
      var container = openContainers[i];
      container.setAttribute('data-zhuo-dropdown', 'closed');
      try {
        if (document.activeElement && document.activeElement.blur && container.contains(document.activeElement)) {
          document.activeElement.blur();
        }
      } catch (_e) {}
    }
  }
  document.addEventListener('click', handleDropdownClick, true);

  return 'armed';
})();
