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

  // Fallback for window.open when multi-window is disabled in webview
  try {
    var origOpen = window.open;
    window.open = function(url, target, features) {
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

    // Clicked outside any language dropdown -> close all open dropdowns and blur active element
    var openContainers = document.querySelectorAll('[data-zhuo-dropdown="open"]');
    for (var i = 0; i < openContainers.length; i++) {
      openContainers[i].setAttribute('data-zhuo-dropdown', 'closed');
    }
    try {
      if (document.activeElement && document.activeElement.blur && document.activeElement !== document.body) {
        document.activeElement.blur();
      }
    } catch (_e) {}
  }
  document.addEventListener('click', handleDropdownClick, true);

  return 'armed';
})();
