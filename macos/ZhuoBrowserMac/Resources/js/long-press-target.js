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
})();
