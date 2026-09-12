# Multi-platform architecture

Zhuoyue Browser is a HarmonyOS NEXT product on ArkWeb. iOS and Android are
native shells that share scripts, rules, and contracts through `core/`.
Harmony is not rewritten in Flutter.

See `core/README.md` for the portable package and `core/spec/kernel.md` for
the kernel method table.

## Decision

- Keep the shipping ArkTS client as the product source of truth.
- Implement iOS with SwiftUI + `WKWebView`.
- Implement Android with Jetpack Compose + system `WebView`.
- Share injected JavaScript, EasyList compilation, design tokens, and model
  JSON keys. Do not share UI widgets.

Flutter-OH remains the right stack for other youdroid apps. It is the wrong
stack for a browser kernel: `AdsBlockManager`, live-webview hibernation,
multi-window, and downloads do not survive a PlatformView rewrite.

## Phone V1 vs later

The living matrix is `core/spec/phone-v1.json`. FEATURES.md labels the same
buckets in prose. Harmony-only items (AdsBlockManager, specified windows,
AGC IAP, HAP signing) stay in this repository's existing pipelines.

## Sync rule

`ohos/entry/src/main/ets/constants/AppConstants.ets` owns injected scripts.
`cd core && npm run export-js:check` fails CI if `core/js/` drifts.
Change the ArkTS constants, then regenerate the snapshot.

Layout: `ohos/` Harmony client, `ios/` SwiftUI shell, `android/` Compose +
WebView shell, `web/` marketing site. Sync iOS scripts and compiled content rules with
`ios/Scripts/sync-core.sh`. iOS Phone V1 now compiles `core/rules` into
`WKContentRuleList`, keeps private tabs on a non-persistent data store, and
hibernates webviews beyond the live-tab budget. Reader mode, find-in-page, and
desktop UA are available from the address-bar action menu. Settings, sharing,
and `WKDownload` attachments are in this shell as well. Bookmarks, history, and
omni suggestions follow the shared `core` library policy; private tabs never
write those records. Per-site allow-list uses exact `rawHost` matching, same as
Harmony: blocking is skipped for listed hosts and restored when the host is
removed. Camera, microphone, and location use an in-app confirmation first,
then the system permission prompt; private tabs do not persist those decisions.

Sync Android scripts and compact `{host,path}` network rules with
`android/Scripts/sync-core.sh` (not Safari JSON). The Compose shell now has
native home, tabs, private tabs, background `shouldInterceptRequest` blocking,
per-site allow-list, bookmarks, history, omni suggestions from the shared
`core` library policy, and `Intent.ACTION_SEND` sharing. Private tabs never
write those records. Reader mode, find-in-page, and desktop UA are available
from the address-bar action menu. Attachment downloads use `DownloadListener`
and app-private storage with `FileProvider` sharing. Camera, microphone, and
location use an in-app confirmation first, then the system permission prompt;
private tabs do not persist those decisions.
