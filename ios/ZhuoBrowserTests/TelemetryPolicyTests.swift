import XCTest
@testable import ZhuoBrowser

final class TelemetryPolicyTests: XCTestCase {
    func testTelemetryRequiresConsentOptInAndNonPrivateContext() {
        XCTAssertFalse(TelemetryPolicy.allowsWrite(context(consent: false, enabled: true, isPrivate: false)))
        XCTAssertFalse(TelemetryPolicy.allowsWrite(context(consent: true, enabled: false, isPrivate: false)))
        XCTAssertFalse(TelemetryPolicy.allowsWrite(context(consent: true, enabled: true, isPrivate: true)))
        XCTAssertTrue(TelemetryPolicy.allowsWrite(context(consent: true, enabled: true, isPrivate: false)))
    }

    func testTelemetryOnlyAcceptsBoundedActionKeys() {
        XCTAssertEqual(TelemetryPolicy.sanitizedAction(" article_exported "), "article_exported")
        XCTAssertEqual(TelemetryPolicy.sanitizedAction(String(repeating: "a", count: 50))?.count, 40)
        XCTAssertNil(TelemetryPolicy.sanitizedAction(""))
        XCTAssertNil(TelemetryPolicy.sanitizedAction("https://example.com/private"))
        XCTAssertNil(TelemetryPolicy.sanitizedAction("search terms"))
    }

    func testTelemetryDurationsAreFiniteAndBounded() {
        XCTAssertEqual(TelemetryPolicy.clampedMilliseconds(-1), 0)
        XCTAssertEqual(TelemetryPolicy.clampedMilliseconds(.infinity), 0)
        XCTAssertEqual(TelemetryPolicy.clampedMilliseconds(12.6), 13)
        XCTAssertEqual(TelemetryPolicy.clampedMilliseconds(100_000_000), 86_400_000)
    }

    private func context(consent: Bool, enabled: Bool, isPrivate: Bool) -> TelemetryContext {
        TelemetryContext(consentAccepted: consent, enabled: enabled, isPrivate: isPrivate)
    }
}
