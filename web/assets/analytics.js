(function () {
  if (!window.ShuYiShu || typeof window.ShuYiShu.createShuYiShuBrowserClient !== 'function') {
    return;
  }

  var host = window.location.hostname || '';
  var isLocal =
    host === 'localhost' ||
    host === '127.0.0.1' ||
    host === '[::1]' ||
    window.location.protocol === 'file:';

  var client = window.ShuYiShu.createShuYiShuBrowserClient({
    baseUrl: 'https://trending.youdroid.top',
    productId: 'product-zhuobrowser',
    appKey: isLocal ? 'dev_zhuobrowser_web' : 'prod_zhuobrowser_web',
    appVersion: '1.0.0',
    buildNumber: 'web',
    consentState: 'granted',
    autoPageViews: true,
    autoLifecycle: true,
    autoWebVitals: true,
    autoErrors: true
  });

  window.zhuoAnalytics = client;

  document.addEventListener('click', function (event) {
    var target = event.target;
    if (!target || typeof target.closest !== 'function') {
      return;
    }

    var dmgLink = target.closest('a[href$=".dmg"]');
    if (dmgLink) {
      client.track('download_click', { platform: 'macos', surface: 'landing' });
      return;
    }

    var storeLink = target.closest('a.store-link');
    if (storeLink) {
      client.track('download_click', { platform: 'harmony', surface: 'landing' });
    }
  });
})();
