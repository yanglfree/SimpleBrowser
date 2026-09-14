import XCTest
@testable import ZhuoBrowser

final class BrowsingPrivacyPolicyTests: XCTestCase {
    func testSelectionRequiresAtLeastOneDataType() {
        XCTAssertTrue(BrowsingDataSelection().hasSelection)
        XCTAssertFalse(
            BrowsingDataSelection(
                history: false,
                cookies: false,
                cache: false,
                permissions: false
            ).hasSelection
        )
    }

    func testHistoryCutoffsAreDeterministic() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_789_387_200)

        XCTAssertEqual(
            BrowsingPrivacyPolicy.cutoff(for: .sevenDays, now: now, calendar: calendar),
            now.addingTimeInterval(-7 * 24 * 60 * 60)
        )
        XCTAssertEqual(
            BrowsingPrivacyPolicy.cutoff(for: .thirtyDays, now: now, calendar: calendar),
            now.addingTimeInterval(-30 * 24 * 60 * 60)
        )
        XCTAssertLessThan(BrowsingPrivacyPolicy.cutoff(for: .all), Date(timeIntervalSince1970: 0))
    }

    func testWebsiteDataRecordMatchesParentDomain() {
        XCTAssertTrue(BrowsingPrivacyPolicy.recordDisplayName("example.com", matches: "www.example.com"))
        XCTAssertTrue(BrowsingPrivacyPolicy.recordDisplayName("example.com", matches: "example.com"))
        XCTAssertFalse(BrowsingPrivacyPolicy.recordDisplayName("ample.com", matches: "example.com"))
        XCTAssertFalse(BrowsingPrivacyPolicy.recordDisplayName("", matches: "example.com"))
    }

    func testSecurityStateFollowsSchemeAndMixedContent() {
        XCTAssertEqual(SiteSecurityPolicy.state(for: "https://example.com"), .secure)
        XCTAssertEqual(
            SiteSecurityPolicy.state(for: "https://example.com", hasOnlySecureContent: false),
            .insecure
        )
        XCTAssertEqual(SiteSecurityPolicy.state(for: "http://example.com"), .insecure)
        XCTAssertEqual(SiteSecurityPolicy.state(for: "browser://home"), .unknown)
        XCTAssertEqual(SiteSecurityPolicy.provisionalState(for: "https://example.com"), .unknown)
        XCTAssertEqual(SiteSecurityPolicy.provisionalState(for: "http://example.com"), .insecure)
    }

    func testPasswordWarningOnlyAppliesToHTTP() {
        XCTAssertTrue(SiteSecurityPolicy.shouldWarnForPasswordFocus(on: "http://example.com/login"))
        XCTAssertFalse(SiteSecurityPolicy.shouldWarnForPasswordFocus(on: "https://example.com/login"))
    }

    func testCertificateErrorsRequireURLDomainAndKnownCode() {
        XCTAssertTrue(
            SiteSecurityPolicy.isCertificateError(
                NSError(domain: NSURLErrorDomain, code: NSURLErrorServerCertificateUntrusted)
            )
        )
        XCTAssertFalse(
            SiteSecurityPolicy.isCertificateError(
                NSError(domain: "Example", code: NSURLErrorServerCertificateUntrusted)
            )
        )
        XCTAssertFalse(
            SiteSecurityPolicy.isCertificateError(
                NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
            )
        )
    }
}
