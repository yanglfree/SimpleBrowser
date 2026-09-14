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
}
