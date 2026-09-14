(function() {
  if (window.__mbPasswordWatcher) return 'watching';
  window.__mbPasswordWatcher = true;
  document.addEventListener('focusin', function(event) {
    var target = event.target;
    if (target && target.tagName === 'INPUT' && (target.type === 'password')) {
      if (window.dolphinSecurity && window.dolphinSecurity.notifyPasswordFocus) {
        window.dolphinSecurity.notifyPasswordFocus();
      }
      if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.zhuoSecurity) {
        window.webkit.messageHandlers.zhuoSecurity.postMessage({ type: 'password-focus', url: window.location.href });
      }
    }
  }, true);
  return 'armed';
})();
