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
})();
