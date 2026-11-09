import AppKit
import SwiftUI
import XCTest
@testable import ZhuoBrowserMac

@MainActor
final class BookmarkPopoverFocusTests: XCTestCase {

    /// Regression guard for the "star button sometimes freezes the window" report.
    ///
    /// While a popover window is presented, AppKit asks its content for the first key
    /// view; an editable `NSTextField` answers by selecting all of its text, and TextKit
    /// follows with a synchronous input-method (IME) activation. With third-party IMEs
    /// that nested run-loop wait has been measured at ~1.7s of blocked main thread.
    /// The bookmark popover therefore renders its fields non-focusable first and only
    /// enables them once it is on screen.
    func testBookmarkPopoverRendersNoFocusableFieldBeforePresentationCompletes() {
        XCTAssertGreaterThan(
            OmniboxBookmarkPopoverView.focusEnableDelay,
            0,
            "The fields must not be editable during the popover's window setup"
        )

        let session = BrowserSession()
        let hosting = NSHostingView(
            rootView: OmniboxBookmarkPopoverView(session: session, isPresented: .constant(true))
        )
        hosting.frame = NSRect(x: 0, y: 0, width: 340, height: 440)
        hosting.layoutSubtreeIfNeeded()

        let fields = textFields(in: hosting)
        XCTAssertFalse(fields.isEmpty, "The popover should render its name and URL fields")
        XCTAssertTrue(
            fields.allSatisfy { !$0.acceptsFirstResponder },
            "No popover text field may accept first responder during window setup"
        )
    }

    private func textFields(in view: NSView) -> [NSTextField] {
        var found: [NSTextField] = []
        for subview in view.subviews {
            if let field = subview as? NSTextField {
                found.append(field)
            }
            found.append(contentsOf: textFields(in: subview))
        }
        return found
    }
}
