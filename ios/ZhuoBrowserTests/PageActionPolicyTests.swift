import XCTest
@testable import ZhuoBrowser

final class PageActionPolicyTests: XCTestCase {
    func testHomeContextDisablesBrowsingActions() {
        let context = PageActionContext(
            url: URLPolicy.homeURL,
            isPrivate: false,
            isDesktop: false
        )

        XCTAssertTrue(context.isHome)
        XCTAssertFalse(context.isBrowsing)
        XCTAssertFalse(context.isPrivate)
        XCTAssertFalse(context.isDesktop)
    }

    func testPrivateDesktopPagePreservesActionState() {
        let context = PageActionContext(
            url: "https://example.com/article",
            isPrivate: true,
            isDesktop: true
        )

        XCTAssertFalse(context.isHome)
        XCTAssertTrue(context.isBrowsing)
        XCTAssertTrue(context.isPrivate)
        XCTAssertTrue(context.isDesktop)
    }
}
