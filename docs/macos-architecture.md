# macOS Architecture & Memory Thrift Specification

## Objective

Build a desktop client for ZhuoBrowser on macOS that achieves **extreme memory efficiency** and **distraction-free simplicity**, solving the pervasive problem of modern desktop browsers (Chrome, Edge, Arc) consuming gigabytes of RAM.

## System Architecture

```
┌────────────────────────────────────────────────────────────────────────┐
│                        ZhuoBrowserMac (SwiftUI)                        │
├────────────────────────────────┬───────────────────────────────────────┤
│        Unified Toolbar         │ Back / Forward / Omnibox / Mem Saver  │
├────────────────────────────────┴───────────────────────────────────────┤
│        Compact Tab Strip       │ Active Tab / Hibernated Badges (💤)   │
├────────────────────────────────────────────────────────────────────────┤
│                           Content Viewport                             │
│  ┌─────────────────────────────┐    ┌────────────────────────────────┐  │
│  │   MinimalStartView (Home)   │ or │      WebContainerView (Web)    │  │
│  │   Zero-DOM / Zero-Network   │    │      Hosted WKWebView          │  │
│  └─────────────────────────────┘    └────────────────────────────────┘  │
└────────────────────────────────┬───────────────────────────────────────┘
                                 │
                 ┌───────────────┴───────────────┐
                 │         BrowserSession        │
                 ├───────────────────────────────┤
                 │ - Tab management              │
                 │ - Enforces MemoryBudgetPolicy │
                 └───────────────┬───────────────┘
                                 │
     ┌───────────────────────────┼───────────────────────────┐
     │                           │                           │
┌────▼─────────────────┐   ┌─────▼────────────────┐   ┌──────▼─────────────┐
│  MemoryBudgetPolicy  │   │    ContentBlocker    │   │  InjectedScripts   │
├──────────────────────┤   ├──────────────────────┤   ├────────────────────┤
│ - Live budget (1~4)  │   │ - WKContentRuleList  │   │ - reader-core.js   │
│ - Automatic eviction │   │ - EasyList / China   │   │ - cleanup.js       │
│ - Scroll restoration │   │ - C++ network engine │   │ - tracker-block.js │
└──────────────────────┘   └──────────────────────┘   └────────────────────┘
```

## Memory Optimization Mechanisms

### 1. Tab Hibernation & Strict Live WebKit Budget
- **The Problem**: Chromium browsers spawn multiple processes per tab, keeping DOM trees, JS heaps, and GPU textures alive indefinitely.
- **The Solution**: ZhuoBrowser Mac sets a strict `liveWebViewBudget` (default `2`, configurable to `1`).
- **The Lifecycle**:
  1. Active tab + most recent tab maintain live `WKWebView` instances.
  2. Any tab falling outside the budget is immediately evicted:
     - Captures scroll offset `window.scrollY`.
     - Invalidates KVO observers.
     - Calls `destroy()` on `TabController` and tears down `WKWebView`.
     - macOS terminates or trims the associated `WebContent` rendering process.
  3. When the user returns to a hibernated tab, a new `WKWebView` is created on demand, loading the page and smoothly restoring the scroll position.

### 2. Declarative Native Ad Blocking (`WKContentRuleList`)
- Traditional browser extensions run user-script engines in every subframe, parsing regex rules and listening to DOM mutations.
- ZhuoBrowser Mac compiles EasyList rules into WebKit's native binary format via `WKContentRuleListStore`. Rules are evaluated at the network layer in C++ with 0 JavaScript execution cost.

### 3. Pure System Framework Foundation
- No Electron runtime, no bundled Chromium binaries, no Node.js backend.
- Base application heap is ~30MB–50MB, providing instantaneous cold starts (<100ms).

## Quality Verification

All memory budget decisions are backed by unit tests in `ZhuoBrowserMacTests/MemoryBudgetPolicyTests.swift`:
- `testActiveTabIsAlwaysKeptAlive`
- `testBudgetPreservesMostRecentTabs`
- `testBudgetWithinLimitDoesNotHibernate`
- `testClampedBudgetEnforcesLimits`
- `testURLPolicyLooksLikeURLAndNormalization`
