(function() {
  if (window.__mbLongPressTargetInstalled) return 'ready';
  window.__mbLongPressTargetInstalled = true;
  var lastX = 0, lastY = 0;
  document.addEventListener('touchstart', function(event) {
    var touch = event.touches && event.touches[0];
    if (!touch) return;
    lastX = touch.clientX;
    lastY = touch.clientY;
  }, { passive: true });
  window.__mbResolveLongPressTarget = function() {
    var node = document.elementFromPoint(lastX, lastY);
    if (!node) return "";
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
      return JSON.stringify(target);
    }
    return "";
  };
  return 'ready';
})();
