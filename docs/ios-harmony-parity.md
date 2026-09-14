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
| Navigation/session | partial | Back/forward navigation, history picker, pinned tabs, adjacent close selection, configurable recent-WebView budget, expiry archive/recovery, soft-limit cleanup, non-private session restore, recent-closed recovery, cyclic tab switching, common keyboard commands, group-safe tab reordering, 30-day scroll/reader-position resume, and sanitized non-password form restoration exist. Card swipe and drag/drop are implemented with accessibility alternatives but still need physical-device touch acceptance. |
| Library | complete | Unified bookmark/read-later state, automatic read marking, search and calendar-grouped history, rename/delete, host-level history deletion, 1/7/30-day retention, and bounded Netscape HTML import/export exist. |
| Downloads | complete | WKDownload tasks expose progress, pause/resume, retry/cancel, bounded concurrency, Wi-Fi-only and cellular large-file policy, durable interrupted/missing-file recovery, Quick Look/share/delete actions, and in-app plus opt-in system completion notices. Native resume uses server-provided resume data and safely restarts when the origin cannot resume. |
| Reader and articles | partial | Live reader settings plus offline capture/library, bounded image caching, reading-position restore, full-text search, highlights, notes, tags/topics, archive, and Markdown/HTML export exist. New captures are gated by server-verified Pro entitlement; physical purchase and touch-selection acceptance remain. |
| Site privacy/security | partial | Per-origin camera/microphone/location decisions exist. Security/certificate panel, insecure-password warning, cookie-on-close, selective clearing, and site zoom remain. |
| Web appearance and UA | partial | One-shot desktop UA exists. Global/site UA policy, web dark mode exclusions, minimum font size, and per-site zoom remain. |
| System integration | partial | Page/download share exists. Screenshot share, external-link routing, clipboard visit/copy, diagnostics, and feedback remain. |
| Default browser | external-gate | Requires Apple's default-browser entitlement and approval before the system flow can ship. |
| Pro commerce | partial | StoreKit 2 products, transaction updates, explicit restore, subscription management, agreement-gated paywall, short-lived server-entitlement cache, server-authoritative feature gating, and the production iOS gateway catalog are implemented. App Store Connect product setup, notification routing, and Sandbox/TestFlight purchase/renewal/refund acceptance remain. |
| Large-screen workspace | missing | iPad adaptive chrome, sidebar, multi-window/split panes, and article workspace remain. |

## Delivery order

1. Close start-page, appearance, privacy, and site-control gaps.
2. Close navigation, session, library, and download journeys.
3. Port offline article library and its Pro boundary.
4. Add StoreKit 2 and server-verified entitlement recovery.
5. Add iPad adaptive workspace, then pursue default-browser entitlement.

Each batch must add focused tests, pass shared-core tests and an iOS build, run
fresh Simulator interaction QA, and land as a task-only commit.
