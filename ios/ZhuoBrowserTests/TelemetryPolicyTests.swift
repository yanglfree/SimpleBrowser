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

    func testShuYiShuSuppressesPrivateAndUnconsentedWritesAndFlushesAllowedEvents() async throws {
        let storage = InMemoryShuYiShuStorage()
        let transport = MockShuYiShuTransport()
        let service = TelemetryService.makeForTesting(storage: storage, transport: transport)

        service.recordActionUsage("tab_created", context: context(consent: false, enabled: true, isPrivate: false))
        service.recordActionUsage("tab_created", context: context(consent: true, enabled: false, isPrivate: false))
        service.recordActionUsage("tab_created", context: context(consent: true, enabled: true, isPrivate: true))
        XCTAssertEqual(service.pendingEventCount, 0)

        service.recordActionUsage(" article_exported ", context: context(consent: true, enabled: true, isPrivate: false))
        XCTAssertEqual(service.pendingEventCount, 1)

        try await service.flush()
        XCTAssertEqual(service.pendingEventCount, 0)
        XCTAssertEqual(transport.requests.count, 1)
        let body = transport.requests[0].body
        XCTAssertTrue(body.contains("\"product_id\":\"product-zhuobrowser\""))
        XCTAssertTrue(body.contains("\"action\":\"article_exported\""))
    }

    private func context(consent: Bool, enabled: Bool, isPrivate: Bool) -> TelemetryContext {
        TelemetryContext(consentAccepted: consent, enabled: enabled, isPrivate: isPrivate)
    }
}

private final class InMemoryShuYiShuStorage: ShuYiShuStorage {
    private var values: [String: String] = [:]

    func readString(forKey key: String) -> String? {
        values[key]
    }

    func writeString(_ value: String, forKey key: String) {
        values[key] = value
    }
}

private final class MockShuYiShuTransport: ShuYiShuTransport, @unchecked Sendable {
    var requests: [TransportRequest] = []

    func postJson(_ request: TransportRequest) async throws -> TransportResponse {
        requests.append(request)
        return TransportResponse(statusCode: 200, body: "{\"accepted\":1,\"duplicates\":0,\"rejected\":0}")
    }
}
