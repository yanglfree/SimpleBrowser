(function() {
  var S = window.__mbReader;
  if (!S || !S.active) return 'not-reader';
  var sheet = document.getElementById('__mb-reader-css');
  if (sheet) sheet.remove();
  var viewport = document.querySelector('meta[name="viewport"]');
  if (viewport) {
    if (!S.viewportExisted) viewport.remove();
    else if (S.viewportContent === null) viewport.removeAttribute('content');
    else viewport.setAttribute('content', S.viewportContent);
  }
  document.body.innerHTML = S.body;
  document.body.setAttribute('style', S.bodyStyle);
  window.scrollTo(0, S.scroll || 0);
  S.active = false;
  return 'restored';
})();
