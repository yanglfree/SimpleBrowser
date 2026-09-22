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

        let expectedRequest = ExternalProtocolRequest(
            url: "weixin://pay?id=123",
            scheme: "weixin",
            category: .payment,
            sourceHost: "shop.example",
            targetAppName: "微信"
        )
        XCTAssertEqual(decision, .confirm(expectedRequest))
        XCTAssertEqual(expectedRequest.promptTitle, "打开微信？")
    }

    func testTargetAppNameResolution() {
        XCTAssertEqual(ExternalProtocolPolicy.resolveTargetAppName(scheme: "itms-apps"), "App Store")
        XCTAssertEqual(ExternalProtocolPolicy.resolveTargetAppName(scheme: "alipay"), "支付宝")
        XCTAssertEqual(ExternalProtocolPolicy.resolveTargetAppName(scheme: "mqq"), "QQ")
        XCTAssertEqual(ExternalProtocolPolicy.resolveTargetAppName(scheme: "bilibili"), "哔哩哔哩")
        XCTAssertEqual(ExternalProtocolPolicy.resolveTargetAppName(scheme: "customscheme"), "")

        let customRequest = ExternalProtocolRequest(
            url: "customscheme://action",
            scheme: "customscheme",
            category: .custom,
            sourceHost: "example.com",
            targetAppName: ""
        )
        XCTAssertEqual(customRequest.promptTitle, "打开其他应用？")
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
