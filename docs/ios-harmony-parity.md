# iOS to HarmonyOS parity ledger

HarmonyOS is the product source of truth. This ledger tracks user-visible parity,
not implementation identity. Platform-only delivery mechanics such as HAP
signing, AGC specified-device delivery, and ArkWeb APIs do not require iOS
copies; their user-facing outcomes do.

Cyclar requirement: `BRO-112`.

Status values are `complete`, `partial`, `missing`, and `external-gate`.

| Product area | iOS status | Current boundary |
| --- | --- | --- |
| Core browsing | complete | Native home, tabs, private tabs, live WebView budget, omni bar, reader, find, desktop UA, sharing, bookmarks, history, downloads, blocking, and site permissions exist. |
| Privacy startup | complete | First launch blocks browsing until consent, exposes the public terms/privacy pages, and continues into onboarding. |
| Onboarding | complete | Three-step product/privacy/search setup with skip and persisted completion. |
| Start page | partial | Persistent quick-site add/edit/remove/reorder, visibility/count, and built-in backgrounds exist. Custom photo and Bing daily background remain. |
| App appearance | complete | System, light, and dark modes use semantic colors and persist. |
| Blocking controls | partial | Main toggle and per-host allow-list exist. Rule strength, update status, block-event categories/statistics, and site panel remain. |
| Navigation/session | partial | Back/forward navigation, history picker, pinned tabs, adjacent close selection, configurable recent-WebView budget, seven-day expiry recovery, soft-limit cleanup, and non-private session restore exist. Gesture actions, keyboard shortcuts, scroll/form restoration, tab reordering, and expired-tab management remain. |
| Library | partial | Bookmarks/history and suggestions exist. Rename, host deletion, import/export, retention controls, and read-later state remain. |
| Downloads | partial | WKDownload persistence and sharing exist. Pause/resume/retry/cancel, concurrency, Wi-Fi/large-file policy, missing-file recovery, and completion notice remain. |
| Reader and articles | partial | Live reader settings exist. Offline article capture/library, reading position, images, full-text search, highlights, notes, topics, and export remain. |
| Site privacy/security | partial | Per-origin camera/microphone/location decisions exist. Security/certificate panel, insecure-password warning, cookie-on-close, selective clearing, and site zoom remain. |
| Web appearance and UA | partial | One-shot desktop UA exists. Global/site UA policy, web dark mode exclusions, minimum font size, and per-site zoom remain. |
| System integration | partial | Page/download share exists. Screenshot share, external-link routing, clipboard visit/copy, diagnostics, and feedback remain. |
| Default browser | external-gate | Requires Apple's default-browser entitlement and approval before the system flow can ship. |
| Pro commerce | missing | StoreKit 2 products, restore, entitlement persistence/server verification, and paywall remain. |
| Large-screen workspace | missing | iPad adaptive chrome, sidebar, multi-window/split panes, and article workspace remain. |

## Delivery order

1. Close start-page, appearance, privacy, and site-control gaps.
2. Close navigation, session, library, and download journeys.
3. Port offline article library and its Pro boundary.
4. Add StoreKit 2 and server-verified entitlement recovery.
5. Add iPad adaptive workspace, then pursue default-browser entitlement.

Each batch must add focused tests, pass shared-core tests and an iOS build, run
fresh Simulator interaction QA, and land as a task-only commit.
