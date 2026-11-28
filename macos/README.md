# Zhuo浏览器 for Mac

Native macOS SwiftUI + WebKit (`WKWebView`) shell engineered for **extreme memory frugality** and **distraction-free simplicity**.

## Core Philosophy

1. **Ultra-Low Memory Footprint (极致省内存)**:
   - Built on native macOS `WebKit.framework`. Libraries are shared via the system `dyld` cache; zero Chromium or Electron runtime bloat.
   - **Zero-JS Content Blocking**: Compiles EasyList starter rules into native `WKContentRuleList` binary bytecode directly evaluated inside WebKit's network process in C++, incurring zero JS runtime overhead.
2. **Instant Tab Switching (标签页状态持久化) — resident by default**:
   - **Every open tab keeps its own live `WKWebView` for the whole session.** Switching tabs re-parents an already-rendered view: no navigation, no network, scroll offset, DOM, form input and back/forward history intact. This is treated as baseline functionality, not an optimisation.
   - Memory cost of that guarantee is roughly 80–250 MB per open tab (one WebContent process each). The toolbar badge (`切换复用 / 页面重建`) makes the contract observable: a healthy session reports zero rebuilds.
   - **Memory-saver mode is opt-in and off by default** (偏好设置 → 标签切换与内存). Turning it on restores the previous behaviour: background tabs beyond a 1–8 live quota are frozen into a `TabStateSnapshot` built from `WKWebView.interactionState`, and wake from that archive (restoring scroll/DOM where possible, but the page is rebuilt).
   - A **critical** macOS memory-pressure signal is the only automatic exception: least-recently-used background tabs may be frozen as an emergency valve. Warning-level pressure does nothing. The visible tab is never frozen.
   - **Graceful staleness handling** (frozen tabs only): snapshots older than 15 minutes are flagged with `clock.arrow.circlepath`; older than an hour they are restored and then refreshed transparently. A restore that produces no document silently falls back to a normal load.
   - Snapshots and the open-tab list are persisted under Application Support (bounded to 16 snapshots / 4 MB each, LRU-evicted) so `启动时恢复上次的标签页` reopens the previous session. Private tabs are never persisted.
3. **Minimalist Aesthetic & Parity (极致简洁与完整功能)**:
   - Unified compact macOS toolbar: Navigation, Omnibox, Star Bookmark toggle, Ad Shield, Memory Saver indicator, Bookmarks/History library button, and New Tab button.
   - Clean horizontal tab bar with visual frozen (`moon.zzz.fill`) and possibly-stale (`clock.arrow.circlepath`) badges.
   - Integrated Library Manager: Full Bookmarks and Browsing History management with search, inline editing, opening in new tab, and date grouping.
   - Native macOS keyboard shortcuts:
     - `Cmd+T`: New tab
     - `Cmd+W`: Close active tab
     - `Cmd+R`: Reload
     - `Cmd+L`: Focus address bar
     - `Cmd+[` / `Cmd+]`: Back / Forward
     - `Cmd+D`: Toggle bookmark for active page
     - `Cmd+Y`: Open browsing history
     - `Cmd+Option+B`: Open bookmarks manager
     - `Cmd+1` ... `Cmd+9`: Quick tab switching

## Directory Layout

```
macos/
  project.yml                    # XcodeGen project specification
  Scripts/sync-core.sh           # Syncs core/js and core/rules into Resources
  ZhuoBrowserMac.xcodeproj       # Generated Xcode project
  ZhuoBrowserMac/
    App/                         # App entry & menu commands
    Core/                        # State, memory budget policy, content blocker, library models/store
    UI/                          # Toolbar, tab strip, start view, web container, library manager
    Resources/                   # Bundled rules and core JavaScripts
  ZhuoBrowserMacTests/           # Unit tests for memory budget, policies, and bookmarks/history
```

## Setup & Build

Quick start with the root runner:

```bash
./run_release.sh macos
# or inside macos/
./run_release.sh
```

Or build manually:

```bash
cd macos
./Scripts/sync-core.sh
xcodegen generate
xcodebuild -project ZhuoBrowserMac.xcodeproj -scheme ZhuoBrowserMac -destination "platform=macOS" CODE_SIGN_IDENTITY="-" build
```

Run unit tests:

```bash
xcodebuild test -project ZhuoBrowserMac.xcodeproj -scheme ZhuoBrowserMacTests -destination "platform=macOS" CODE_SIGN_IDENTITY="-"
```
