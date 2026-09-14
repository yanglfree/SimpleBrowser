import XCTest
@testable import ZhuoBrowser

final class PageIssueDiagnosticTests: XCTestCase {
    func testLayoutClassesMatchHarmonyBreakpoints() {
        XCTAssertEqual(BrowserLayoutClass.resolve(width: 599), .compact)
        XCTAssertEqual(BrowserLayoutClass.resolve(width: 600), .medium)
        XCTAssertEqual(BrowserLayoutClass.resolve(width: 839), .medium)
        XCTAssertEqual(BrowserLayoutClass.resolve(width: 840), .expanded)
    }

    func testSummaryContainsOnlyCoarsePageDiagnostics() {
        let events = [
            BlockEvent(
                id: "one",
                tabID: "tab",
                pageURL: "https://private.example/path",
                category: .advertisement,
                count: 3,
                occurredAt: Date(timeIntervalSince1970: 0)
            )
        ]
        var control = SiteControl(host: "private.example")
        control.networkBlocking = .enabled
        control.autoReader = .disabled

        let diagnostic = PageIssueDiagnostic.create(
            appVersion: "1.2.3 (45)",
            width: 390,
            height: 844,
            loadError: .timeout,
            events: events,
            control: control
        )

        XCTAssertTrue(diagnostic.summary.contains("load_error=timeout"))
        XCTAssertTrue(diagnostic.summary.contains("observable_cleanup_count=3"))
        XCTAssertTrue(diagnostic.summary.contains("site_overrides=2"))
        XCTAssertFalse(diagnostic.summary.contains("private.example"))
        XCTAssertFalse(diagnostic.summary.contains("/path"))
    }

    func testLoadErrorsMapToStableDiagnosticKinds() {
        XCTAssertEqual(PageLoadErrorKind.classify(URLError(.notConnectedToInternet)), .offline)
        XCTAssertEqual(PageLoadErrorKind.classify(URLError(.timedOut)), .timeout)
        XCTAssertEqual(PageLoadErrorKind.classify(URLError(.cannotFindHost)), .dns)
        XCTAssertEqual(PageLoadErrorKind.classify(URLError(.serverCertificateUntrusted)), .certificate)
        XCTAssertEqual(PageLoadErrorKind.classify(URLError(.cancelled)), .none)
    }
}
