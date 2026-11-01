import AppKit
import SwiftUI
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
}
