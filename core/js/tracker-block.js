(function() {
  var TAG = '__mbTracker';
  var trackerPatterns = ["google-analytics","googletagmanager","analytics.","/analytics","hm.baidu.com","cnzz.com","umeng.com","talkingdata","scorecardresearch","quantserve","mixpanel","segment.io","segment.com","amplitude","hotjar","clarity.ms","sentry.io","bugsnag","matomo","piwik","newrelic","track","beacon","telemetry","pixel","collect?","/stat","sensorsdata"];
  var maliciousPatterns = ["malware","phishing","phish","trojan","ransom","exploit","cryptominer","coinhive","malvertising"];
  var trackers = 0, malicious = 0;
  var resources = [];

  var scripts = document.querySelectorAll('script[src],img[src],iframe[src]');
  for (var i = 0; i < scripts.length; i++) {
    var node = scripts[i];
    if (node.hasAttribute(TAG)) continue;
    var src = (node.src || node.getAttribute('src') || '').toLowerCase();
    if (!src) continue;
    var matched = false;
    for (var m = 0; m < maliciousPatterns.length; m++) {
      if (src.indexOf(maliciousPatterns[m]) >= 0) {
        node.setAttribute(TAG, '1');
        node.remove();
        malicious++;
        if (resources.length < 50) resources.push({ url: src, category: 'malicious' });
        matched = true;
        break;
      }
    }
    if (matched) continue;
    for (var p = 0; p < trackerPatterns.length; p++) {
      if (src.indexOf(trackerPatterns[p]) < 0) continue;
      node.setAttribute(TAG, '1');
      node.remove();
      trackers++;
      if (resources.length < 50) resources.push({ url: src, category: 'tracker' });
      break;
    }
  }

  if (!window.__mbBeaconPatched) {
    window.__mbBeaconPatched = true;
    window.__mbBeaconCount = 0;
    if (navigator.sendBeacon) {
      navigator.sendBeacon = function() { window.__mbBeaconCount++; return true; };
    }
  }
  trackers += window.__mbBeaconCount || 0;
  window.__mbBeaconCount = 0;

  return JSON.stringify({ trackers: trackers, malicious: malicious, resources: resources });
})();
