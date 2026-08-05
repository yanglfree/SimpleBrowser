# Clear Browser

Clear Browser is a HarmonyOS NEXT browser built on ArkWeb. Its first release focuses on a clean, private browsing surface rather than a system-wide browser extension.

## V1 capabilities

- ArkWeb browsing with multiple tabs.
- Address/search navigation, back/forward, reload, desktop user agent, and incognito tabs.
- ArkWeb `AdsBlockManager` with a bundled EasyList-compatible starter subscription and blocked-request counters.
- Cosmetic cleanup, reader mode, and JavaScript-based dark mode.
- Persistent bookmarks, history, and browser settings through Preferences.
- Bookmarks, history, and ad-blocking settings surfaced in the browser UI.

## Build

The project targets HarmonyOS SDK 5.0.3 (API 15) and a HarmonyOS 6 target. With Hvigor available on `PATH`, run:

```bash
hvigorw assembleHap
```

The local build produces an unsigned HAP when no signing configuration is supplied. Connect a HarmonyOS device or simulator before installing the HAP for manual UI verification.

## Scope boundary

AI page assistance, sync, extension distribution, VPN/DNS filtering, and a full remote EasyList update service are intentionally outside this V1 implementation. The bundled rule file is a small, auditable starter set; production distribution should replace it with a verified subscription and an update signature policy.
