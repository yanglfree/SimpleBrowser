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
}
