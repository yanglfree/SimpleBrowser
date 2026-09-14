# iOS to HarmonyOS parity ledger

HarmonyOS is the product source of truth. This ledger tracks user-visible parity,
not implementation identity. Platform-only delivery mechanics such as HAP
signing, AGC specified-device delivery, and ArkWeb APIs do not require iOS
copies; their user-facing outcomes do.

Cyclar requirement: `BRO-112`.

Status values are `complete`, `partial`, `missing`, and `external-gate`.

| Product area | iOS status | Current boundary |
| --- | --- | --- |
| Core browsing | complete | Native home, tabs, private tabs, live WebView budget, omni bar, custom `%s` search templates with prefix overrides, reader, find, desktop UA, sharing, bookmarks, history, downloads, blocking, site permissions, and classified offline/timeout/DNS/certificate/unknown error recovery exist. Native pull-to-refresh follows the Harmony browsing-only/idle contract and targets the pulled pane in split browsing. Error recovery also targets the failed pane, and certificate failures expose security information without a bypass. |
| Privacy startup | complete | First launch blocks browsing until consent, exposes the public terms/privacy pages, and continues into onboarding. |
| Privacy telemetry | partial | An opt-in, local-only Unified Logging layer records bounded startup/page-load durations, memory warnings, and allow-listed action keys only after consent; every write resolves privacy per tab so multiwindow and private tabs cannot share a global privacy flag. URLs, titles, queries, and article content are never logged. MetricKit crash diagnostics remain excluded because its 24-hour payload cannot prove that pre-opt-in and private periods are absent. |
| Onboarding | complete | Three-step product/privacy/search setup with skip and persisted completion. |
| Start page | partial | Persistent quick-site add/edit/remove/reorder, visibility/count, built-in backgrounds, a private downsampled custom-photo cache, an opt-in Bing daily background, and site-owned favicon discovery now exist. Non-private icons use an ephemeral credential-free request path, a bounded 14-day cache, and shared thumbnails across the start page, tab overview, and iPad sidebar; private tabs neither fetch nor display them. PhotosPicker import, daily refresh/failure, icon fallback/cache, rotation cropping, and relaunch persistence still need Simulator/device acceptance. |
| App appearance | complete | System, light, and dark modes use semantic colors and persist. |
| Settings discovery | complete | The native iOS settings search now indexes every settings group with user-facing labels and semantic Chinese/English keywords, keeps matching controls directly interactive, and presents an explicit empty result instead of forcing manual scrolling. |
| Blocking controls | partial | Global and per-site network/tracker/cosmetic controls, standard/strict cleanup, automatic reader policy, a site panel, and honest WebKit-observable cleanup categories/statistics exist. The Harmony five-source subscription set now updates every three days on unconstrained networks or manually on any network; EasyList and EasyList China are atomic requirements, optional sources fail independently, cached compiled lists survive relaunch, and any download/compile/persist failure preserves the active set. Live WebKit compilation/relaunch/failure acceptance and request-level network counts remain. |
| Navigation/session | partial | Back/forward navigation, history picker, pinned tabs, adjacent close selection, configurable recent-WebView budget, expiry archive/recovery, soft-limit cleanup, non-private session restore, recent-closed recovery, cyclic tab switching, common keyboard commands, group-safe tab reordering, 30-day scroll/reader-position resume, and sanitized non-password form restoration exist. A Harmony-matched recent-tabs dock keeps the active tab first, limits the same-privacy working set to five, and exposes full-overview and same-mode new-tab actions from the tab-launcher long press and page tools. Tab overview menus match Harmony's close, same-privacy close-others, copy-link, pin, split-open, and new-window actions. WebKit context menus retain native suggestions while adding background-open, wide-screen split-open, and privacy-safe read-later actions for HTTP(S) links. Explicit close/pin controls and accessibility actions remain. The persisted Harmony gesture contract covers toolbar swipe-up actions, swipe-down collapse, horizontal adjacent-tab switching, long-press blocking, master/child switches, and default reset. Card swipe, toolbar motion, long-press arbitration, context menus, and drag/drop still need physical-device touch acceptance. |
| Library | complete | Unified bookmark/read-later state, automatic read marking, search and calendar-grouped history, rename/delete, host-level history deletion, 1/7/30-day retention, and bounded Netscape HTML import/export exist. |
| Downloads | complete | WKDownload tasks expose progress, pause/resume, retry/cancel, bounded concurrency, Wi-Fi-only and cellular large-file policy, durable interrupted/missing-file recovery, Quick Look/share/delete actions, and in-app plus opt-in system completion notices. Native resume uses server-provided resume data and safely restarts when the origin cannot resume. |
| Reader and articles | partial | Live reader settings plus offline capture/library, bounded image caching, reading-position restore, full-text search, highlights, notes, tags/topics, archive, and Markdown/HTML export exist. New captures are gated by server-verified Pro entitlement; physical purchase and touch-selection acceptance remain. |
| Site privacy/security | partial | Per-origin camera/microphone/location decisions, HTTPS/HTTP/certificate-error status, insecure-password warning, cookie-on-close, selective global clearing, per-site data clearing, and persistent per-site zoom exist. WKWebView does not expose certificate details for successful TLS connections. |
| Web appearance and UA | complete | One-shot, per-site, and global mobile/desktop UA policy, system/light/dark webpage appearance, per-site dark-mode exclusion, minimum font size, and persistent per-site page zoom are implemented. |
| System integration | partial | Page/download share, bounded 40-screen long-screenshot share with scroll restoration, privacy-bounded page diagnostics, explicit link copy/clipboard visit, safe new-window routing, confirmed third-party protocol handoff, gateway feedback, and a queued Share Extension with Clean/Private/Read-and-Close/Save/Original actions exist. App Group registration plus real host-app/share-sheet and live feedback acceptance remain. iOS correctly defers queued actions until the containing app is opened because Share extensions cannot launch it. |
| Default browser | external-gate | Requires Apple's default-browser entitlement and approval before the system flow can ship. |
| Pro commerce | partial | StoreKit 2 products, transaction updates, explicit restore, subscription management, agreement-gated paywall, short-lived server-entitlement cache, server-authoritative feature gating, and the production iOS gateway catalog are implemented. App Store Connect product setup, notification routing, and Sandbox/TestFlight purchase/renewal/refund acceptance remain. |
| Large-screen workspace | partial | iPad is a supported device family. Live 600/840pt breakpoints preserve compact behavior, add switchable/inline sidebars, scale the tab grid, constrain article surfaces, and provide the Harmony-style inspector. Two same-privacy tabs can now stay live side by side with focus-aware replacement and a draggable 30–70% divider. A tab can move into an independent typed SwiftUI window only after the destination scene accepts its snapshot. iPad rotation, Stage Manager, Split View, multiwindow restoration, keyboard/trackpad, and touch behavior still need Simulator/device acceptance. |

## Delivery order

1. Close start-page, appearance, privacy, and site-control gaps.
2. Close navigation, session, library, and download journeys.
3. Port offline article library and its Pro boundary.
4. Add StoreKit 2 and server-verified entitlement recovery.
5. Finish iPad and multiwindow runtime acceptance, then pursue default-browser entitlement.

Each batch must add focused tests, pass shared-core tests and an iOS build, run
fresh Simulator interaction QA, and land as a task-only commit.
