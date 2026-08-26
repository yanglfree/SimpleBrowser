# Zhuoyue Browser — Feature Inventory

Baseline reference for what the app currently does, derived from the source tree
(`entry/src/main/ets/`) rather than from intent. Use this to scope new work and to
recognize when a change is extending an existing feature versus adding a new one.
When code and this document disagree, the code is correct — update this file in
the same change that changes behavior.

Organized by user-facing domain; each entry names the primary implementation
location. See `DESIGN.md` for the interaction/visual contract of chrome components
and `README.md` for the V1 scope boundary.

## 1. Tabs & sessions

- Multiple tabs, each with its own `webview.WebviewController`; only a bounded
  number (`liveWebViewLimit` setting) stay mounted at once — the rest render as a
  `HibernatedTab` placeholder and reattach on selection.
  (`Index.ets`, `viewmodels/BrowserViewModel.ets`, `components/TabOverview.ets`)
- Private (无痕) tabs, per-tab: never written to session storage, history, or
  site-block-stats persistence (`BrowserViewModel.recordPageVisit`,
  `BrowserRepository.saveSession`).
- Tab overview grid — two-column on phones, responsive up to 4 columns on wide
  windows (`components/TabOverview.ets`); swipe-to-close, close-all, private/active/
  inactive card variants.
- Recent-tabs dock — long-press the tab counter for a bottom sheet of up to 4
  recent tabs in the same privacy mode, with a compact new-tab tile
  (`components/RecentTabsDock.ets`).
- Desktop tab strip for wide layouts with drag reordering (long-press → adjust
  mode → drag) and a swipe-to-nudge alternate route (`components/DesktopTabStrip.ets`).
- Tab pinning (`toggleTabPinned`); pinned tabs stay ordered ahead of unpinned ones
  and drag reorder is clamped within the pinned/unpinned, private/normal group.
- Address-bar horizontal swipe to switch tabs, with a dot indicator on the address
  capsule (shown only with ≥2 tabs and the gesture enabled).
- Session persistence and restore across launches (`BrowserRepository`,
  `SESSION_KEY`), scoped per window (`setSessionScope`) for multi-window.
- Tab archival/expiry: tabs older than `tabExpiryDays` (1/3/7 days, or Never) are
  archived out of the live session and can be restored (`archiveExpiredTabs` /
  `restoreExpiredTabs`, `TAB_ARCHIVE_KEY`).
- Soft tab-count limit (`tabSoftLimit`) with cleanup-candidate suggestions
  (`softLimitCleanupCandidates`) before hitting the hard `MAX_TAB_COUNT` (100).
- Per-tab state tracked in `BrowserTab`: loading/progress, desktop-UA flag, pinned,
  reader-mode flag, back/forward availability, block tallies, favicon, scroll
  position (both normal and reader), form draft, load-error kind, TLS security
  state + parsed certificate summary.
- Keyboard shortcuts on external keyboards: focus address, new tab, close tab,
  reopen closed tab, next/previous tab, reload, find-in-page
  (`models/BrowserShortcut.ets`).

## 2. Navigation & address bar

- Omni-bar: combined address/search entry, back/forward, stop/reload, share,
  desktop-UA toggle, bookmark toggle — surfaced through an action sheet
  (`components/OmniCapsule.ets`, `components/ActionSheet.ets`).
- Address sheet with live suggestions blending history, bookmarks, and search
  query completion (`BrowserViewModel.getSuggestions`, `components/AddressSheet.ets`).
- Configurable default search engine (Bing, Baidu, Google, DuckDuckGo) plus a
  custom search URL template (`SearchEngine`, `customSearchTemplate`).
- Search-suggestions toggle (`searchSuggestionsEnabled`).
- Native start page at `browser://home` — never handed to ArkWeb; anything
  URL-shaped must special-case `isHomeUrl()` (`components/StartPage.ets`).
- Per-tab back-history sheet component and `goBackBySteps` model exist
  (`components/NavigationHistorySheet.ets`, `WebKernelService.goBackBySteps`,
  `Overlay.NavigationHistory`), but as of this writing `Index.ets`'s
  `openBackHistory()` is never called from any gesture — the sheet is currently
  unreachable in the UI. Confirm before relying on it.
- Link long-press action sheet (open in new tab, copy link, share, etc.)
  (`components/LinkActionSheet.ets`, `WebKernelService.getLongPressTarget`).
- Find-in-page with match count and next/previous (`components/FindSheet.ets`,
  `findCountScript`).
- Auto-hide toolbar on scroll (`autoHideToolbarEnabled`).
- Site zoom, persisted per host (`SiteZoomRatio`, `rememberSiteZoom` in the
  repository's serialized save queue) plus a device-wide minimum font size floor.
- Per-site and default user-agent preference (mobile/desktop/default), with desktop
  UA carrying its own viewport script (`UserAgentService`, `DESKTOP_VIEWPORT_SCRIPT`).
- Load-error states surfaced natively (offline, timeout, DNS, certificate,
  unknown) via `ErrorStatePanel.ets` rather than showing the browser's own error
  page.
- TLS security panel showing connection state and parsed certificate chain
  (`components/SecurityPanel.ets`, `services/CertificateService.ets`).

## 3. Ad blocking & privacy

Two independent systems, deliberately not unified (see `CLAUDE.md`):

- **Native request blocking** — ArkWeb's `AdsBlockManager` fed one concatenated
  rules file compiled from EasyList + EasyList China (bundled rawfiles, required)
  and optional extra subscriptions, refreshed from a jsDelivr mirror (GitHub raw is
  unreachable from the mainland). An in-repo supplement list
  (`resources/rawfile/ads/dolphin-supplement.txt`) is re-applied to any freshly
  fetched list via `! >>> dolphin-supplement` fencing (`services/AdsBlockService.ets`).
- **Visible counters + cosmetic hiding** — an in-house `RuleEngine` (Adblock-Plus-
  style filter parsing: domain options, resource-type options, regex literals,
  `$badfilter`) plus `CosmeticFilterService` for element-hiding selectors, capped
  well below EasyList's ~13.5k generic-hide selectors as a parse-cost safety valve.
- Category tallies: ads, trackers, malicious, pop-ups, cookie banners
  (`BlockStats`), with weekly and cumulative totals and per-site breakdown
  (`components/BlockPanel.ets`).
- Rule strength toggle (Standard/Strict) and a global ads/trackers on-off,
  independent of the strength (`RuleStrength`, `blockAds`, `blockTrackers`).
- Per-site allow-list (`isHostAllowed` / `setHostAllowed` / `getAllowedHosts`) to
  disable blocking on a host without touching the global setting.
- Tracker-script blocking via URL pattern matching, separate from the ad-block
  engine (`TRACKER_URL_PATTERNS`, `TRACKER_BLOCK_SCRIPT`).
- Cosmetic cleanup pass injected after load, idempotent via node tagging so a
  re-run reports 0 changes (`contentCleanupScript`).
- Reader mode: extraction + display with adjustable font size (15-21sp, step 2),
  three line-height presets, and paper theme (white/sepia/night)
  (`readerApplyScript`, `components/ReaderBar.ets`, `TelemetryService.reportReaderExtraction`).
- Site-level JS dark mode with a per-host exclusion list, independent of app
  appearance (`WebDarkModePreference`, `webDarkModeExcludedHosts`,
  `toggleCurrentSiteDarkMode`).
- Cookie/storage/cache clearing: manual "clear browsing data" flows plus an
  optional clear-cookies-on-tab-close setting (`services/PrivacyService.ets`,
  `clearCookiesOnTabClose`). Cookies are force-flushed synchronously before a tab
  closes so a login isn't lost to ArkWeb's ~30s write cadence.
- Site permission control per origin — camera, microphone, location,
  notifications — with prompt/allow/deny per permission
  (`SitePermission`, `components/PermissionSheet.ets`).
- Password-field watcher script for autofill/security signaling
  (`PASSWORD_FIELD_WATCHER_SCRIPT`).
- Opt-in, locally-aggregated telemetry (startup time, page-load time, memory
  pressure, reader success, crash reports, action-usage counts) — fully disable-able
  (`telemetryEnabled`, `services/TelemetryService.ets`).

## 4. Downloads

- Routed through ArkWeb's `WebDownloadManager` to the system download directory
  (`services/DownloadService.ets`).
- Concurrency limit (`downloadConcurrency`), Wi-Fi-only gate, and a
  large-download-size threshold with policy-reason surfacing
  (`resolveDownloadPolicyReason`, `largeDownloadThresholdMb`, `wifiOnlyDownloads`).
- Pause / resume / retry / cancel per task; open or share a completed download
  (`components/DownloadSheet.ets`, `services/ShareService.ets`).

## 5. Bookmarks, history & the start page

- Unified saved-item model covering bookmarks and read-later, distinguished by
  `isRead`, with free-form tags (`SavedItem`, `components/SavedItemEditSheet.ets`).
- Netscape bookmark HTML import/export, no DOM dependency
  (`services/BookmarkTransferService.ets`).
- Browsing history with configurable retention (`historyRetentionDays`), per-entry
  and per-host removal, and full clear (`components/HistorySheet.ets`).
- Start-page quick-site shortcuts: explicit adds first, then saved bookmarks, then
  shipped presets; one tile per host; hiding a host never deletes the underlying
  bookmark/history entry (`components/QuickSiteGrid.ets`, `QuickSiteEditor.ets`,
  `QuickSiteSourceList.ets`). Configurable tile count (4-8, default 6) and an
  overall on/off switch.
- Shortcut icons resolved from the site itself (page-declared `<link rel=icon>`
  metadata preferred over the legacy root favicon, size-gated at 64px, disk-cached
  for two weeks) — no third-party favicon proxy, since those are unreachable from
  the mainland (`services/FaviconService.ets`, `FaviconPolicy.ets`,
  `FaviconMetadataPolicy.ets`).
- Long-press edit mode for shortcuts: wiggle feedback, drag sort, close controls
  (`components/QuickSiteGrid.ets`).
- Configurable start-page background: built-in or a user-picked custom image
  (`services/HomeBackgroundService.ets`, `components/HomeBackgroundPicker.ets`).

## 6. Windows, panes & responsive layout

- Responsive layout classes driven by measured width/height/aspect
  (`models/WindowMetrics.ets`): Compact, Medium (≥600vp), Expanded (≥840vp),
  Desktop (≥1440vp), plus a height-constrained flag (`CONSTRAINED_WINDOW_MAX_HEIGHT`)
  and a wide-aspect flag for split layouts. Wide windows swap the phone dock for
  `DesktopTabStrip` + `BrowserSidebar`; compact keeps `BrowserDock`.
- Two-pane split view on sufficiently wide/short windows (`models/PaneModels.ets`,
  `PaneId`, `PaneLayout`, adjustable split ratio).
- Persistent right-side `BrowserSidebar` (Medium+) covering tabs, favorites,
  history, downloads, and blocking detail, replacing the modal sheets used on
  phones for the same content.
- Multi-window support: `launchType: "specified"` opens a new OS-level window;
  `EntryAbilityStage.onAcceptWant` maps a `dolphin.windowToken` want parameter to
  a window instance, each with its own scoped session; a tab can be moved to a new
  window (`services/MultiWindowService.ets`, `models/WindowLaunchPolicy.ets`).
- Foldable-device awareness: crease metrics (horizontal/vertical) inform layout
  decisions (`services/FoldStateService.ets`, `models/FoldMetrics.ets`).
- Memory-pressure response: shrinks the live-webview budget under OS memory
  pressure (`services/MemoryPressureService.ets`).

## 7. Appearance & settings

- Appearance mode: System / Light / Dark, applied to both app chrome and system
  bars (`services/ThemeService.ets`, `AppearanceMode`).
- Full settings surface backed by one `BrowserSettings` object, persisted via
  `@ohos.data.preferences` through a single serialized save queue so a webview
  event can't clobber a newer user edit (`repositories/BrowserRepository.ets`,
  `components/SettingsPage.ets`). Covers every toggle/limit listed above:
  blocking, search, gestures, quick sites, start-page background, tab expiry,
  history retention, live-webview budget, downloads, tab soft limit, minimum font
  size, per-site zoom/UA, onboarding-completed flag, appearance, web dark mode +
  exclusions, site permissions, cookie-clear-on-close, telemetry, reader
  font/line-height/paper.
- Gesture toggles, independently switchable: gestures overall, gesture actions,
  gesture tab-switch, gesture blocking (`gesturesEnabled` and three sub-flags) —
  every gesture-driven action must retain a non-gesture route per `DESIGN.md`.
- First-run onboarding sheet (`components/OnboardingSheet.ets`,
  `onboardingCompleted`).
- Share sheet for the current page, and image/file sharing for downloads
  (`components/SharePanel.ets`, `services/ShareService.ets`).
- Wide-layout browser menu (`components/WideActionMenu.ets`) vs. compact
  bottom action sheet — same actions, different surface per `DESIGN.md`.

## 8. Platform integration

- App version/build metadata surfaced in Settings → About
  (`services/AppMetadataService.ets`).
- Declared OS permissions: INTERNET, GET_NETWORK_INFO, CAMERA, MICROPHONE,
  LOCATION, READ_WRITE_DOWNLOAD_DIRECTORY (`module.json5`); camera/mic/location
  are additionally gated per-site through the in-app permission model (§3).
- Public marketing site (`website/`) sharing the in-app design tokens, not a
  separate theme — out of scope for app feature work but maintained alongside it.

## Explicitly out of scope (V1)

Per `README.md`: AI page assistance, account sync, extension distribution,
VPN/DNS-level filtering, and a full remote EasyList update *service* (the current
jsDelivr-mirrored fetch is a refresh mechanism, not a signed subscription
service). The bundled rule file is a small, auditable starter set — production
distribution should replace it with a verified subscription and update-signature
policy before shipping at scale.
