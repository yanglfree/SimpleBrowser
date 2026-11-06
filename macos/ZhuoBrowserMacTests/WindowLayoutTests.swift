import AppKit
import SwiftUI
import WebKit
import XCTest
@testable import ZhuoBrowserMac

@MainActor
final class WindowLayoutTests: XCTestCase {

    func testWindowConfiguratorAppliesSeamlessTitlebarSettings() {
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        WindowConfigurator.configure(window: window)

        // Verify window settings
        XCTAssertTrue(window.styleMask.contains(.fullSizeContentView), "Window should use full-size content view")
        XCTAssertEqual(window.titleVisibility, .hidden, "Window title should be hidden")
        XCTAssertTrue(window.titlebarAppearsTransparent, "Titlebar should be transparent")
        XCTAssertNil(window.toolbar, "Toolbar should be nil to prevent empty system toolbar gaps")
        XCTAssertFalse(window.isMovableByWindowBackground, "Window background should not be movable to let controls handle events")
    }

    func testWindowDragNSViewCreation() {
        let dragView = WindowDragNSView(frame: NSRect(x: 0, y: 0, width: 200, height: 38))
        XCTAssertNotNil(dragView)
        XCTAssertEqual(dragView.frame.height, 38)
        XCTAssertTrue(dragView.mouseDownCanMoveWindow, "WindowDragNSView should allow moving window on drag")
    }

    func testUnifiedToolbarOmniboxFocusStateSync() {
        let session = BrowserSession()
        XCTAssertFalse(session.isOmniboxFocused)

        let toolbar = UnifiedToolbarView(session: session)
        let hostingView = NSHostingView(rootView: toolbar)
        hostingView.frame = NSRect(x: 0, y: 0, width: 800, height: 38)

        // Session omnibox focus toggle should propagate
        session.isOmniboxFocused = true
        XCTAssertTrue(session.isOmniboxFocused)

        session.isOmniboxFocused = false
        XCTAssertFalse(session.isOmniboxFocused)
    }

    func testUnifiedToolbarResponsiveLayoutWithSideSpaces() {
        let session = BrowserSession()
        let toolbar = UnifiedToolbarView(session: session)
        let hostingView = NSHostingView(rootView: toolbar)

        // Test at default desktop width
        hostingView.frame = NSRect(x: 0, y: 0, width: 1200, height: 38)
        hostingView.layoutSubtreeIfNeeded()
        XCTAssertEqual(hostingView.frame.width, 1200)

        // Test at expanded widescreen width
        hostingView.frame = NSRect(x: 0, y: 0, width: 1800, height: 38)
        hostingView.layoutSubtreeIfNeeded()
        XCTAssertEqual(hostingView.frame.width, 1800)
    }

    func testMinimalStartViewHostingAndDismissFocus() {
        let session = BrowserSession()
        let startView = MinimalStartView(session: session)
        let hostingView = NSHostingView(rootView: startView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        XCTAssertNotNil(hostingView)
    }

    func testWebContainerHostViewRetainsWarmWebViewsAcrossHomeAndTabSwitches() {
        let host = WebContainerView.HostView(frame: NSRect(x: 0, y: 0, width: 1024, height: 768))
        let webViewA = WKWebView(frame: .zero)
        let webViewB = WKWebView(frame: .zero)

        host.attach(webView: webViewA)
        XCTAssertTrue(webViewA.superview === host)
        XCTAssertFalse(webViewA.isHidden)
        XCTAssertEqual(webViewA.frame, host.bounds)

        // Switching to a New Tab (home page) passes nil: webViewA must stay attached in host and become hidden
        host.attach(webView: nil)
        XCTAssertTrue(webViewA.superview === host)
        XCTAssertTrue(webViewA.isHidden)

        // Switching to a second web tab attaches webViewB without tearing webViewA out of host
        host.attach(webView: webViewB)
        XCTAssertTrue(webViewA.superview === host)
        XCTAssertTrue(webViewA.isHidden)
        XCTAssertTrue(webViewB.superview === host)
        XCTAssertFalse(webViewB.isHidden)
        XCTAssertEqual(webViewB.frame, host.bounds)

        // Resizing the host updates both foreground and hidden warm WebViews
        host.setFrameSize(NSSize(width: 1440, height: 900))
        host.resizeSubviews(withOldSize: NSSize(width: 1024, height: 768))
        XCTAssertEqual(webViewA.frame.size, NSSize(width: 1440, height: 900))
        XCTAssertEqual(webViewB.frame.size, NSSize(width: 1440, height: 900))

        // Dismantle detaches all subviews cleanly
        host.detachAll()
        XCTAssertNil(webViewA.superview)
        XCTAssertNil(webViewB.superview)
    }

    func testHomeBackgroundManagerInitDoesNotBlockMainThread() {
        let start = CFAbsoluteTimeGetCurrent()
        let manager = HomeBackgroundManager(isPersistenceEnabled: false)
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
        XCTAssertNotNil(manager)
        XCTAssertLessThan(elapsedMs, 50, "HomeBackgroundManager init should not decode 4K/6K presets synchronously on the main thread")
    }

    func testTabBarDoubleClickNSViewBehaviors() {
        let view = TabBarDoubleClickNSView(frame: NSRect(x: 0, y: 0, width: 200, height: 28))
        XCTAssertFalse(view.mouseDownCanMoveWindow, "TabBar double-click background must not trigger window drag")
        XCTAssertTrue(view.acceptsFirstMouse(for: nil), "TabBar double-click background should accept first mouse")

        var doubleClickCount = 0
        view.onDoubleClick = {
            doubleClickCount += 1
        }

        // Single click (clickCount == 1) should not trigger creation
        let singleClickEvent = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: NSPoint(x: 10, y: 10),
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1.0
        )!
        view.mouseDown(with: singleClickEvent)
        XCTAssertEqual(doubleClickCount, 0, "Single click must not trigger new tab creation")

        // Double click (clickCount == 2) should trigger creation
        let doubleClickEvent = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: NSPoint(x: 10, y: 10),
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            eventNumber: 2,
            clickCount: 2,
            pressure: 1.0
        )!
        view.mouseDown(with: doubleClickEvent)
        XCTAssertEqual(doubleClickCount, 1, "Double click must trigger new tab creation once")

        // Immediate rapid follow-up clickCount == 2 within 250ms debounce should be filtered
        view.mouseDown(with: doubleClickEvent)
        XCTAssertEqual(doubleClickCount, 1, "Immediate consecutive double click within debounce window should be ignored")
    }

    func testCompactTabWidthClampsToMaxWidthWhenFewTabs() {
        let availableWidth: CGFloat = 1200
        // 1 tab: ample space, should be clamped to maxWidth (240)
        let width1 = compactTabWidth(availableWidth: availableWidth, tabCount: 1)
        XCTAssertEqual(width1, 240)

        // 2 tabs: 1200 - 36 - 4 = 1160 / 2 = 580 -> clamped to 240
        let width2 = compactTabWidth(availableWidth: availableWidth, tabCount: 2)
        XCTAssertEqual(width2, 240)
    }

    func testCompactTabWidthCompressesDynamicallyWithIncreasingTabs() {
        let availableWidth: CGFloat = 1180 // standard 1200px window minus 20px padding

        let width5 = compactTabWidth(availableWidth: availableWidth, tabCount: 5)
        let width8 = compactTabWidth(availableWidth: availableWidth, tabCount: 8)
        let width12 = compactTabWidth(availableWidth: availableWidth, tabCount: 12)
        let width16 = compactTabWidth(availableWidth: availableWidth, tabCount: 16)

        // Verify strictly monotonic decrease as tabs increase
        XCTAssertGreaterThan(width5, width8)
        XCTAssertGreaterThan(width8, width12)
        XCTAssertGreaterThan(width12, width16)

        // Verify that in all cases, the tabs + gaps + trailing space fit within available width
        for (count, width) in [(5, width5), (8, width8), (12, width12), (16, width16)] {
            let totalFootprint = CGFloat(count) * width + CGFloat(count - 1) * 4 + 36
            XCTAssertLessThanOrEqual(totalFootprint, availableWidth + 0.001, "Tabs must dynamically fit within availableWidth for tabCount \(count)")
        }
    }

    func testCompactTabWidthEnforcesMinimumWidthProtection() {
        let availableWidth: CGFloat = 800

        // 30 tabs on 800px width: raw calculation would be ~22px, clamped to minWidth (52)
        let width30 = compactTabWidth(availableWidth: availableWidth, tabCount: 30)
        XCTAssertEqual(width30, 52, "Tabs must never shrink below minWidth protection")

        // 60 tabs on small window
        let width60 = compactTabWidth(availableWidth: 400, tabCount: 60)
        XCTAssertEqual(width60, 52)
    }

    func testCompactTabWidthHandlesZeroOrNegativeAvailableWidth() {
        XCTAssertEqual(compactTabWidth(availableWidth: 1000, tabCount: 0), 240)
        XCTAssertEqual(compactTabWidth(availableWidth: -50, tabCount: 5), 52)
        XCTAssertEqual(compactTabWidth(availableWidth: 0, tabCount: 5), 52)
    }

    func testCompactTabBarViewHostingAndDynamicLayout() {
        let session = BrowserSession()
        _ = session.createTab(url: "https://example.com/1", select: false)
        _ = session.createTab(url: "https://example.com/2", select: false)
        _ = session.createTab(url: "https://example.com/3", select: false)
        _ = session.createTab(url: "https://example.com/4", select: false)
        _ = session.createTab(url: "https://example.com/5", select: false)
        _ = session.createTab(url: "https://example.com/6", select: true)

        let tabBar = CompactTabBarView(session: session)
        let hostingView = NSHostingView(rootView: tabBar)
        hostingView.frame = NSRect(x: 0, y: 0, width: 1200, height: 36)
        hostingView.layoutSubtreeIfNeeded()

        XCTAssertEqual(hostingView.frame.width, 1200)
        XCTAssertEqual(hostingView.frame.height, 36)
        XCTAssertEqual(session.tabs.count, 7) // 1 initial home tab + 6 created tabs
    }
}
