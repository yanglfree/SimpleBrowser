import XCTest
@testable import ZhuoBrowser

final class AdaptiveWorkspacePolicyTests: XCTestCase {
    func testSidebarPresentationTracksLiveHarmonyBreakpoints() {
        XCTAssertEqual(AdaptiveWorkspacePolicy.sidebarPresentation(width: 599), .unavailable)
        XCTAssertEqual(AdaptiveWorkspacePolicy.sidebarPresentation(width: 600), .overlay)
        XCTAssertEqual(AdaptiveWorkspacePolicy.sidebarPresentation(width: 839), .overlay)
        XCTAssertEqual(AdaptiveWorkspacePolicy.sidebarPresentation(width: 840), .inline)
    }

    func testSidebarWidthMatchesHarmonyPaneWidths() {
        XCTAssertEqual(AdaptiveWorkspacePolicy.sidebarWidth(width: 600), 320)
        XCTAssertEqual(AdaptiveWorkspacePolicy.sidebarWidth(width: 840), 360)
        XCTAssertEqual(AdaptiveWorkspacePolicy.sidebarWidth(width: 1_200), 360)
        XCTAssertEqual(AdaptiveWorkspacePolicy.sidebarWidth(width: 1_440), 400)
    }

    func testArticleInspectorMatchesHarmonyWorkbenchModes() {
        XCTAssertEqual(AdaptiveWorkspacePolicy.articleWorkbenchMode(width: 599), .compact)
        XCTAssertEqual(AdaptiveWorkspacePolicy.articleWorkbenchMode(width: 600), .switchableInspector)
        XCTAssertFalse(AdaptiveWorkspacePolicy.showsArticleInspector(width: 600, requested: false))
        XCTAssertTrue(AdaptiveWorkspacePolicy.showsArticleInspector(width: 600, requested: true))
        XCTAssertEqual(AdaptiveWorkspacePolicy.articleWorkbenchMode(width: 840), .fixedInspector)
        XCTAssertTrue(AdaptiveWorkspacePolicy.showsArticleInspector(width: 840, requested: false))
    }

    func testReaderAndTabGridRemainBoundedAcrossWidths() {
        XCTAssertEqual(
            AdaptiveWorkspacePolicy.articleReaderMaximumWidth(availableWidth: 1_200, inspectorVisible: true),
            760
        )
        XCTAssertEqual(
            AdaptiveWorkspacePolicy.articleReaderMaximumWidth(availableWidth: 700, inspectorVisible: true),
            332
        )
        XCTAssertEqual(AdaptiveWorkspacePolicy.tabColumnCount(width: 390), 2)
        XCTAssertEqual(AdaptiveWorkspacePolicy.tabColumnCount(width: 700), 3)
        XCTAssertEqual(AdaptiveWorkspacePolicy.tabColumnCount(width: 1_024), 4)
    }

    func testPaneSelectionReplacesOnlyTheFocusedPane() {
        let ids: Set<String> = ["a", "b", "c"]
        var state = BrowserPaneState(primaryTabID: "a")
        state.beginSplit(primaryTabID: "a", secondaryTabID: "b")

        state.select("c", existingTabIDs: ids)

        XCTAssertEqual(state.primaryTabID, "a")
        XCTAssertEqual(state.secondaryTabID, "c")
        XCTAssertEqual(state.focusedTabID, "c")
    }

    func testPaneRepairPromotesSurvivingSecondaryTab() {
        var state = BrowserPaneState(primaryTabID: "a")
        state.beginSplit(primaryTabID: "a", secondaryTabID: "b")

        state.repair(existingTabIDs: ["b"], fallbackTabID: "b")

        XCTAssertEqual(state.primaryTabID, "b")
        XCTAssertNil(state.secondaryTabID)
        XCTAssertEqual(state.focusedSlot, .primary)
    }

    func testSplitRatioIsClampedToUsablePaneBounds() {
        var state = BrowserPaneState(primaryTabID: "a")
        state.setPrimaryRatio(0.1)
        XCTAssertEqual(state.primaryRatio, 0.3)
        state.setPrimaryRatio(0.9)
        XCTAssertEqual(state.primaryRatio, 0.7)
    }
}
