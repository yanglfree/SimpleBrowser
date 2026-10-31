# Zhuoyue Browser for Mac (卓阅 Mac 客户端)

Native macOS SwiftUI + WebKit (`WKWebView`) shell engineered for **extreme memory frugality** and **distraction-free simplicity**.

## Core Philosophy

1. **Ultra-Low Memory Footprint (极致省内存)**:
   - Built on native macOS `WebKit.framework`. Libraries are shared via the system `dyld` cache; zero Chromium or Electron runtime bloat.
   - **Tab Hibernation (后台标签自动休眠)**: Enforces `MemoryBudgetPolicy` with a strict live webview quota (default 2 live WebViews). Inactive tabs automatically deallocate their `WKWebView` instances and underlying WebContent rendering processes while preserving scroll positions, page titles, and browsing history.
   - **Zero-JS Content Blocking**: Compiles EasyList starter rules into native `WKContentRuleList` binary bytecode directly evaluated inside WebKit's network process in C++, incurring zero JS runtime overhead.
2. **Minimalist Aesthetic & Parity (极致简洁与完整功能)**:
   - Unified compact macOS toolbar: Navigation, Omnibox, Star Bookmark toggle, Ad Shield, Memory Saver indicator, Bookmarks/History library button, and New Tab button.
   - Clean horizontal tab bar with visual hibernation badges (`moon.zzz.fill`).
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
