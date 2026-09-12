(function() {
  var TAG = '__mbTracker';
  var patterns = ["google-analytics","googletagmanager","analytics.","/analytics","hm.baidu.com","cnzz.com","umeng.com","talkingdata","scorecardresearch","quantserve","mixpanel","segment.io","segment.com","amplitude","hotjar","clarity.ms","sentry.io","bugsnag","matomo","piwik","newrelic","track","beacon","telemetry","pixel","collect?","/stat","sensorsdata"];
  var removed = 0;

  var scripts = document.querySelectorAll('script[src],img[src],iframe[src]');
  for (var i = 0; i < scripts.length; i++) {
    var node = scripts[i];
    if (node.hasAttribute(TAG)) continue;
    var src = (node.getAttribute('src') || '').toLowerCase();
    if (!src) continue;
    for (var p = 0; p < patterns.length; p++) {
      if (src.indexOf(patterns[p]) >= 0) {
        node.setAttribute(TAG, '1');
        node.remove();
        removed++;
        break;
      }
    }
  }

  if (!window.__mbBeaconPatched) {
    window.__mbBeaconPatched = true;
    window.__mbBeaconCount = 0;
    if (navigator.sendBeacon) {
      navigator.sendBeacon = function() { window.__mbBeaconCount++; return true; };
    }
  }
  removed += window.__mbBeaconCount || 0;
  window.__mbBeaconCount = 0;

  return JSON.stringify({ trackers: removed });
})();
