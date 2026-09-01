# Zhuoyue Browser

Zhuoyue Browser (卓阅浏览器) is a HarmonyOS NEXT browser built on ArkWeb. It focuses on a clean, private browsing surface rather than a system-wide browser extension.

## Features

- ArkWeb browsing with multiple tabs and an incognito (无痕) per-tab mode.
- Omni-bar for address/search navigation, back/forward, stop/reload, share, desktop user agent, and bookmark toggling — all surfaced in an action sheet.
- ArkWeb `AdsBlockManager` with a bundled EasyList starter rule set, per-site blocking control, category counters (ads, trackers, pop-ups, cookie banners), and weekly blocked totals.
- Cosmetic cleanup, reader mode (with adjustable line height), and JavaScript-based dark mode.
- Downloads routed through ArkWeb's `WebDownloadManager` to the system download directory.
- Settings persisted through Preferences: default search engine, ad/tracker blocking and rule strength, appearance (system/light/dark), privacy options (clear browsing data, clear cookies on tab close), and an about section.
- Bookmark, history, and search suggestions surfaced in the address sheet.

## Build

The project targets HarmonyOS SDK 6.0.0 (API 20) with compatibility for 5.0.3 (API 15).

`build-profile.json5` is not in version control — DevEco writes the signing certificate paths and key passwords of whichever machine opened the project into it. Start from the template:

```bash
cp build-profile.json5.example build-profile.json5
```

Then open the project in DevEco Studio once and let it fill in the signing profile (File → Project Structure → Signing Configs → Automatically generate signature). With Hvigor available on `PATH`:

```bash
hvigorw assembleHap
```

Connect a HarmonyOS device or simulator before installing the HAP for manual UI verification.

## Scope boundary

AI page assistance, sync, extension distribution, VPN/DNS filtering, and a full remote EasyList update service are intentionally outside this V1 implementation. The bundled rule file (`entry/src/main/resources/rawfile/ads/easylist.txt`) is a small, auditable starter set; production distribution should replace it with a verified subscription and an update signature policy.

See [DESIGN.md](DESIGN.md) for the design system that governs the UI.

Mobile build orchestration, signed artifact retention, and the manual store
boundary are documented in [docs/mobile-ci-cd.md](docs/mobile-ci-cd.md).
