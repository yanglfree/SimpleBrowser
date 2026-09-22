# iOS / HarmonyOS gap audit and implementation plan

Date: 2026-09-22. Source baseline: `main` at `50eba51`.
Requirement: Cyclar `BRO-112` (`d6fb93a4-b026-48ca-9c89-32cee24810e4`).
Executor: Antigravity, as requested by the user.
Initial working tree: clean. This document is a source audit and executable plan,
not fresh runtime, device, purchase, or release acceptance.

## Assessment

iOS is already a substantial SwiftUI/WKWebView implementation. It includes home
customization, tabs, privacy, downloads, blocking subscriptions, offline articles,
StoreKit, a Share Extension, iPad split panes, and independent windows. Rebuilding
these modules wholesale would discard existing work. The material gaps are
incomplete user journeys, recent Harmony behavior that has not been ported, and
missing runtime acceptance. The old ledger's `complete` label does not establish
equivalence with the current Harmony source.

Options considered:

1. Rewrite the iOS shell: broad churn, unnecessary regression and data risk.
2. Patch visible menus only: fast, but leaves offline-library reliability gaps.
3. Incrementally close verified behavior and reliability gaps, then exercise the
   full journeys: selected. Preserve native iOS interaction conventions and reuse
   shared extraction contracts. Do not copy ArkWeb internals.

## Confirmed implementation gaps

All paths below are relative to this repository. Findings are based on executable
paths and their callers, not file-name comparison alone.

| ID / priority | Harmony reference | iOS evidence and missing outcome | Required acceptance |
| --- | --- | --- | --- |
| G01 / P1 | `ohos/entry/src/main/ets/components/BrowserDock.ets`, `AddressMenu` | `ios/ZhuoBrowser/RootView.swift`, `addressBar`, and `OmniboxTextField.swift` provide editing but no equivalent non-editing long-press menu for visit clipboard / copy link / close current tab. Close exists elsewhere, so this is an entry-point gap. | Non-editing long press exposes all three actions; editing retains native text selection; close selects the proper remaining tab; home/private/last-tab cases pass; clipboard read only follows an explicit user action. |
| G02 / P1 | `BrowserViewModel.ets`, `neighbourTabId` / `canCreateTabOnSwipe`; `pages/Index.ets`, `switchNeighbour` / `createTabOnSwipe` | `BrowserGesturePolicy.swift` rejects one-tab swipes; `SessionPolicy.adjacentTabID` wraps modulo the full list; `RootView.toolbarSwipeGesture` acts only on end. Missing final-tab forward swipe to create a same-privacy home tab, bounded backward behavior, and gesture progress feedback. | First-tab backward swipe stays put; final-tab forward swipe creates exactly one tab, including a one-tab session; same privacy and soft limit retained; short/cancelled/vertical/editing/disabled gestures do not create tabs. Treat keyboard cycling separately so its intended behavior is not accidentally changed. |
| G03 / P1 | `services/ExternalProtocolService.ets`, `resolveTargetAppName`; `Index.ets`, protocol prompt | `ExternalProtocolRequest` has no friendly name; `RootView` uses `request.category.promptTitle`. Store-opening schemes can show an installation-service title. | Known schemes show a safe static app name, including appropriate iOS App Store routes; unknown names fall back; blocked schemes stay blocked; source host remains visible; cancellation never launches. No untrusted URL-provided app label. |
| G04 / P1 | `components/ArticleLibrarySheet.ets`, URL input / `onImport` | iOS library has search and archive toggle only; captures originate from an already open page or inbound share. | Paste URL into library, explicitly import, load/capture, then reach saved article. Invalid/non-HTTP(S), private context, duplicate and non-Pro inputs receive explicit outcomes without side effects. No automatic clipboard scraping. |
| G05 / P1 | `ArticleLibrarySheet.ets`, status, source and retry routes; `services/ArticleCaptureService.ets` | `BrowserSession.captureArticle` flashes errors without a durable failed item; `ArticleCapture.capture` performs one script evaluation without a bounded capture coordinator; `.failed` exists in the model but `ArticleStore.save` only creates complete/partial rows. Missing actionable saving/failure/retry lifecycle and direct source recovery. | Failed load, stalled extraction, changed page and disk failure settle into honest actionable states; retry/open source work; relaunch preserves failures; retries are Pro-gated, old articles remain readable without Pro; concurrent captures and tab closure cannot hang or report wrong-page success. |
| G06 / P1 | `ArticleLibrarySheet.ets`, `refreshFilter` and filter controls | `ArticlePolicy.filtered(...archived: Bool)` and library UI only choose active versus archived plus free-text search. Missing all/active/archived/failed states and structured tag/topic combinations. | Combined status + tag + topic + text filters return correct items, empty states and reset behavior; changes persist only where intentional; accessible compact and iPad layouts. |
| G07 / P1 | `services/ArticleReaderScripts.ets`, `ArticleHighlightLocator.ets`, `ArticleAnnotationPanel.ets` | `OfflineArticleReader.applyHighlights` matches quote inside one text node, ignores stored context, and marks the first occurrence; the inspector displays plain text without locate action. `ArticlePolicy.relocatedRange` is not wired into DOM rendering. | Highlight text across inline nodes; use quote + context to disambiguate; tapping an annotation locates it; deletion removes marks; missing/ambiguous anchors report relocation instead of highlighting unrelated text. Do not claim perfect repeated-quote anchoring beyond proven behavior. |
| G08 / P1 | `components/ArticleAnnotationPanel.ets`, note add/edit/delete | `ArticleEditorSheet` edits `notes.first`; `ArticleStore.updateMetadata` clears every note when that field is emptied. The array supports more notes but UI has no independent CRUD. | Add two notes, edit/delete one without altering another; preserve existing IDs/timestamps and old data; retain metadata and highlight operations. |
| G09 / P0 | `repositories/ArticleLibraryRepository.ets`; `docs/article-library-remediation.md`, immutable content + metadata transaction | `ArticleStore.replaceDirectory` removes the backup before `upsert`; `persist` swallows write errors; `restore` silently drops records whose HTML is missing. Actor isolation alone does not prevent save/delete interleaving across image-download awaits. Missing reliable content/manifest commit and recovery. | Inject content/manifest failures and save/delete races; old readable data and metadata survive; no success on failed persistence; incomplete records remain recoverable; relaunch after each commit boundary is deterministic. Avoid destructive schema migration or deleting existing content. |
| G10 / P1 | `services/ArticleImageStore.ets`; remediation document image budgets | `ArticleStore` defaults to `URLSession.shared`; downloads full `Data` before checking byte limits and has no overall scheduling deadline. Count/byte constants exist but do not bound received bytes or waiting adequately. | Credential-free ephemeral fetching, bounded request/deadline and incremental byte enforcement; oversized, slow, redirecting and missing images produce partial results while text survives; cancellation cleans only task-owned staging data. |

## Existing functionality requiring acceptance, not duplicate implementation

| Area | Existing iOS source | Remaining evidence to collect |
| --- | --- | --- |
| Home / setup / settings | `NativeHomeView`, `HomeBackgroundService`, `QuickSiteManagerView`, `SetupFlowView`, `SettingsSheet` | Consent gating, PhotosPicker, daily-image failure/cache, shortcut drag/drop, rotation and relaunch. |
| Session / history / bookmarks | `BrowserSession`, `PageStatePolicy`, `LibrarySheet`, `BookmarkTransfer` | Private-data exclusion, memory hibernation, cold restore, form exclusion, recent-close and import/export on a real runtime. |
| Downloads | `DownloadStore`, `DownloadSheet` | Local HTTP fixture: pause/resume, origin without resume, interrupted relaunch, missing file, concurrency, network policy, preview/share. |
| Content blocking / site controls | `RemoteRuleStore`, `ContentBlocker`, `SiteControlSheet`, `BlockPanelSheet` | Compile/adopt/cache/relaunch, optional-source and required-source failure, per-site overrides and honest observable statistics. |
| Reader / offline content | `ReaderBar`, `ArticleCapture`, `ArticleStore`, `OfflineArticleReader` | Cold offline reopen with images, scroll restore, selection, export receiver, all G04–G10 cases. |
| Permissions / security | `PermissionSheet`, `SiteSecuritySheet`, `SitePermissionPolicy` | Populate actual permission records, independently change/remove them, verify clear-site scope and TLS failure without bypass. Certificate-detail feasibility is a separate API investigation; do not repeat the old ledger's blanket API claim without checking. |
| Share / diagnostics / feedback | `Shared/InboundShareRequest.swift`, Share Extension, `LongScreenshotService`, `FeedbackService` | All five inbound actions, entitlement denial, deferred host processing, queue idempotence, screenshot bounds and receiving app. Feedback live submission only with explicit authorization for its content. |
| iPad workspace | `AdaptiveWorkspacePolicy`, `BrowserPaneState`, `BrowserWindowRequest`, `DesktopTabStrip` | Compact/600/840/1440 widths, split focus, divider, rotations, independent window transfer/restore, keyboard and trackpad. |
| Pro commerce | `ProBillingService`, `IapEntitlementAPI`, `ProPaywallView` | Local StoreKit fixtures plus separately tracked Sandbox/TestFlight purchase, restore, renewal and refund; server authorization remains authoritative. |

The above is a module-level source audit, not an exhaustive visual comparison.
Batch A must inspect both running apps and add newly reproduced gaps to BRO-112
and the ledger before implementation. Record the installed build/source identity:
an older iOS build may explain additional perceived gaps but this is not yet proven.

## Platform and external gates

- Default-browser entitlement/eligibility and system settings entry are an external
  gate; verify current Apple requirements before implementation. Do not simulate
  approval or silently enable an unavailable entitlement.
- Share Extension App Group registration and device profiles need independent
  signed-device validation. A simulator result does not prove provisioning.
- Share extensions queue work until the containing app opens; do not rely on
  unsupported host-app launch tricks for apparent Harmony parity.
- Native request-level blocker counters differ from observable DOM cleanup.
  Preserve honest labels; do not invent network events to match Harmony totals.
- MetricKit/telemetry parity must preserve consent and private-session boundaries;
  do not enable broader collection just to fill a capability checklist.
- Harmony HAP/AGC, ArkWeb-specific kernel behavior, fold state, and platform billing
  APIs are not iOS implementation requirements. User-visible equivalents are.
- No production deployment, push, purchase, store metadata mutation or submission
  is included in this execution plan.

## Implementation batches

### A — Baseline and executable regression fixtures

Read repository instructions and this plan. Recheck `git status` and HEAD; other
agents may have landed unrelated changes. Reproduce the current iPhone/iPad paths
and record screenshots, OS/device/build identity and failures. Run the existing
core and iOS checks once to separate baseline failures. Update ledger rows that
currently overstate behavior. Use local fixtures for failure and network tests.

### B — Article reliability foundation (G09, G10)

Own `ArticleStore.swift` and focused storage/image tests. Introduce a small
transaction/coordinator boundary that serializes conflicting save/delete changes,
propagates persistence errors, and retains the previous content until the new
manifest commits. Preserve the existing decoded model and content paths; any new
optional fields need backward-compatible defaults. Keep recoverable state on
missing files. Add bounded image transport without touching browser credentials.
No schema redesign, destructive migration or generic storage framework is needed.

### C — Navigation and protocol parity (G01–G03)

Own `RootView`, `OmniboxTextField`, gesture/session policies and external protocol
policy plus their focused tests. Separate swipe navigation semantics from keyboard
cycling. Reuse close-tab and soft-limit logic. Add an accessible non-editing menu
without breaking UIKit editing. Add friendly-name policy and request-level title.
Verify compact phone layout, gesture conflicts, private tabs and unknown schemes.

### D — Complete article capture and discovery (G04–G06)

Build a feature-scoped capture coordinator around `BrowserSession`, `ArticleCapture`
and the storage boundary from B. Add explicit loading/capturing/partial/failed
outcomes, bounded completion, cancellation, import/source/retry routes, and library
filters. Reuse shared capture JS; preserve private and server-verified Pro gates.
Use additive fields or a compatible sidecar for failure metadata. Existing
readable articles must never be replaced by a failed retry.

### E — Annotation workflows (G07, G08)

Own `OfflineArticleReader`, annotation models/store operations and library detail
views. Use real DOM ranges across text nodes, bounded context matching and stable
annotation IDs. Add locate and explicit relocation state. Provide independent
note CRUD. Preserve the CSP and offline network prohibition. Extract a small
annotation component if needed rather than enlarging the root browser controller.

### F — Full journeys and final reconciliation

Exercise every existing-functionality row above and all new behavior on an iPhone
and iPad simulator. Fix reproduced defects, then update the ledger with separate
implementation / unit-test / runtime / physical-device / external-gate states.
Provide a final report with issue status, commits, actual test outcomes, screenshots
and explicit remaining gates. Do not mark BRO-112 done while required acceptance
is still open; external gates may be separately tracked without blocking local work.

## Verification and delivery contract

Run actual commands and record exit status, not suggested commands as evidence:

```bash
git status --short
cd core
npm test
npm run export-js:check
npm run export-rules:check
cd ../ios
xcodegen generate --spec project.yml
xcodebuild -list -project ZhuoBrowser.xcodeproj
xcrun simctl list devices available
```

Use the discovered scheme and simulator UDID for `xcodebuild test` and simulator
builds. If generated shared resources are stale, use the repository sync scripts
and review their diff; never copy/edit generated mirrors independently. Run
focused tests each batch and a complete relevant suite after integration. Inspect
result bundles and logs. UI screenshots and concrete interactions are required;
policy unit tests do not prove a working menu, selection or window transfer.

For each batch: inspect diff, run proportionate checks, stage only task-owned
files, commit on `main` with a concise English message, do not push/amend/rewrite.
Preserve concurrent work. Update BRO-112 using its latest version. Keep progress
in `docs/ios-harmony-parity.md` and a task-specific evidence report. Stop only for
a concrete external blocker; continue all independent authorized local work.

## Antigravity handoff

Implement batches A–F, starting with the current baseline and storage foundation.
The user has requested implementation, not another proposal-only response. The
scope above is authorized; routine local changes and verification need no repeated
confirmation. High-risk destructive migration, external publication, payments or
new credential access remain outside scope. Report actual completion separately
from work started. This plan itself does not claim any implementation completed.
