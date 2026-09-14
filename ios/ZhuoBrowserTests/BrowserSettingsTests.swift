import XCTest
@testable import ZhuoBrowser

final class BrowserSettingsTests: XCTestCase {
    func testDefaultsProtectFirstLaunchAndMatchHarmonyHomeLimits() {
        let settings = BrowserSettings()

        XCTAssertFalse(settings.privacyConsentAccepted)
        XCTAssertFalse(settings.onboardingCompleted)
        XCTAssertEqual(settings.customSearchTemplate, "")
        XCTAssertFalse(settings.searchSuggestionsEnabled)
        XCTAssertTrue(settings.gesturesEnabled)
        XCTAssertTrue(settings.gestureActionsEnabled)
        XCTAssertTrue(settings.gestureTabSwitchEnabled)
        XCTAssertTrue(settings.gestureBlockingEnabled)
        XCTAssertTrue(settings.autoHideToolbarEnabled)
        XCTAssertFalse(settings.telemetryEnabled)
        XCTAssertEqual(settings.appearance, .system)
        XCTAssertTrue(settings.quickSitesEnabled)
        XCTAssertEqual(settings.quickSiteLimit, 6)
        XCTAssertTrue(settings.homeBackgroundEnabled)
        XCTAssertEqual(settings.homeBackgroundStyle, .daily)
        XCTAssertEqual(settings.homePortraitPreset, .mountain)
        XCTAssertEqual(settings.homeLandscapePreset, .arch)
        XCTAssertEqual(settings.tabExpiry, .sevenDays)
        XCTAssertEqual(settings.historyRetention, .thirtyDays)
        XCTAssertEqual(settings.liveWebViewLimit, 4)
        XCTAssertEqual(settings.tabSoftLimit, 12)
        XCTAssertEqual(settings.downloadConcurrency, 2)
        XCTAssertEqual(settings.largeDownloadThresholdMB, 50)
        XCTAssertFalse(settings.wifiOnlyDownloads)
        XCTAssertFalse(settings.downloadNotificationsEnabled)
        XCTAssertFalse(settings.clearCookiesOnTabClose)
        XCTAssertEqual(settings.minimumFontSize, 14)
        XCTAssertEqual(settings.defaultUserAgentPreference, .default)
        XCTAssertEqual(settings.webDarkMode, .system)
        XCTAssertTrue(settings.siteUserAgentPreferences.isEmpty)
        XCTAssertTrue(settings.siteZoomRatios.isEmpty)
        XCTAssertTrue(settings.webDarkModeExcludedHosts.isEmpty)
        XCTAssertEqual(settings.ruleStrength, .standard)
        XCTAssertTrue(settings.siteControls.isEmpty)
        XCTAssertEqual(settings.rulesLastUpdatedAt, 0)
    }

    func testLegacySettingsDecodeWithSafeNewDefaults() throws {
        let data = #"{"searchEngine":1,"blockAds":false,"searchSuggestionsEnabled":false}"#.data(using: .utf8)!
        let settings = try JSONDecoder().decode(BrowserSettings.self, from: data)

        XCTAssertEqual(settings.searchEngine, .baidu)
        XCTAssertFalse(settings.blockAds)
        XCTAssertFalse(settings.searchSuggestionsEnabled)
        XCTAssertFalse(settings.privacyConsentAccepted)
        XCTAssertEqual(settings.customSearchTemplate, "")
        XCTAssertTrue(settings.gesturesEnabled)
        XCTAssertTrue(settings.gestureActionsEnabled)
        XCTAssertTrue(settings.gestureTabSwitchEnabled)
        XCTAssertTrue(settings.gestureBlockingEnabled)
        XCTAssertTrue(settings.autoHideToolbarEnabled)
        XCTAssertFalse(settings.telemetryEnabled)
        XCTAssertEqual(settings.homeBackgroundStyle, .daily)
        XCTAssertEqual(settings.homePortraitPreset, .mountain)
        XCTAssertEqual(settings.homeLandscapePreset, .arch)
        XCTAssertEqual(settings.tabExpiry, .sevenDays)
        XCTAssertEqual(settings.historyRetention, .thirtyDays)
        XCTAssertEqual(settings.downloadConcurrency, 2)
        XCTAssertEqual(settings.largeDownloadThresholdMB, 50)
        XCTAssertFalse(settings.clearCookiesOnTabClose)
        XCTAssertEqual(settings.minimumFontSize, 14)
        XCTAssertEqual(settings.defaultUserAgentPreference, .default)
        XCTAssertEqual(settings.webDarkMode, .system)
        XCTAssertEqual(settings.ruleStrength, .standard)
        XCTAssertTrue(settings.siteControls.isEmpty)
    }

    func testLegacySettingsWithoutSuggestionPreferenceUseHarmonyDefault() throws {
        let legacy = #"{"searchEngine":0}"#.data(using: .utf8)!
        let restored = try JSONDecoder().decode(BrowserSettings.self, from: legacy)
        XCTAssertFalse(restored.searchSuggestionsEnabled)

        let optedIn = #"{"searchSuggestionsEnabled":true}"#.data(using: .utf8)!
        let optedInSettings = try JSONDecoder().decode(BrowserSettings.self, from: optedIn)
        XCTAssertTrue(optedInSettings.searchSuggestionsEnabled)
    }

    func testQuickSiteLimitIsClampedDuringInitialization() {
        XCTAssertEqual(BrowserSettings(quickSiteLimit: 1).quickSiteLimit, 4)
        XCTAssertEqual(BrowserSettings(quickSiteLimit: 99).quickSiteLimit, 8)
    }

    func testSearchAndGestureSettingsRoundTrip() throws {
        let expected = BrowserSettings(
            customSearchTemplate: " https://search.example/?q=%s ",
            gesturesEnabled: false,
            gestureActionsEnabled: false,
            gestureTabSwitchEnabled: false,
            gestureBlockingEnabled: false,
            autoHideToolbarEnabled: false,
            telemetryEnabled: true
        )

        XCTAssertEqual(expected.customSearchTemplate, "https://search.example/?q=%s")
        let restored = try JSONDecoder().decode(
            BrowserSettings.self,
            from: JSONEncoder().encode(expected)
        )
        XCTAssertEqual(restored, expected)
        XCTAssertEqual(BrowserSettings(customSearchTemplate: "https://invalid.example").customSearchTemplate, "")
    }

    func testDailyAndCustomBackgroundStylesRoundTrip() throws {
        for style in [HomeBackgroundStyle.daily, .custom] {
            let expected = BrowserSettings(homeBackgroundStyle: style)
            let restored = try JSONDecoder().decode(
                BrowserSettings.self,
                from: JSONEncoder().encode(expected)
            )
            XCTAssertEqual(restored.homeBackgroundStyle, style)
        }
    }

    func testLegacySettingsWithoutBackgroundSourceUseHarmonyDailyDefault() throws {
        let legacy = #"{"homeBackgroundEnabled":true}"#.data(using: .utf8)!
        let restored = try JSONDecoder().decode(BrowserSettings.self, from: legacy)

        XCTAssertTrue(restored.homeBackgroundEnabled)
        XCTAssertEqual(restored.homeBackgroundStyle, .daily)
    }

    func testBackgroundEnablementPreservesSourceAndMigratesLegacyPlainStyle() throws {
        let disabled = BrowserSettings(
            homeBackgroundEnabled: false,
            homeBackgroundStyle: .daily,
            homePortraitPreset: .river,
            homeLandscapePreset: .wood
        )
        let restored = try JSONDecoder().decode(
            BrowserSettings.self,
            from: JSONEncoder().encode(disabled)
        )

        XCTAssertEqual(restored, disabled)
        XCTAssertFalse(restored.homeBackgroundEnabled)
        XCTAssertEqual(restored.homeBackgroundStyle, .daily)

        let legacyPlain = #"{"homeBackgroundStyle":0}"#.data(using: .utf8)!
        let migrated = try JSONDecoder().decode(BrowserSettings.self, from: legacyPlain)
        XCTAssertFalse(migrated.homeBackgroundEnabled)
        XCTAssertEqual(migrated.homeBackgroundStyle, .forest)
    }

    func testHomeBackgroundPresetsRoundTripAndMigrateLegacyStyles() throws {
        let expected = BrowserSettings(
            homeBackgroundStyle: .forest,
            homePortraitPreset: .river,
            homeLandscapePreset: .wood
        )
        let restored = try JSONDecoder().decode(
            BrowserSettings.self,
            from: JSONEncoder().encode(expected)
        )

        XCTAssertEqual(restored, expected)
        XCTAssertEqual(
            HomeBackgroundPresetPolicy.resourceName(
                portrait: restored.homePortraitPreset,
                landscape: restored.homeLandscapePreset,
                isLandscape: false
            ),
            "portrait-river"
        )
        XCTAssertEqual(
            HomeBackgroundPresetPolicy.resourceName(
                portrait: restored.homePortraitPreset,
                landscape: restored.homeLandscapePreset,
                isLandscape: true
            ),
            "landscape-wood"
        )
        XCTAssertEqual(
            HomeBackgroundPresetChoice.choices(isLandscape: false),
            [.portrait(.mountain), .portrait(.alley), .portrait(.river)]
        )
        XCTAssertEqual(
            HomeBackgroundPresetChoice.choices(isLandscape: true),
            [.landscape(.arch), .landscape(.roof), .landscape(.wood)]
        )
        XCTAssertTrue(HomeBackgroundPresetChoice.portrait(.river).isSelected(in: restored))
        XCTAssertTrue(HomeBackgroundPresetChoice.landscape(.wood).isSelected(in: restored))

        let legacy = #"{"homeBackgroundStyle":2}"#.data(using: .utf8)!
        let migrated = try JSONDecoder().decode(BrowserSettings.self, from: legacy)
        XCTAssertEqual(migrated.homeBackgroundStyle, .forest)
        XCTAssertEqual(migrated.homePortraitPreset, .alley)
        XCTAssertEqual(migrated.homeLandscapePreset, .roof)
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
            downloadNotificationsEnabled: true,
            clearCookiesOnTabClose: true,
            ruleStrength: .strict,
            siteControls: [SiteControl(
                host: "example.com",
                autoReader: .enabled,
                darkMode: .enabled,
                desktopUserAgent: .disabled
            )],
            rulesLastUpdatedAt: 1234
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

    func testWebAppearanceSettingsAreNormalizedAndRoundTrip() throws {
        let expected = BrowserSettings(
            minimumFontSize: 17,
            siteZoomRatios: [
                SiteZoomRatio(host: "Example.COM", percent: 127),
                SiteZoomRatio(host: "unchanged.example", percent: 100)
            ],
            defaultUserAgentPreference: .mobile,
            siteUserAgentPreferences: [
                SiteUserAgentPreference(host: "Example.COM", preference: .desktop),
                SiteUserAgentPreference(host: "ignored.example", preference: .default)
            ],
            webDarkMode: .dark,
            webDarkModeExcludedHosts: ["Example.COM", "example.com"]
        )

        XCTAssertEqual(expected.minimumFontSize, 16)
        XCTAssertEqual(expected.siteZoomRatios, [SiteZoomRatio(host: "example.com", percent: 125)])
        XCTAssertEqual(
            expected.siteUserAgentPreferences,
            [SiteUserAgentPreference(host: "example.com", preference: .desktop)]
        )
        XCTAssertEqual(expected.webDarkModeExcludedHosts, ["example.com"])

        let restored = try JSONDecoder().decode(
            BrowserSettings.self,
            from: JSONEncoder().encode(expected)
        )
        XCTAssertEqual(restored, expected)
    }

    func testWebAppearancePolicyResolvesSiteOverrides() {
        let settings = BrowserSettings(
            siteZoomRatios: [SiteZoomRatio(host: "example.com", percent: 150)],
            defaultUserAgentPreference: .mobile,
            siteUserAgentPreferences: [
                SiteUserAgentPreference(host: "example.com", preference: .desktop)
            ],
            webDarkMode: .dark,
            webDarkModeExcludedHosts: ["example.com"]
        )

        XCTAssertEqual(WebAppearancePolicy.host(for: "https://Example.com/a"), "example.com")
        XCTAssertTrue(WebAppearancePolicy.usesDesktopUserAgent(for: "https://example.com", settings: settings))
        XCTAssertFalse(WebAppearancePolicy.usesDesktopUserAgent(for: "https://other.example", settings: settings))
        XCTAssertEqual(WebAppearancePolicy.zoomPercent(for: "https://example.com/a", settings: settings), 150)
        XCTAssertTrue(WebAppearancePolicy.isDarkModeExcluded(for: "https://example.com", settings: settings))
    }
}
