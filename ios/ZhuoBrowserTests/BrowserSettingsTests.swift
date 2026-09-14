import XCTest
@testable import ZhuoBrowser

final class BrowserSettingsTests: XCTestCase {
    func testDefaultsProtectFirstLaunchAndMatchHarmonyHomeLimits() {
        let settings = BrowserSettings()

        XCTAssertFalse(settings.privacyConsentAccepted)
        XCTAssertFalse(settings.onboardingCompleted)
        XCTAssertEqual(settings.appearance, .system)
        XCTAssertTrue(settings.quickSitesEnabled)
        XCTAssertEqual(settings.quickSiteLimit, 6)
        XCTAssertEqual(settings.tabExpiry, .sevenDays)
        XCTAssertEqual(settings.historyRetention, .thirtyDays)
        XCTAssertEqual(settings.liveWebViewLimit, 4)
        XCTAssertEqual(settings.tabSoftLimit, 12)
        XCTAssertEqual(settings.downloadConcurrency, 2)
        XCTAssertEqual(settings.largeDownloadThresholdMB, 50)
        XCTAssertFalse(settings.wifiOnlyDownloads)
        XCTAssertFalse(settings.downloadNotificationsEnabled)
    }

    func testLegacySettingsDecodeWithSafeNewDefaults() throws {
        let data = #"{"searchEngine":1,"blockAds":false,"searchSuggestionsEnabled":false}"#.data(using: .utf8)!
        let settings = try JSONDecoder().decode(BrowserSettings.self, from: data)

        XCTAssertEqual(settings.searchEngine, .baidu)
        XCTAssertFalse(settings.blockAds)
        XCTAssertFalse(settings.privacyConsentAccepted)
        XCTAssertEqual(settings.homeBackgroundStyle, .forest)
        XCTAssertEqual(settings.tabExpiry, .sevenDays)
        XCTAssertEqual(settings.historyRetention, .thirtyDays)
        XCTAssertEqual(settings.downloadConcurrency, 2)
        XCTAssertEqual(settings.largeDownloadThresholdMB, 50)
    }

    func testQuickSiteLimitIsClampedDuringInitialization() {
        XCTAssertEqual(BrowserSettings(quickSiteLimit: 1).quickSiteLimit, 4)
        XCTAssertEqual(BrowserSettings(quickSiteLimit: 99).quickSiteLimit, 8)
    }

    func testTabResourceSettingsUseSupportedValues() {
        XCTAssertEqual(BrowserSettings(liveWebViewLimit: 3).liveWebViewLimit, 4)
        XCTAssertEqual(BrowserSettings(liveWebViewLimit: 99).liveWebViewLimit, 6)
        XCTAssertEqual(BrowserSettings(tabSoftLimit: 9).tabSoftLimit, 12)
        XCTAssertEqual(BrowserSettings(tabSoftLimit: 99).tabSoftLimit, 40)
    }

    func testSessionSettingsRoundTrip() throws {
        let expected = BrowserSettings(
            tabExpiry: .threeDays,
            historyRetention: .sevenDays,
            liveWebViewLimit: 2,
            tabSoftLimit: 20,
            downloadConcurrency: 5,
            largeDownloadThresholdMB: 125,
            wifiOnlyDownloads: true,
            downloadNotificationsEnabled: true
        )

        let restored = try JSONDecoder().decode(
            BrowserSettings.self,
            from: JSONEncoder().encode(expected)
        )

        XCTAssertEqual(restored, expected)
    }

    func testDownloadSettingsAreClamped() {
        XCTAssertEqual(BrowserSettings(downloadConcurrency: 0).downloadConcurrency, 1)
        XCTAssertEqual(BrowserSettings(downloadConcurrency: 99).downloadConcurrency, 6)
        XCTAssertEqual(BrowserSettings(largeDownloadThresholdMB: 0).largeDownloadThresholdMB, 1)
        XCTAssertEqual(BrowserSettings(largeDownloadThresholdMB: 2_000).largeDownloadThresholdMB, 1_024)
    }
}
