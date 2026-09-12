# Zhuoyue Browser for iOS

Native SwiftUI + `WKWebView` shell. HarmonyOS remains the product source of
truth in `../ohos`. Shared scripts and contracts live in `../core`.

Phone V1 now includes native home, multi-tab, private tabs with a non-persistent
data store, live-webview hibernation, session restore for non-private tabs,
`WKContentRuleList` compiled from `core/rules`, reader mode, find-in-page, and
a desktop user-agent toggle.

## Setup

```bash
cd ../core && npm run export-js && npm run export-rules
cd ../ios
./Scripts/sync-core.sh
xcodegen generate
xed .
```

Re-run `sync-core.sh` after Harmony script or filter-list changes.

## Scope

In:

- Native start page (never handed to `WKWebView`)
- Tabs, private tabs, live-webview budget (4)
- `WKContentRuleList` from supplement + EasyList China + capped EasyList
- Document-start/end scripts from `core/js`
- Reader mode (shared extraction core), find-in-page, desktop UA

Out until later milestones: downloads, IAP, default-browser entitlement,
per-site allow-list UI.
