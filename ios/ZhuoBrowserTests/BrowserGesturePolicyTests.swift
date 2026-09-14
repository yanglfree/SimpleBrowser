import XCTest
@testable import ZhuoBrowser

final class BrowserGesturePolicyTests: XCTestCase {
    func testToolbarDirectionsMatchHarmonyContract() {
        let settings = BrowserSettings()

        XCTAssertEqual(action(x: 0, y: -22, settings: settings), .openActions)
        XCTAssertEqual(action(x: 0, y: 22, settings: settings), .hideToolbar)
        XCTAssertEqual(action(x: -22, y: 0, settings: settings), .nextTab)
        XCTAssertEqual(action(x: 22, y: 0, settings: settings), .previousTab)
        XCTAssertEqual(action(x: 10, y: 10, settings: settings), .none)
    }

    func testMasterAndChildSwitchesDisableOnlyTheirGesture() {
        XCTAssertEqual(action(x: 0, y: -30, settings: BrowserSettings(gesturesEnabled: false)), .none)
        XCTAssertEqual(action(x: 0, y: -30, settings: BrowserSettings(gestureActionsEnabled: false)), .none)
        XCTAssertEqual(action(x: -30, y: 0, settings: BrowserSettings(gestureTabSwitchEnabled: false)), .none)
        XCTAssertEqual(action(x: 0, y: 30, settings: BrowserSettings(autoHideToolbarEnabled: false)), .none)
    }

    func testContextPreventsUnsafeOrMeaninglessGestures() {
        let settings = BrowserSettings()

        XCTAssertEqual(action(x: -30, y: 0, settings: settings, tabCount: 1), .none)
        XCTAssertEqual(action(x: 0, y: 30, settings: settings, isBrowsing: false), .none)
        XCTAssertEqual(action(x: 0, y: -30, settings: settings, isEditingAddress: true), .none)
        XCTAssertFalse(BrowserGesturePolicy.canOpenBlocking(settings: settings, isBrowsing: false))
        XCTAssertFalse(
            BrowserGesturePolicy.canOpenBlocking(
                settings: BrowserSettings(gestureBlockingEnabled: false),
                isBrowsing: true
            )
        )
        XCTAssertTrue(BrowserGesturePolicy.canOpenBlocking(settings: settings, isBrowsing: true))
    }

    private func action(
        x: Double,
        y: Double,
        settings: BrowserSettings,
        isBrowsing: Bool = true,
        tabCount: Int = 2,
        isEditingAddress: Bool = false
    ) -> BrowserToolbarGestureAction {
        BrowserGesturePolicy.toolbarAction(
            translationX: x,
            translationY: y,
            settings: settings,
            isBrowsing: isBrowsing,
            tabCount: tabCount,
            isEditingAddress: isEditingAddress
        )
    }
}
