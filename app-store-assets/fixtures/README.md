# Store Screenshot Fixtures

These local pages provide neutral placeholder content inside the real browser, as requested for the V2 store image revision. They do not simulate browser controls. Do not publish these fixtures as app content.

- browsing.html: blue-gray placeholder page behind external-link choices.
- reading.html: first reading fixture; the title was moved during capture preparation.
- reader-clean.html: article-only placeholder for real night/sepia reader screenshots.
- blocking.html: placeholder page with eight local `/ads/banners/preview-N.png` requests. The bundled EasyList `/ads/banners/*$image` rule matches these URLs. The app displayed 32 blocked requests and 163 cumulative requests; these are UI counters, not unique-request assertions or benchmarks. Nothing is sent to an ad network.

```bash
python3 -m http.server 18763 --bind 127.0.0.1 --directory app-store-assets/fixtures
hdc rport tcp:18763 tcp:18763
hdc shell aa start -b com.youdroid.zhuobrowser -a EntryAbility -U http://127.0.0.1:18763/browsing.html
```

Use real external-opening and reader controls. Capture into a fresh path on each run because an existing device screenCap path may retain an old image. Preserve original source captures; export compositions separately. Restore reader paper after capture. Remove the task's reverse forwarding and stop its local HTTP server when finished.
