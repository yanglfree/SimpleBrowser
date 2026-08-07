# Dolphin Browser

Dolphin Browser (极简浏览器) is a HarmonyOS NEXT browser built on ArkWeb. It focuses on a clean, private browsing surface rather than a system-wide browser extension.

## Features

- ArkWeb browsing with multiple tabs and an incognito (无痕) per-tab mode.
- Omni-bar for address/search navigation, back/forward, stop/reload, share, desktop user agent, and bookmark toggling — all surfaced in an action sheet.
- ArkWeb `AdsBlockManager` with a bundled EasyList starter rule set, per-site blocking control, category counters (ads, trackers, pop-ups, cookie banners), and weekly blocked totals.
- Cosmetic cleanup, reader mode (with adjustable line height), and JavaScript-based dark mode.
- Downloads routed through ArkWeb's `WebDownloadManager` to the system download directory.
- Settings persisted through Preferences: default search engine, ad/tracker blocking and rule strength, appearance (system/light/dark), privacy options (clear browsing data, clear cookies on tab close), and an about section.
- Bookmark, history, and search suggestions surfaced in the address sheet.

## Build

The project targets HarmonyOS SDK 6.0.0 (API 20) with compatibility for 5.0.3 (API 15). With Hvigor available on `PATH`, run:

```bash
hvigorw assembleHap
```

The local build is configured with a debug signing profile (`build-profile.json5`). Connect a HarmonyOS device or simulator before installing the HAP for manual UI verification.

## Agent harness

[`harness/`](harness/) contains a standalone, typed CLI for AI agents to install and launch the app, locate ArkUI controls semantically, drive real-device input, and collect screenshots, layout trees, and JSON run reports. See [`harness/README.md`](harness/README.md) for the protocol and scenario format.

## Scope boundary

AI page assistance, sync, extension distribution, VPN/DNS filtering, and a full remote EasyList update service are intentionally outside this V1 implementation. The bundled rule file (`entry/src/main/resources/rawfile/ads/easylist.txt`) is a small, auditable starter set; production distribution should replace it with a verified subscription and an update signature policy.

See [DESIGN.md](DESIGN.md) for the design system that governs the UI.
