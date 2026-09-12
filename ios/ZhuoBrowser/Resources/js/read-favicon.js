(function() {
  var links = document.querySelectorAll('link[rel~="icon"],link[rel="shortcut icon"],link[rel="apple-touch-icon"]');
  for (var i = 0; i < links.length; i++) {
    var href = links[i].href || links[i].getAttribute('href') || '';
    if (href.length > 0) return href;
  }
  return '';
})();
