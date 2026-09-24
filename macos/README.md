# Zhuoyue Browser for Mac (卓阅 Mac 客户端)

Native macOS SwiftUI + WebKit (`WKWebView`) shell engineered for **extreme memory frugality** and **distraction-free simplicity**.

## Core Philosophy

1. **Ultra-Low Memory Footprint (极致省内存)**:
   - Built on native macOS `WebKit.framework`. Libraries are shared via the system `dyld` cache; zero Chromium or Electron runtime bloat.
   - **Tab Hibernation (后台标签自动休眠)**: Enforces `MemoryBudgetPolicy` with a strict live webview quota (default 2 live WebViews). Inactive tabs automatically deallocate their `WKWebView` instances and underlying WebContent rendering processes while preserving scroll positions, page titles, and browsing history.
   - **Zero-JS Content Blocking**: Compiles EasyList starter rules into native `WKContentRuleList` binary bytecode directly evaluated inside WebKit's network process in C++, incurring zero JS runtime overhead.
2. **Minimalist Aesthetic (极致简洁)**:
   - Unified compact macOS toolbar: Navigation, Omnibox, Ad Shield, Memory Saver indicator, and New Tab button.
   - Clean horizontal tab bar with visual hibernation badges (`moon.zzz.fill`).
   - Native macOS keyboard shortcuts:
     - `Cmd+T`: New tab
     - `Cmd+W`: Close active tab
     - `Cmd+R`: Reload
     - `Cmd+[` / `Cmd+]`: Back / Forward
     - `Cmd+1` ... `Cmd+9`: Quick tab switching

## Directory Layout

```
macos/
  project.yml                    # XcodeGen project specification
  Scripts/sync-core.sh           # Syncs core/js and core/rules into Resources
  ZhuoBrowserMac.xcodeproj       # Generated Xcode project
  ZhuoBrowserMac/
    App/                         # App entry & menu commands
    Core/                        # State, memory budget policy, content blocker
    UI/                          # Toolbar, tab strip, start view, web container
    Resources/                   # Bundled rules and core JavaScripts
  ZhuoBrowserMacTests/           # Unit tests for memory budget and policies
```

## Setup & Build

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
