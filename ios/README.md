# Zhuoyue Browser for iOS

Native SwiftUI + `WKWebView` shell. HarmonyOS remains the product source of
truth in `../ohos`. Shared scripts and contracts live in `../core`.

This is the Phone V1 starting point: one tab, native `browser://home`, address
bar, and document-start scripts. Content blockers, private tabs, and session
restore are not in this scaffold.

## Setup

```bash
./Scripts/sync-core.sh
xcodegen generate
xed .
```

`sync-core.sh` copies `../core/js` into the app bundle. Re-run it after
Harmony script changes.

## Scope

In:

- Native start page (never handed to `WKWebView`)
- HTTPS navigation through `WKWebView`
- Document-start guards from `core/js`

Out until later milestones: `WKContentRuleList`, tab hibernation, downloads,
reader chrome, IAP, default-browser entitlement.
