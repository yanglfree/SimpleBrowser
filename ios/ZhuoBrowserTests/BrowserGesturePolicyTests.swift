import XCTest
@testable import ZhuoBrowser

final class BrowserGesturePolicyTests: XCTestCase {
    func testToolbarDirectionsMatchHarmonyContract() {
        let settings = BrowserSettings()

        XCTAssertEqual(action(x: 0, y: -22, settings: settings), .openActions)
        XCTAssertEqual(action(x: 0, y: 22, settings: settings), .hideToolbar)
        XCTAssertEqual(action(x: -22, y: 0, settings: settings, tabCount: 3, activeTabIndex: 0), .nextTab)
        XCTAssertEqual(action(x: 22, y: 0, settings: settings, tabCount: 3, activeTabIndex: 1), .previousTab)
        XCTAssertEqual(action(x: 10, y: 10, settings: settings), .none)
    }

    func testFinalTabForwardSwipeCreatesTab() {
        let settings = BrowserSettings()

        // 1-tab session: swiping forward creates exactly one tab
        XCTAssertEqual(action(x: -30, y: 0, settings: settings, tabCount: 1, activeTabIndex: 0), .createTab)

        // Multi-tab session on last tab: swiping forward creates tab
        XCTAssertEqual(action(x: -30, y: 0, settings: settings, tabCount: 3, activeTabIndex: 2), .createTab)

        // Multi-tab session on non-last tab: swiping forward selects nextTab
        XCTAssertEqual(action(x: -30, y: 0, settings: settings, tabCount: 3, activeTabIndex: 1), .nextTab)
    }

    func testFirstTabBackwardSwipeStaysPut() {
        let settings = BrowserSettings()

        // At first tab (index 0), swiping backward must stay put (.none)
        XCTAssertEqual(action(x: 30, y: 0, settings: settings, tabCount: 3, activeTabIndex: 0), .none)
        XCTAssertEqual(action(x: 30, y: 0, settings: settings, tabCount: 1, activeTabIndex: 0), .none)

        // At index > 0, swiping backward switches to previous tab
        XCTAssertEqual(action(x: 30, y: 0, settings: settings, tabCount: 3, activeTabIndex: 1), .previousTab)
    }

    func testMasterAndChildSwitchesDisableOnlyTheirGesture() {
        XCTAssertEqual(action(x: 0, y: -30, settings: BrowserSettings(gesturesEnabled: false)), .none)
        XCTAssertEqual(action(x: 0, y: -30, settings: BrowserSettings(gestureActionsEnabled: false)), .none)
        XCTAssertEqual(action(x: -30, y: 0, settings: BrowserSettings(gestureTabSwitchEnabled: false)), .none)
        XCTAssertEqual(action(x: 0, y: 30, settings: BrowserSettings(autoHideToolbarEnabled: false)), .none)
    }

    func testContextPreventsUnsafeOrMeaninglessGestures() {
        let settings = BrowserSettings()

        XCTAssertEqual(action(x: 0, y: 30, settings: settings, isBrowsing: false), .none)
        XCTAssertEqual(action(x: 0, y: -30, settings: settings, isEditingAddress: true), .none)
        XCTAssertEqual(action(x: -30, y: 0, settings: settings, isEditingAddress: true), .none)
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
        activeTabIndex: Int = 0,
        isEditingAddress: Bool = false
    ) -> BrowserToolbarGestureAction {
        BrowserGesturePolicy.toolbarAction(
            translationX: x,
            translationY: y,
            settings: settings,
            isBrowsing: isBrowsing,
            tabCount: tabCount,
            activeTabIndex: activeTabIndex,
            isEditingAddress: isEditingAddress
        )
    }
}
