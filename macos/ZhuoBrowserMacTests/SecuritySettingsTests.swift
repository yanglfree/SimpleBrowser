import WebKit
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

    func testDistributionChannelCapabilitiesAndOverride() {
        defer { DistributionChannel.overrideForTesting = nil }

        DistributionChannel.overrideForTesting = .appStore
        XCTAssertEqual(DistributionChannel.current, .appStore)
        XCTAssertFalse(DistributionChannel.current.allowsExternalExtensionPackages)

        DistributionChannel.overrideForTesting = .directDMG
        XCTAssertEqual(DistributionChannel.current, .directDMG)
        XCTAssertTrue(DistributionChannel.current.allowsExternalExtensionPackages)
    }

    func testSecurityRuntimeServiceBindings() {
        let config = WKWebViewConfiguration()

        SecurityRuntimeService.applySafeBrowsing(level: .disabled, to: config)
        XCTAssertFalse(config.preferences.isFraudulentWebsiteWarningEnabled)

        SecurityRuntimeService.applySafeBrowsing(level: .standard, to: config)
        XCTAssertTrue(config.preferences.isFraudulentWebsiteWarningEnabled)

        SecurityRuntimeService.applySafeBrowsing(level: .enhanced, to: config)
        XCTAssertTrue(config.preferences.isFraudulentWebsiteWarningEnabled)

        XCTAssertNil(SecurityRuntimeService.effectiveDoHURL(enabled: false, provider: .cloudflare, customURL: ""))
        XCTAssertNil(SecurityRuntimeService.effectiveDoHURL(enabled: true, provider: .system, customURL: ""))
        XCTAssertNil(SecurityRuntimeService.effectiveDoHURL(enabled: true, provider: .custom, customURL: "http://insecure.dns/query"))
        XCTAssertEqual(
            SecurityRuntimeService.effectiveDoHURL(enabled: true, provider: .cloudflare, customURL: "")?.absoluteString,
            "https://cloudflare-dns.com/dns-query"
        )
        XCTAssertEqual(
            SecurityRuntimeService.effectiveDoHURL(enabled: true, provider: .custom, customURL: "https://dns.example.org/dns-query")?.absoluteString,
            "https://dns.example.org/dns-query"
        )

        XCTAssertTrue(SecurityRuntimeService.isPasswordKnownCompromised("123456"))
        XCTAssertTrue(SecurityRuntimeService.isPasswordKnownCompromised("Password"))
        XCTAssertTrue(SecurityRuntimeService.isPasswordKnownCompromised("aaaaaa"))
        XCTAssertTrue(SecurityRuntimeService.isPasswordKnownCompromised("67890"))
        XCTAssertFalse(SecurityRuntimeService.isPasswordKnownCompromised("Zhuo!9xK#2026mQ"))

        let noJITScript = SecurityRuntimeService.makeHardenedNoJITScript()
        XCTAssertEqual(noJITScript.injectionTime, .atDocumentStart)
        XCTAssertTrue(noJITScript.source.contains("__zhuoHardenedNoJIT"))
    }

    func testPerSiteAdBlockAllowlistAndSync() {
        let isolated = BrowserSettings(persistsAutomatically: false)
        XCTAssertFalse(isolated.isHostAllowlisted("example.com"))

        XCTAssertTrue(isolated.toggleHostAllowlist("  Example.COM "))
        XCTAssertTrue(isolated.isHostAllowlisted("example.com"))
        XCTAssertEqual(isolated.adBlockAllowlistedHosts, ["example.com"])

        let payload = AccountManager.shared.settingsPayload(from: isolated)
        XCTAssertEqual(payload["adBlockAllowlistedHosts"] as? [String], ["example.com"])

        XCTAssertFalse(isolated.toggleHostAllowlist("example.com"))
        XCTAssertFalse(isolated.isHostAllowlisted("example.com"))

        AccountManager.shared.applySettings([
            "adBlockAllowlistedHosts": ["Sub.Example.org", "docs.swift.org"],
            "updatedAt": 2000000000001
        ], to: isolated)
        XCTAssertTrue(isolated.isHostAllowlisted("sub.example.org"))
        XCTAssertTrue(isolated.isHostAllowlisted("docs.swift.org"))
    }

    func testFindInPageStateAndErrorMapping() {
        let session = BrowserSession(stateStore: TabStateStore(isPersistenceEnabled: false), restoresPreviousSession: false)
        // Home tab should not open find bar
        session.openFindBar()
        XCTAssertFalse(session.isShowingFindBar)

        _ = session.createTab(url: "https://example.com", select: true)
        session.openFindBar()
        XCTAssertTrue(session.isShowingFindBar)

        session.closeFindBar()
        XCTAssertFalse(session.isShowingFindBar)

        let cancelled = NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)
        XCTAssertNil(TabController.userFacingErrorMessage(for: cancelled))

        let offline = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        XCTAssertNotNil(TabController.userFacingErrorMessage(for: offline))
    }

    func testAccountManagerDeleteAccountClearsSession() async {
        let account = AccountManager(isPersistenceEnabled: false)
        let profile = UserProfile(id: "u_del_1", email: "del@youdroid.com", displayName: "DeleteMe")
        account.saveSession(token: "tok_del_123", profile: profile)
        XCTAssertTrue(account.isLoggedIn)

        let deleted = await account.deleteAccount()
        XCTAssertTrue(deleted)
        XCTAssertFalse(account.isLoggedIn)
        XCTAssertNil(account.currentUser)
        XCTAssertNil(account.token)
    }
}
