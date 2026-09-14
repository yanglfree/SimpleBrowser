import XCTest
@testable import ZhuoBrowser

final class AdaptiveWorkspacePolicyTests: XCTestCase {
    func testSidebarPresentationTracksLiveHarmonyBreakpoints() {
        XCTAssertEqual(AdaptiveWorkspacePolicy.sidebarPresentation(width: 599), .unavailable)
        XCTAssertEqual(AdaptiveWorkspacePolicy.sidebarPresentation(width: 600), .overlay)
        XCTAssertEqual(AdaptiveWorkspacePolicy.sidebarPresentation(width: 839), .overlay)
        XCTAssertEqual(AdaptiveWorkspacePolicy.sidebarPresentation(width: 840), .inline)
        XCTAssertEqual(BrowserLayoutClass.resolve(width: 1_439), .expanded)
        XCTAssertEqual(BrowserLayoutClass.resolve(width: 1_440), .desktop)
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

    func testDesktopTabStripMatchesHarmonySizingContract() {
        XCTAssertFalse(AdaptiveWorkspacePolicy.showsDesktopTabStrip(width: 1_439))
        XCTAssertTrue(AdaptiveWorkspacePolicy.showsDesktopTabStrip(width: 1_440))
        XCTAssertEqual(
            AdaptiveWorkspacePolicy.desktopTabWidth(
                availableWidth: 1_000,
                tabCount: 5,
                pinnedCount: 1
            ),
            219
        )
        XCTAssertEqual(
            AdaptiveWorkspacePolicy.desktopTabWidth(
                availableWidth: 400,
                tabCount: 6,
                pinnedCount: 0
            ),
            88
        )
        XCTAssertEqual(
            AdaptiveWorkspacePolicy.desktopTabWidth(
                availableWidth: 2_000,
                tabCount: 2,
                pinnedCount: 0
            ),
            240
        )
        XCTAssertEqual(
            AdaptiveWorkspacePolicy.desktopTabWidth(
                availableWidth: 1_000,
                tabCount: 3,
                pinnedCount: 3
            ),
            88
        )
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
