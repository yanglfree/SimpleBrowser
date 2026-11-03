import XCTest
@testable import ZhuoBrowserMac

@MainActor
final class SecuritySettingsTests: XCTestCase {

    func testSafeBrowsingLevelDefaultsAndTitles() {
        XCTAssertEqual(SafeBrowsingLevel.standard.title, "标准保护")
        XCTAssertEqual(SafeBrowsingLevel.enhanced.title, "增强型保护")
        XCTAssertEqual(SafeBrowsingLevel.disabled.title, "不保护（不建议）")

        XCTAssertFalse(SafeBrowsingLevel.standard.detailDescription.isEmpty)
        XCTAssertFalse(SafeBrowsingLevel.enhanced.detailDescription.isEmpty)
        XCTAssertFalse(SafeBrowsingLevel.disabled.detailDescription.isEmpty)
    }

    func testSecureDNSProviderDefaultsAndEndpoints() {
        XCTAssertEqual(SecureDNSProvider.system.displayName, "操作系统默认设置（若有）")
        XCTAssertEqual(SecureDNSProvider.google.defaultDoHURL, "https://dns.google/dns-query")
        XCTAssertEqual(SecureDNSProvider.cloudflare.defaultDoHURL, "https://cloudflare-dns.com/dns-query")
        XCTAssertEqual(SecureDNSProvider.alidns.defaultDoHURL, "https://dns.alidns.com/dns-query")
        XCTAssertEqual(SecureDNSProvider.dnspod.defaultDoHURL, "https://doh.pub/dns-query")
        XCTAssertEqual(SecureDNSProvider.custom.defaultDoHURL, "")
    }

    func testPersistedBrowserSettingsBackwardCompatibility() throws {
        // Legacy JSON without any of the new security fields
        let legacyJSON = """
        {
            "searchEngine": "Google",
            "quickSitesEnabled": true,
            "liveWebViewBudget": 2,
            "tabHibernationEnabled": false,
            "adBlockEnabled": true,
            "cosmeticCleanupEnabled": true,
            "restoreSessionOnLaunch": true,
            "updatedAt": 1730000000000,
            "hasPendingLocalChanges": false
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(PersistedBrowserSettings.self, from: legacyJSON)
        XCTAssertEqual(decoded.searchEngine, .google)
        // Assert new security properties fallback safely to defaults
        XCTAssertEqual(decoded.safeBrowsingLevel, .standard)
        XCTAssertFalse(decoded.alwaysUseSecureConnections)
        XCTAssertTrue(decoded.leakedPasswordDetectionEnabled)
        XCTAssertTrue(decoded.secureDNSEnabled)
        XCTAssertEqual(decoded.secureDNSProvider, .system)
        XCTAssertEqual(decoded.customSecureDNSURL, "")
        XCTAssertTrue(decoded.javascriptJITOptimizationEnabled)
    }

    func testPersistedBrowserSettingsFullRoundTrip() throws {
        let original = PersistedBrowserSettings(
            searchEngine: .duckDuckGo,
            quickSitesEnabled: false,
            liveWebViewBudget: 3,
            tabHibernationEnabled: true,
            adBlockEnabled: true,
            cosmeticCleanupEnabled: false,
            restoreSessionOnLaunch: false,
            safeBrowsingLevel: .enhanced,
            alwaysUseSecureConnections: true,
            leakedPasswordDetectionEnabled: false,
            secureDNSEnabled: true,
            secureDNSProvider: .cloudflare,
            customSecureDNSURL: "https://custom.dns/query",
            javascriptJITOptimizationEnabled: false,
            updatedAt: 1730600000000,
            hasPendingLocalChanges: true
        )

        let encoded = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(PersistedBrowserSettings.self, from: encoded)

        XCTAssertEqual(restored, original)
        XCTAssertEqual(restored.safeBrowsingLevel, .enhanced)
        XCTAssertTrue(restored.alwaysUseSecureConnections)
        XCTAssertFalse(restored.leakedPasswordDetectionEnabled)
        XCTAssertEqual(restored.secureDNSProvider, .cloudflare)
        XCTAssertEqual(restored.customSecureDNSURL, "https://custom.dns/query")
        XCTAssertFalse(restored.javascriptJITOptimizationEnabled)
    }

    func testBrowserSettingsIsolatedMutation() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let tempFile = tempDir.appendingPathComponent("settings.json")
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let isolated = BrowserSettings(
            persistsAutomatically: false,
            userDefaults: UserDefaults(suiteName: "test.security.settings.\(UUID().uuidString)"),
            settingsFileURL: tempFile
        )

        XCTAssertEqual(isolated.safeBrowsingLevel, .standard)
        XCTAssertFalse(isolated.alwaysUseSecureConnections)

        isolated.safeBrowsingLevel = .enhanced
        isolated.alwaysUseSecureConnections = true
        isolated.secureDNSProvider = .alidns
        isolated.customSecureDNSURL = "https://dns.alidns.com/dns-query"
        isolated.javascriptJITOptimizationEnabled = false

        isolated.flushSynchronously()

        let snapshot = isolated.snapshot
        XCTAssertEqual(snapshot.safeBrowsingLevel, .enhanced)
        XCTAssertTrue(snapshot.alwaysUseSecureConnections)
        XCTAssertEqual(snapshot.secureDNSProvider, .alidns)
        XCTAssertEqual(snapshot.customSecureDNSURL, "https://dns.alidns.com/dns-query")
        XCTAssertFalse(snapshot.javascriptJITOptimizationEnabled)
    }

    func testAccountManagerSettingsSyncIncludesSecurityOptions() {
        let isolated = BrowserSettings(persistsAutomatically: false)
        isolated.safeBrowsingLevel = .enhanced
        isolated.alwaysUseSecureConnections = true
        isolated.secureDNSEnabled = true
        isolated.secureDNSProvider = .google
        isolated.javascriptJITOptimizationEnabled = false

        let payload = AccountManager.shared.settingsPayload(from: isolated)
        XCTAssertEqual(payload["safeBrowsingLevel"] as? String, "enhanced")
        XCTAssertEqual(payload["alwaysUseSecureConnections"] as? Bool, true)
        XCTAssertEqual(payload["secureDNSEnabled"] as? Bool, true)
        XCTAssertEqual(payload["secureDNSProvider"] as? String, "google")
        XCTAssertEqual(payload["javascriptJITOptimizationEnabled"] as? Bool, false)

        let targetSettings = BrowserSettings(persistsAutomatically: false)
        AccountManager.shared.applySettings([
            "safeBrowsingLevel": "disabled",
            "alwaysUseSecureConnections": true,
            "secureDNSEnabled": false,
            "secureDNSProvider": "dnspod",
            "customSecureDNSURL": "https://doh.pub/dns-query",
            "javascriptJITOptimizationEnabled": false,
            "updatedAt": 2000000000000
        ], to: targetSettings)

        XCTAssertEqual(targetSettings.safeBrowsingLevel, .disabled)
        XCTAssertTrue(targetSettings.alwaysUseSecureConnections)
        XCTAssertFalse(targetSettings.secureDNSEnabled)
        XCTAssertEqual(targetSettings.secureDNSProvider, .dnspod)
        XCTAssertEqual(targetSettings.customSecureDNSURL, "https://doh.pub/dns-query")
        XCTAssertFalse(targetSettings.javascriptJITOptimizationEnabled)
    }
}
