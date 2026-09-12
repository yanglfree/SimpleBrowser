(function() {
  if (window.__mbPasswordWatcher) return 'watching';
  window.__mbPasswordWatcher = true;
  document.addEventListener('focusin', function(event) {
    var target = event.target;
    if (target && target.tagName === 'INPUT' && (target.type === 'password')) {
      if (window.dolphinSecurity && window.dolphinSecurity.notifyPasswordFocus) {
        window.dolphinSecurity.notifyPasswordFocus();
      }
    }
  }, true);
  return 'armed';
})();
