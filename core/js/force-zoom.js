(function() {
  var head = document.head || document.documentElement;
  if (!head) return 'no-head';
  var meta = document.querySelector('meta[name="viewport"]');
  if (!meta) {
    meta = document.createElement('meta');
    meta.setAttribute('name', 'viewport');
    head.appendChild(meta);
  }
  var content = meta.getAttribute('content') || '';
  var parts = content.split(',');
  var kept = [];
  for (var i = 0; i < parts.length; i++) {
    var part = parts[i].trim().toLowerCase();
    if (part.indexOf('user-scalable') === 0 || part.indexOf('maximum-scale') === 0 ||
        part.indexOf('minimum-scale') === 0) {
      continue;
    }
    if (part.length > 0) kept.push(parts[i].trim());
  }
  kept.push('user-scalable=yes');
  kept.push('minimum-scale=0.25');
  kept.push('maximum-scale=5');
  meta.setAttribute('content', kept.join(', '));
  return 'ok';
})();
