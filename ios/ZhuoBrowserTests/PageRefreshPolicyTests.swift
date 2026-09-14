import XCTest
@testable import ZhuoBrowser

final class PageRefreshPolicyTests: XCTestCase {
    func testBrowsingPageCanRefreshWhenIdle() {
        XCTAssertTrue(
            PageRefreshPolicy.isEnabled(
                isBrowsing: true,
                isReader: false,
                isLoading: false,
                hasLoadError: false
            )
        )
    }

    func testNonBrowsingAndTransientStatesCannotRefresh() {
        XCTAssertFalse(enabled(isBrowsing: false))
        XCTAssertFalse(enabled(isReader: true))
        XCTAssertFalse(enabled(isLoading: true))
        XCTAssertFalse(enabled(hasLoadError: true))
    }

    private func enabled(
        isBrowsing: Bool = true,
        isReader: Bool = false,
        isLoading: Bool = false,
        hasLoadError: Bool = false
    ) -> Bool {
        PageRefreshPolicy.isEnabled(
            isBrowsing: isBrowsing,
            isReader: isReader,
            isLoading: isLoading,
            hasLoadError: hasLoadError
        )
    }
}
