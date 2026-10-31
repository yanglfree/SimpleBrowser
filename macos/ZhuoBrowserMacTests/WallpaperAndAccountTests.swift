import XCTest
@testable import ZhuoBrowserMac

@MainActor
final class WallpaperAndAccountTests: XCTestCase {

    func testWallpaperPresetsList() {
        let presets = HomeBackgroundManager.presets
        XCTAssertEqual(presets.count, 5)
        XCTAssertTrue(presets.contains(where: { $0.id == "arch" }))
        XCTAssertTrue(presets.contains(where: { $0.id == "roof" }))
        XCTAssertTrue(presets.contains(where: { $0.id == "wood" }))
        XCTAssertTrue(presets.contains(where: { $0.id == "mountain" }))
        XCTAssertTrue(presets.contains(where: { $0.id == "alley" }))
    }

    func testWallpaperSourceSwitching() {
        let manager = HomeBackgroundManager.shared
        manager.setSource(.none)
        XCTAssertEqual(manager.source, .none)
        XCTAssertNil(manager.currentImage)

        manager.setSource(.preset)
        XCTAssertEqual(manager.source, .preset)

        manager.selectPreset(id: "roof")
        XCTAssertEqual(manager.selectedPresetId, "roof")
        XCTAssertEqual(manager.source, .preset)
    }

    func testAccountManagerInitialStateAndLogout() {
        let account = AccountManager.shared
        XCTAssertFalse(AccountManager.serverBaseURL.isEmpty)
        XCTAssertTrue(AccountManager.serverBaseURL.hasPrefix("https://"))

        // Test logout resets states cleanly
        account.logout()
        XCTAssertFalse(account.isLoggedIn)
        XCTAssertNil(account.currentUser)
        XCTAssertNil(account.token)
        XCTAssertNil(account.syncErrorMessage)
    }

    func testKeychainHelperTokenStorage() {
        let sampleToken = "test_token_\(UUID().uuidString)"
        let saved = KeychainHelper.saveToken(sampleToken)
        if saved {
            XCTAssertEqual(KeychainHelper.loadToken(), sampleToken)
            KeychainHelper.deleteToken()
            XCTAssertNil(KeychainHelper.loadToken())
        }
    }

    func testAccountManagerApplySettings() {
        let account = AccountManager.shared
        let settings = BrowserSettings.shared

        let payload: [String: Any] = [
            "adBlockEnabled": false,
            "cosmeticCleanupEnabled": false,
            "liveWebViewBudget": 1,
            "searchEngine": SearchEngine.google.rawValue
        ]

        account.applySettings(payload, to: settings)

        XCTAssertFalse(settings.adBlockEnabled)
        XCTAssertFalse(settings.cosmeticCleanupEnabled)
        XCTAssertEqual(settings.liveWebViewBudget, 1)
        XCTAssertEqual(settings.searchEngine, .google)

        // Restore defaults
        settings.adBlockEnabled = true
        settings.cosmeticCleanupEnabled = true
        settings.liveWebViewBudget = 2
        settings.searchEngine = .bing
    }

    func testUserProfileEquality() {
        let userA = UserProfile(id: "123", email: "user@test.com", displayName: "Test User")
        let userB = UserProfile(id: "123", email: "user@test.com", displayName: "Test User")
        let userC = UserProfile(id: "456", email: "other@test.com", displayName: "Other")

        XCTAssertEqual(userA, userB)
        XCTAssertNotEqual(userA, userC)
    }

    func testDoubleClickAreaCreatesNewTab() {
        let session = BrowserSession()
        let initialCount = session.tabs.count

        // Simulate new tab triggered from double click empty space
        let newTab = session.createTab()
        XCTAssertEqual(session.tabs.count, initialCount + 1)
        XCTAssertEqual(session.activeTabID, newTab.id)
        XCTAssertTrue(newTab.isHome)
    }
}
