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
    }

    func testLegacySettingsDecodeWithSafeNewDefaults() throws {
        let data = #"{"searchEngine":1,"blockAds":false,"searchSuggestionsEnabled":false}"#.data(using: .utf8)!
        let settings = try JSONDecoder().decode(BrowserSettings.self, from: data)

        XCTAssertEqual(settings.searchEngine, .baidu)
        XCTAssertFalse(settings.blockAds)
        XCTAssertFalse(settings.privacyConsentAccepted)
        XCTAssertEqual(settings.homeBackgroundStyle, .forest)
    }

    func testQuickSiteLimitIsClampedDuringInitialization() {
        XCTAssertEqual(BrowserSettings(quickSiteLimit: 1).quickSiteLimit, 4)
        XCTAssertEqual(BrowserSettings(quickSiteLimit: 99).quickSiteLimit, 8)
    }
}
