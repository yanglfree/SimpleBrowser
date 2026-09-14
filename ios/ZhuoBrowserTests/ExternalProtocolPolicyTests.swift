import XCTest
@testable import ZhuoBrowser

final class ExternalProtocolPolicyTests: XCTestCase {
    func testWebAndInternalProtocolsStayInsideWebKit() {
        for value in [
            "https://example.com", "http://localhost:8080", "about:blank", "resource://local", "browser://home"
        ] {
            XCTAssertEqual(ExternalProtocolPolicy.decision(for: value, sourceURL: ""), .allow)
        }
    }

    func testPrivilegedProtocolsAreBlocked() {
        for value in ["javascript:alert(1)", "chrome-devtools://inspect", "DEVTOOLS://page"] {
            XCTAssertEqual(ExternalProtocolPolicy.decision(for: value, sourceURL: "https://example.com"), .blocked)
        }
    }

    func testExternalProtocolsRequireConfirmationAndKeepTheOriginalURL() {
        let decision = ExternalProtocolPolicy.decision(
            for: "weixin://pay?id=123",
            sourceURL: "https://Shop.Example/checkout"
        )

        XCTAssertEqual(
            decision,
            .confirm(
                ExternalProtocolRequest(
                    url: "weixin://pay?id=123",
                    scheme: "weixin",
                    category: .payment,
                    sourceHost: "shop.example"
                )
            )
        )
    }

    func testClipboardVisitAcceptsOnlyWebAddresses() {
        XCTAssertEqual(
            ExternalProtocolPolicy.clipboardAddress(from: " example.com/path ", engine: .bing),
            "https://example.com/path"
        )
        XCTAssertEqual(
            ExternalProtocolPolicy.clipboardAddress(from: "localhost:8080", engine: .bing),
            "http://localhost:8080"
        )
        XCTAssertNil(ExternalProtocolPolicy.clipboardAddress(from: "search words", engine: .bing))
        XCTAssertNil(ExternalProtocolPolicy.clipboardAddress(from: "javascript:alert(1)", engine: .bing))
    }
}
