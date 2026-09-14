import XCTest
@testable import ZhuoBrowser

final class PageLoadErrorPresentationTests: XCTestCase {
    func testNoneHasNoPresentation() {
        XCTAssertNil(PageLoadErrorPresentation(kind: .none))
    }

    func testNetworkErrorsHaveRecoverableVisualPresentations() {
        let offline = PageLoadErrorPresentation(kind: .offline)
        let timeout = PageLoadErrorPresentation(kind: .timeout)
        let dns = PageLoadErrorPresentation(kind: .dns)

        XCTAssertEqual(offline?.title, "没有网络连接")
        XCTAssertEqual(timeout?.title, "连接超时")
        XCTAssertEqual(dns?.title, "找不到该网站")
        XCTAssertNotNil(offline?.symbolName)
        XCTAssertNotNil(timeout?.symbolName)
        XCTAssertNotNil(dns?.symbolName)
    }

    func testOnlyCertificateErrorOffersSecurityDetails() {
        XCTAssertEqual(PageLoadErrorPresentation(kind: .certificate)?.showsSecurityDetails, true)
        XCTAssertEqual(PageLoadErrorPresentation(kind: .offline)?.showsSecurityDetails, false)
        XCTAssertEqual(PageLoadErrorPresentation(kind: .timeout)?.showsSecurityDetails, false)
        XCTAssertEqual(PageLoadErrorPresentation(kind: .dns)?.showsSecurityDetails, false)
        XCTAssertEqual(PageLoadErrorPresentation(kind: .unknown)?.showsSecurityDetails, false)
    }

    func testCertificateCopyDoesNotOfferBypass() {
        let presentation = PageLoadErrorPresentation(kind: .certificate)

        XCTAssertEqual(presentation?.title, "连接证书异常")
        XCTAssertEqual(presentation?.message, "为保护你的隐私，浏览器不会自动绕过证书错误。")
        XCTAssertNil(presentation?.symbolName)
    }
}
