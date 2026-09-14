import XCTest
@testable import ZhuoBrowser

final class TabThumbnailPolicyTests: XCTestCase {
    func testCaptureRequiresVisibleNonPrivateWebContent() {
        XCTAssertTrue(
            TabThumbnailPolicy.shouldCapture(
                url: "https://example.com",
                isPrivate: false,
                isAttached: true,
                viewWidth: 390,
                viewHeight: 844
            )
        )
        XCTAssertFalse(
            TabThumbnailPolicy.shouldCapture(
                url: URLPolicy.homeURL,
                isPrivate: false,
                isAttached: true,
                viewWidth: 390,
                viewHeight: 844
            )
        )
        XCTAssertFalse(
            TabThumbnailPolicy.shouldCapture(
                url: "https://example.com",
                isPrivate: true,
                isAttached: true,
                viewWidth: 390,
                viewHeight: 844
            )
        )
        XCTAssertFalse(
            TabThumbnailPolicy.shouldCapture(
                url: "https://example.com",
                isPrivate: false,
                isAttached: false,
                viewWidth: 390,
                viewHeight: 844
            )
        )
        XCTAssertFalse(
            TabThumbnailPolicy.shouldCapture(
                url: "https://example.com",
                isPrivate: false,
                isAttached: true,
                viewWidth: 0,
                viewHeight: 844
            )
        )
    }

    func testSnapshotHeightUsesBoundedSixteenByNineCrop() {
        XCTAssertEqual(
            TabThumbnailPolicy.visibleSnapshotHeight(viewWidth: 360, viewHeight: 800),
            202.5
        )
        XCTAssertEqual(
            TabThumbnailPolicy.visibleSnapshotHeight(viewWidth: 360, viewHeight: 180),
            180
        )
        XCTAssertEqual(
            TabThumbnailPolicy.visibleSnapshotHeight(viewWidth: 0, viewHeight: 800),
            0
        )
    }
}
