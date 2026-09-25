# HarmonyOS WebView defect remediation plan

Date: 2026-09-25. Source baseline: `main` (installed AppGallery build 1.0.3 differs
from `main` only by `50eba51`, which does not touch the affected code).
Executor: Antigravity, as requested by the user.
Evidence: on-device run on MatePad Pro (WEB-W00, HarmonyOS 6.1, ArkWeb 6.1.0.120)
against a LAN test page plus cn.bing.com. This document is the audit and the
executable plan; it does not claim any fix is implemented.

Read `CLAUDE.md` (architecture, invariants, testing gotchas) and `DESIGN.md`
(chrome contracts) before editing. All code, comments and commits in English;
user-visible strings go through `$r('app.string.*')` in both `base` and `zh_CN`
string resources as the project already does.

## P0-1 Page-end race drops history, session, and all page enhancement

Evidence: a Bing results page and several `?query` test pages were never written
to history (still missing after force-stop + relaunch); long-press on a Bing
result link never opened `LinkActionSheet`.

Root cause: `Index.handleProgress` (`pages/Index.ets`, ~line 4889) sets
`isLoading: false` as soon as progress reaches 100. When that callback lands
before `onPageEnd`, `Index.handlePageEnd` (~line 4616) sees
`!tab.isLoading && isSameDocumentUrl(tab.url, url)` and returns early as if it
were a same-document navigation. Everything after that return is skipped:
`recordPageVisit`, `persistSession`, `prepareScrollResume`, form-draft restore,
`enhancePage` (force zoom, `LONG_PRESS_TARGET_SCRIPT`, favicon, cosmetic
cleanup, desktop viewport), pending article capture, auto reader, and the
insecure-page password watcher. Which pages hit it depends on subresource timing.

Fix direction:
- Do not infer "same document" from `isLoading`. Track per-tab navigation
  completion explicitly (e.g. a `Map<string, string>` of the document URL whose
  page-end work already ran, set in `handlePageEnd`, cleared in
  `handlePageBegin` for a real new document). `handlePageEnd` must run its full
  completion path exactly once per `onPageBegin` document, regardless of the
  order of progress callbacks.
- Extract the decision into a pure exported helper (e.g. in
  `services/WebKernelService.ets` or a new small policy module) and cover it with
  hypium tests: progress-100-before-page-end, page-end-before-progress,
  hash-only navigation, reload of the same URL, error page commit.
- Record the history title from the latest tab state, and update the history
  entry when `onTitleReceive` arrives after page end (history currently stores
  the host for many pages). Keep private tabs excluded.
- Long-press: `LONG_PRESS_TARGET_SCRIPT` sets its target on a 500 ms JS timer
  while the native `LongPressGesture` also fires at 500 ms and reads it
  immediately. Make the read robust (e.g. shorter JS timer, or resolve the
  element at read time from the last touch point recorded by the script).
  Remember `core/js/` is generated: after editing `AppConstants.ets` run
  `cd core && npm run export-js`, then `ios/Scripts/sync-core.sh`,
  `android/Scripts/sync-core.sh`, `macos/Scripts/sync-core.sh`, and commit the
  regenerated files together.

## P0-2 JavaScript dialogs are silently suppressed

Evidence: `alert()` returned with no UI; `confirm()` returned `false`;
`prompt()` returned `null`. Sites' "confirm delete / submit" flows cannot proceed.

Root cause: `components/BrowserWebView.ets` registers no `onAlert`, `onConfirm`,
`onPrompt`, or `onBeforeUnload`.

Fix direction: implement all four, surfacing events to `Index` through
`WebKernelCallbacks` (the wrapper owns no policy). Show a native dialog titled
with the page host (not the page's own text, to avoid spoofing), and always
resolve the result object (`handleConfirm` / `handleCancel` /
`handlePromptConfirm`) on every path including dismissal and tab close. Only
the active tab may show a dialog; a background tab's dialog is cancelled.
Consider a "block further dialogs from this page" option after repeated
dialogs, as Chrome does.

## P0-3 `window.open` and `target=_blank` replace the current page

Evidence: both navigated the current tab; `window.close()` did nothing. OAuth
and payment popup flows break and the originating page is lost.

Root cause: `.multiWindowAccess(false)` and no `onWindowNew` / `onWindowExit`.

Fix direction: enable `multiWindowAccess(true)`, handle `onWindowNew` by creating
a new tab adjacent to the opener (same `isPrivate` as the opener), attach a new
`WebviewController` via `event.handler.setWebController(...)` so `window.opener`
and `postMessage` keep working, and handle `onWindowExit` by closing that tab.
Respect the live-webview budget (`liveTabIds`, `enforceLiveWebViewLimit`): a
popup tab must stay live while its opener depends on it. Block popups that are
not triggered by a user gesture (`event.isUserTrigger`) and show a small
"popup blocked" affordance, matching mainstream browsers.

## P1-1 Fullscreen video is not fullscreen

Evidence: `requestFullscreen()` resolved, but the tab strip, toolbar, and status
bar stayed visible.

Fix direction: handle `onFullScreenEnter` / `onFullScreenExit`: hide all chrome,
enter immersive window mode (hide system bars), and on phones honour the video
orientation (landscape for wide video); restore everything on exit and when the
app goes to background. The system back gesture must exit fullscreen first
(`exitFullScreen()` on the handler) rather than navigating back.

## P1-2 Certificate error page shows the previous URL and "Retry" reloads it

Evidence: opening `https://expired.badssl.com/` from a loaded page showed the
certificate error view, but the address bar and tab title kept the previous
page; tapping Retry reloaded the previous page.

Root cause: `handleSslError` records no failed URL; `retryPage` calls
`WebKernelService.reload` (~line 5007 of `pages/Index.ets`).

Fix direction: store the failed main-frame URL on the tab (a field on the tab
model, following the model clone/normalize rules in `CLAUDE.md`), show it in the
address bar while `loadError` is set, and make Retry load that URL. Apply the
same to `handleLoadError` for consistency (DNS failures happen to commit the
right URL today, but do not rely on it).

## P1-3 Download notice never auto-dismisses

Evidence: the "download completed" notice stayed over page content for more
than 8 minutes, and also appeared over a private tab.

Fix direction: auto-dismiss completed/failed notices after a few seconds
(keep in-progress ones), dismiss on tab switch, and do not show a normal-tab
download notice over a private tab.

## P2 Security hardening

- `.mixedMode(MixedMode.All)` lets HTTPS pages load HTTP scripts. Change to
  `MixedMode.Compatible`.
- `.fileAccess(true)` gives web content `file://` access. Set to `false` unless a
  concrete feature needs it (check offline article / reader paths first).
- No `onRenderExited`: a renderer crash leaves a blank tab. Show the existing
  `ErrorStatePanel` with a reload action and log the reason.
- No `onHttpAuthRequest`: Basic/Digest-auth sites cannot be opened. Add a
  username/password sheet; never persist credentials for private tabs.

## Verified working (do not regress)

Downloads, system file picker for `<input type=file>`, private-tab storage
isolation and history exclusion, private tabs dropped on relaunch, session
restore, external-protocol confirmation, DNS error view, certificate blocking,
search from the address bar.

## Verification requirements

1. `cd ohos && $HV test --no-daemon` (`HV` per `CLAUDE.md`). Read
   `ohos/entry/.test/default/intermediates/test/coverage_data/test_result.txt`;
   the exit code alone is not a verdict. Register new suites in
   `ohos/entry/src/test/List.test.ets`.
2. `cd ohos && $HV assembleHap --no-daemon` with no new `ArkTS:WARN` lines.
3. If injected JS changed: `cd core && npm test && npm run export-js:check`,
   plus the three `sync-core.sh` scripts.
4. On-device acceptance (`./run_release.sh ohos`, device reachable over wireless
   hdc at `192.168.49.12:38725`; the device holds the user's real tabs, so open
   new tabs for testing and never clear user data): alert/confirm/prompt show
   and return the chosen value; `window.open` and `target=_blank` open a new tab
   with `window.opener` set and `window.close()` closes it; a Bing results page
   appears in history after a force-stop and relaunch; long-press on a Bing link
   opens the link menu; video fullscreen hides all chrome; Retry on a
   certificate error targets the failed URL.

## Antigravity handoff

Implement P0-1 through P2 in that order, one focused commit per item on `main`,
each with its tests. The user requested implementation, not another proposal.
Routine local edits, builds, tests and device installs need no repeated
confirmation. Do not push, amend, rewrite history, touch signing
(`AGENTS.md`), or publish. Report per item what was verified on device versus
only by unit tests, and list anything left unfinished with its blocker.
