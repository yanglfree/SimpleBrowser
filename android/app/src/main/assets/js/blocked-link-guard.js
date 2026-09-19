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

  function applyNativeHash(hash) {
    if (window.location.hash !== hash) window.location.hash = hash;
  }

  // Some embedded engines fail to apply an otherwise ordinary same-document
  // anchor after the click completes. Compensate only when the page did not
  // cancel the click and only for current-window navigation. Assigning the
  // native hash preserves browser history and lets the engine own its events.
  document.addEventListener('click', function(event) {
    if (event.button && event.button !== 0) return;
    if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
    var link = nearestLink(event.target);
    if (!link) return;
    var target = extractUrl(link, 'target').toLowerCase();
    if (target && target !== '_self') return;
    if (link.hasAttribute && link.hasAttribute('download')) return;
    var resolved = sameDocumentTarget(link.href || extractUrl(link, 'href'));
    if (!resolved || !resolved.hash) return;
    var wanted = resolved.hash;
    setTimeout(function() {
      if (event.defaultPrevented) return;
      if (window.location.hash !== wanted) {
        applyNativeHash(wanted);
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

  // Preserve window.open semantics. A failed explicit _self navigation may be
  // recovered in the current document, but new-window intent must never be
  // converted into a current-page redirect.
  try {
    var origOpen = window.open;
    window.open = function(url, target, features) {
      var result = null;
      try {
        if (origOpen) result = origOpen.call(window, url, target, features);
      } catch (_e) {}
      if (result) return result;
      var normalizedTarget = typeof target === 'string' ? target.trim().toLowerCase() : '';
      if (normalizedTarget !== '_self') return result;
      if (url && typeof url === 'string') {
        var u = url.trim();
        if (u && !blocked.test(u)) {
          var hashTarget = sameDocumentTarget(u);
          if (hashTarget !== null && hashTarget.hash) {
            applyNativeHash(hashTarget.hash);
            return window;
          }
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
