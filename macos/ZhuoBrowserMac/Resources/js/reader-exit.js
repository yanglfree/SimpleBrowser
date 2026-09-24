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
  var reader = document.getElementById('__mb-reader');
  if (reader) reader.remove();
  if (S.bodyStyle === null) document.body.removeAttribute('style');
  else document.body.setAttribute('style', S.bodyStyle);
  if (S.documentHandlers) {
    if (document.onselectstart === null) document.onselectstart = S.documentHandlers.selectstart;
    if (document.oncopy === null) document.oncopy = S.documentHandlers.copy;
    if (document.oncontextmenu === null) document.oncontextmenu = S.documentHandlers.contextmenu;
  }
  if (S.bodyHandlers) {
    if (document.body.onselectstart === null) document.body.onselectstart = S.bodyHandlers.selectstart;
    if (document.body.oncopy === null) document.body.oncopy = S.bodyHandlers.copy;
    if (document.body.oncontextmenu === null) document.body.oncontextmenu = S.bodyHandlers.contextmenu;
  }
  window.scrollTo(0, S.scroll || 0);
  S.active = false;
  return 'restored';
})();
