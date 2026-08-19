# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Dolphin Browser (极简浏览器) — a HarmonyOS NEXT browser built on ArkWeb. ArkTS/ArkUI, stage model,
one module (`entry`), bundle `com.youdroid.dolphin`. Targets SDK 6.0.0 (API 20), compatible 5.0.3 (API 15).
UI copy is Chinese (via resource tokens); code, comments and commit messages are English.

`README.md` states the feature scope and the V1 exclusions. `DESIGN.md` is the binding design system
(color/spacing tokens, component contracts, "a gesture is never the only route to a task") — read it
before touching chrome, and update it when a component's contract changes.

## Commands

`hvigorw` is **not** vendored in the repo; use DevEco's copy (what `run_release.sh` resolves to):

```bash
HV=/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw

$HV test --no-daemon                       # unit tests (host-side, no device needed)
$HV assembleHap --no-daemon                # debug HAP
$HV clean --no-daemon                      # if the daemon serves stale build state
./run_release.sh                           # release build + sign + hdc install + launch
./run_release.sh -d <device-id>            # pick a device (else it prompts)
```

`hdc` lives at `/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc`.
For on-device checks: `hdc list targets`, `hdc shell hilog | grep <TAG>`, `hdc shell uitest dumpLayout`,
`hdc shell uinput` for synthetic taps, `hdc shell snapshot_display`.

### Testing gotchas

- **`hvigorw test` prints `BUILD SUCCESSFUL` and exits 0 even when assertions fail.** The only
  trustworthy verdict is the generated report:
  `entry/.test/default/intermediates/test/coverage_data/test_result.txt` — check the
  `Tests run: N, Failure: 0, Error: 0` summary line. Failing assertions do show up as red `ERROR:` lines
  in stdout, so grep for those too. A compile error, by contrast, fails the build with exit 255.
- Every suite must be registered in `entry/src/test/List.test.ets` or it silently never runs.
  There is no test-name filter — to run one suite, temporarily comment out the others there.
- Tests are host-side hypium (`@ohos/hypium`) and cannot touch ArkUI `@Component`s, ArkWeb, or
  `preferences`. Testable logic therefore lives in `viewmodels/`, `models/`, and pure exported helpers
  in `services/` (e.g. `resolveDownloadPolicyReason`, `createWindowMetrics`, `RuleEngine`) — when a
  behaviour needs a test, extract the decision into such a function rather than testing the page.
- Known pre-existing failure on `main`: `BrowserInteraction.test.ets:29` (collapsed pill height,
  expects 32, gets 34) — stale after the recent dock work, unrelated to whatever you are changing.

## Architecture

Four layers, strictly one-directional:

1. **`pages/Index.ets`** — the single `@Entry` page (~3.7k lines) and the only orchestrator. It owns all
   `@State`, the `Overlay` enum (one sheet at a time), the per-tab `webview.WebviewController` map, and all
   *policy*: which script to inject after a load, how blocked requests are bucketed, when a tab hibernates.
   New chrome goes into `components/` as a dumb `@Component`; the decisions stay in `Index`.
2. **`viewmodels/BrowserViewModel.ets`** — tab lifecycle, session restore/expiry, suggestions, quick sites,
   blocking tallies, settings mutation. No UI types, no ArkWeb. This is where new browser logic belongs.
3. **`repositories/BrowserRepository.ets`** — the only persistence. `@ohos.data.preferences` store
   `minimal_browser_store`, one JSON blob per key. All writes funnel through a serialized `saveQueue`
   (`save()` / `rememberSiteZoom()`) so a webview event can't clobber a newer user edit; keep that property.
4. **`services/`** — mostly stateless statics wrapping a system kit (`WebKernelService` for every ArkWeb
   controller call, `ThemeService`, `PrivacyService`, `ShareService`, `DownloadService`, `TelemetryService`,
   `MultiWindowService`). `AdsBlockService` is the exception and holds static compiled-rule state.

Supporting: `models/` (interfaces + `clone*`/`default*`/`normalize*` helpers — ArkTS has no structural
spread, so every model needs an explicit clone), `constants/AppConstants.ets` (limits **and** all injected
JavaScript), `utils/` (`Logger` over hilog, `UrlUtils`, `AppContext`).

### Invariants worth knowing before editing

- **`HOME_URL` is `browser://home`** and is never handed to ArkWeb — the start page is native
  (`StartPage.ets`). Anything URL-shaped must special-case `isHomeUrl()`.
- **Private tabs never persist**: `saveSession` filters them out, and history/site-stats writes are skipped
  for `isPrivate` tabs. Preserve this when adding any new recorded signal.
- **Adding a settings field takes four edits**: the `BrowserSettings` interface, `defaultBrowserSettings`,
  `cloneSettings`/`normalizeBrowserSettings` (all in `models/BrowserModels.ets`), and
  `BrowserRepository.decodeSettings`, which decodes field-by-field for forward/backward compatibility.
  Miss the decoder and the setting silently resets on every launch.
- **Multi-window**: `launchType: "specified"` + `EntryAbilityStage.onAcceptWant` maps a
  `dolphin.windowToken` want parameter to a window instance; `AppContext` keys ability contexts by that
  token, and each window scopes its persisted session via `setSessionScope`. Moving a tab to a new window
  passes the serialized tab in `dolphin.tabTransfer` (`MultiWindowService.moveTab`).
- **Live-webview budget**: only `liveTabIds` tabs keep a mounted `Web`; the rest render the `HibernatedTab`
  placeholder. `MemoryPressureService` shrinks that budget under pressure. Never assume a tab has a controller.
- **Ad blocking is two systems.** ArkWeb's native `AdsBlockManager` does the actual request blocking from one
  concatenated rules file on disk; the in-house `RuleEngine` + `CosmeticFilterService` exist for the visible
  counters and element hiding. `RULE_SOURCES` marks EasyList/EasyList China `required` (bundled as rawfiles,
  a failed fetch aborts the refresh) and the rest optional (a skipped source must not cost the other
  updates). Mainland reachability is a real constraint — GitHub raw is unreachable, hence the jsDelivr
  mirror. Our own rules live in `resources/rawfile/ads/dolphin-supplement.txt`, fenced by
  `! >>> dolphin-supplement` markers so they can be re-applied to a list fetched from anywhere.
- **Injected JS** lives in `AppConstants.ets` as strings/builders, must be idempotent (the cleanup pass tags
  nodes so a re-run reports 0), and returns JSON that `Index` parses into a typed interface.
- **Responsive layout** is driven by `models/WindowMetrics.ets` (`Compact`/`Medium`/`Expanded`/`Desktop` by
  width, plus a height-constrained flag). Wide windows swap the dock for `DesktopTabStrip` + `BrowserSidebar`
  and can split into two panes (`models/PaneModels.ets`); compact keeps `BrowserDock`. Changing a breakpoint
  means updating `WindowMetrics.test.ets` / `WideWindowRegression.test.ets`.

## Conventions

- ArkTS strict mode: explicit type annotations on every declaration, parameter, and callback (including
  arrow params and `.map`/`.filter` lambdas); no `any`, no object spread, no structural typing shortcuts.
  The compiler enforces most of this — treat new `ArkTS:WARN` lines you introduce as errors, but leave the
  pre-existing ones (`vp2px` deprecation, `AdsBlockService` throwable APIs, `getUserDownloadDir` capability).
- Colors and user-visible strings come from resource tokens — `$r('app.color.*')` (defined in
  `resources/base/element/color.json` + `resources/dark/element/color.json`) and `$r('app.string.*')`.
  Never inline a hex color or a Chinese literal in a component.
- Log through `Logger` with a file-level `const TAG`, never `console`.
- Give interactive chrome a stable `.id('kebab-case')` so `uitest dumpLayout` automation can find it.
- Comments explain *why* a constraint exists (device reachability, a race, a memory budget), not what the
  line does. Match that register.
- `@Builder` value parameters bind once and do not refresh — pass the `$$` object form when a builder must
  react to state, and watch `ForEach` key reuse.
- UI changes are verified on a physical device (`./run_release.sh`), not just by tests; fix chrome problems
  the way Safari/Chrome already solve them rather than inventing a new interaction.
