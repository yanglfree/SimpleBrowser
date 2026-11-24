import XCTest
@testable import ZhuoBrowserMac

final class TelemetryServiceTests: XCTestCase {
    func testMacTelemetryPolicyAllowsNonPrivateEnabledWritesOnly() {
        XCTAssertTrue(MacTelemetryPolicy.allowsWrite(enabled: true, isPrivate: false))
        XCTAssertFalse(MacTelemetryPolicy.allowsWrite(enabled: false, isPrivate: false))
        XCTAssertFalse(MacTelemetryPolicy.allowsWrite(enabled: true, isPrivate: true))
        XCTAssertFalse(MacTelemetryPolicy.allowsWrite(enabled: false, isPrivate: true))
    }

    func testMacTelemetryPolicySanitizesActionsAndRejectsURLsOrWhitespace() {
        XCTAssertEqual(MacTelemetryPolicy.sanitizedAction(" tab_created "), "tab_created")
        XCTAssertEqual(MacTelemetryPolicy.sanitizedAction(String(repeating: "x", count: 50))?.count, 40)
        XCTAssertNil(MacTelemetryPolicy.sanitizedAction(""))
        XCTAssertNil(MacTelemetryPolicy.sanitizedAction("https://example.com/path"))
        XCTAssertNil(MacTelemetryPolicy.sanitizedAction("search query"))
    }

    func testTelemetryServiceSuppressesPrivateAndDisabledAndFlushesMacOSEvent() async throws {
        let suiteName = "com.youdroid.zhuobrowser.mac.telemetry.tests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let storage = InMemoryMacShuYiShuStorage()
        let transport = MockMacShuYiShuTransport()
        let analytics = ShuYiShuAnalytics(
            baseURL: TelemetryService.defaultBaseURL,
            appKey: "dev_zhuobrowser_macos",
            productId: TelemetryService.productId,
            platform: "macos",
            appVersion: "1.0.0",
            buildNumber: "1",
            installationId: "mac-test-install",
            transport: transport,
            storage: storage,
            queueStorageKey: "shuyishu.mac.test.queue",
            firstOpenStorageKey: "shuyishu.mac.test.first_open",
            lastAppVersionStorageKey: "shuyishu.mac.test.last_version",
            consentState: .granted
        )
        let service = TelemetryService(
            analytics: analytics,
            userDefaults: userDefaults,
            enabledKey: "Test_TelemetryEnabled",
            bypassTestGuard: true
        )

        service.recordActionUsage("tab_created", isPrivate: true)
        service.setEnabled(false)
        service.recordActionUsage("tab_created", isPrivate: false)
        XCTAssertEqual(service.pendingEventCount, 0)

        service.setEnabled(true)
        service.recordActionUsage("bookmark_manager_opened", isPrivate: false)
        XCTAssertEqual(service.pendingEventCount, 1)

        try await service.flush()
        XCTAssertEqual(service.pendingEventCount, 0)
        XCTAssertEqual(transport.requests.count, 1)
        let body = transport.requests[0].body
        XCTAssertTrue(body.contains("\"product_id\":\"product-zhuobrowser\""))
        XCTAssertTrue(body.contains("\"platform\":\"macos\""))
        XCTAssertTrue(body.contains("\"action\":\"bookmark_manager_opened\""))
    }
}

private final class InMemoryMacShuYiShuStorage: ShuYiShuStorage {
    private var store: [String: String] = [:]

    func readString(forKey key: String) -> String? {
        store[key]
    }

    func writeString(_ value: String, forKey key: String) {
        store[key] = value
    }
}

private final class MockMacShuYiShuTransport: ShuYiShuTransport, @unchecked Sendable {
    var requests: [TransportRequest] = []

    func postJson(_ request: TransportRequest) async throws -> TransportResponse {
        requests.append(request)
        return TransportResponse(statusCode: 200, body: "{\"accepted\":1,\"duplicates\":0,\"rejected\":0}")
    }
}
