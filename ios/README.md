# Zhuoyue Browser for iOS

Native SwiftUI + `WKWebView` shell. HarmonyOS remains the product source of
truth in `../ohos`. Shared scripts and contracts live in `../core`.

Phone V1 now includes native home, multi-tab, private tabs with a non-persistent
data store, live-webview hibernation, session restore for non-private tabs,
`WKContentRuleList` compiled from `core/rules`, reader mode, find-in-page, and
a desktop user-agent toggle. First launch now enforces privacy consent and
onboarding; the start page supports persistent quick-site management, built-in
backgrounds, an app-private custom photo, an opt-in cached Bing daily image,
and system/light/dark appearance.
Navigation parity includes forward navigation and back/forward history, pinned
tabs, adjacent close selection, configurable live-WebView retention, expired-tab
recovery, and the HarmonyOS-compatible soft tab limit. The third parity batch
adds recent-closed recovery, cyclic tab switching, common hardware-keyboard
commands, and group-safe tab reordering with explicit accessibility actions.
The fourth parity batch persists normal and reader scroll positions for 30 days,
offers Continue / Start Over recovery, and restores bounded form drafts while
excluding password, hidden, file, one-time-code, and payment fields.
The fifth parity batch completes the bookmark/history surface with unified
read-later state, search and calendar grouping, bookmark editing, site-level
history deletion, retention controls, and bounded Netscape HTML import/export.
The sixth parity batch completes download management with native progress,
pause/resume/retry/cancel actions, concurrency and network policies, durable
interruption and missing-file recovery, Quick Look, and completion notices.
Later parity batches add the offline article workspace, StoreKit 2 entitlement
verification, advanced site controls, confirmed external-protocol handoff,
bounded long-screenshot sharing, page diagnostics, gateway feedback, and an
iOS Share Extension for queued webpage actions. iPad is a supported device
family and uses live 600/840-point breakpoints for an adaptive browser sidebar,
tab grid, bounded reader, and article inspector. Its workspace also supports
same-privacy side-by-side web panes and typed independent windows with
destination-acknowledged tab transfer.

## Setup

```bash
cd ../core && npm run export-js && npm run export-rules
cd ../ios
./Scripts/sync-core.sh
xcodegen generate
xed .
```

From the repo root, `./run_release.sh ios -s` builds the Simulator destination and launches `com.youdroid.zhuobrowser`. Physical devices need a signing team (`DEVELOPMENT_TEAM`).

The app and `ZhuoBrowserShareExtension` targets both require the App Group
`group.com.youdroid.zhuobrowser`. Register it in the Apple Developer portal and
include it in both provisioning profiles before signed-device or archive QA.

Re-run `sync-core.sh` after Harmony script or filter-list changes.

## Scope

In:

- Native start page (never handed to `WKWebView`)
- Tabs, private tabs, live-webview budget (4)
- `WKContentRuleList` from supplement + EasyList China + capped EasyList
- Document-start/end scripts from `core/js`
- Reader mode (shared extraction core), find-in-page, desktop UA

- Settings (search engine, blocking toggle, clear site data)
- Share the current page and download attachments via `WKDownload`
- Share bounded long screenshots and receive webpage links through the Share Extension
- Submit privacy-bounded product feedback through the shared gateway
- Bookmarks, history, and address-bar suggestions (private tabs never record)

- Per-site allow-list that turns off `WKContentRuleList` for that host

- Per-origin camera, microphone, and location decisions (Prompt / Allow / Deny)

- iPad adaptive workspace, side-by-side web panes, and independent windows

The live catch-up ledger is [`../docs/ios-harmony-parity.md`](../docs/ios-harmony-parity.md).

Out until later milestones: the default-browser entitlement.
