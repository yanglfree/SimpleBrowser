import XCTest
@testable import ZhuoBrowser

final class AppInformationTests: XCTestCase {
    func testLegalAndSupportDestinationsAreCanonical() {
        XCTAssertEqual(AppInformation.termsURL.absoluteString, "https://browser.youdroid.top/terms.html")
        XCTAssertEqual(AppInformation.privacyURL.absoluteString, "https://browser.youdroid.top/privacy.html")
        XCTAssertEqual(AppInformation.supportURL.absoluteString, "mailto:youdroid2048@gmail.com")
        XCTAssertEqual(AppInformation.filingNumber, "鄂ICP备2024064800号-14A")
    }
}
