import XCTest
@testable import ZhuoBrowser

final class WebLinkActionPolicyTests: XCTestCase {
    func testOnlyNetworkWebLinksReceiveProductActions() {
        XCTAssertEqual(
            WebLinkActionPolicy.webURL(URL(string: "https://example.com/article"))?.absoluteString,
            "https://example.com/article"
        )
        XCTAssertNotNil(WebLinkActionPolicy.webURL(URL(string: "http://localhost:8080")))
        XCTAssertNil(WebLinkActionPolicy.webURL(URL(string: "javascript:alert(1)")))
        XCTAssertNil(WebLinkActionPolicy.webURL(URL(string: "mailto:hello@example.com")))
        XCTAssertNil(WebLinkActionPolicy.webURL(URL(string: "https:///missing-host")))
        XCTAssertNil(WebLinkActionPolicy.webURL(nil))
    }

    func testPrivateLinksCannotEnterPersistentReadLaterLibrary() {
        XCTAssertTrue(WebLinkActionPolicy.canSaveForLater(isPrivate: false))
        XCTAssertFalse(WebLinkActionPolicy.canSaveForLater(isPrivate: true))
    }
}
