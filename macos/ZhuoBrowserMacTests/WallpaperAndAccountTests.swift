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

        manager.selectBingWallpaper(date: "20261031")
        XCTAssertEqual(manager.source, .daily)
        XCTAssertEqual(manager.selectedBingDate, "20261031")

        manager.selectBingWallpaper(date: nil)
        XCTAssertEqual(manager.source, .daily)
        XCTAssertNil(manager.selectedBingDate)
    }

    func testBingServerWallpapersJSONParsingAndResolution() {
        let sampleJSON = """
        {
          "ok": true,
          "wallpapers": [
            {
              "date": "20261030",
              "startDate": "20261029",
              "title": "展翅高飞的时节",
              "copyright": "沙丘鹤，新墨西哥州",
              "imageUrl": "/api/wallpapers/bing/20261030?variant=full",
              "thumbnailUrl": "/api/wallpapers/bing/20261030?variant=thumb"
            },
            {
              "date": "20261101",
              "startDate": "20261031",
              "title": "林间迷雾",
              "copyright": "黑森林，德国",
              "imageUrl": "/api/wallpapers/bing/20261101?variant=full",
              "thumbnailUrl": "/api/wallpapers/bing/20261101?variant=thumb"
            }
          ]
        }
        """.data(using: .utf8)!

        let parsed = HomeBackgroundManager.parseServerWallpapersJSON(sampleJSON)
        XCTAssertEqual(parsed.count, 2)
        // Sorted descending by date
        XCTAssertEqual(parsed[0].date, "20261101")
        XCTAssertEqual(parsed[0].title, "林间迷雾")
        XCTAssertEqual(parsed[0].formattedShortDate, "11-01")
        XCTAssertEqual(parsed[0].formattedFullDate, "2026-11-01")
        XCTAssertEqual(
            parsed[0].resolvedImageURL?.absoluteString,
            "\(AccountManager.serverBaseURL)/api/wallpapers/bing/20261101?variant=full"
        )
        XCTAssertEqual(
            parsed[0].resolvedThumbnailURL?.absoluteString,
            "\(AccountManager.serverBaseURL)/api/wallpapers/bing/20261101?variant=thumb"
        )
        XCTAssertEqual(parsed[1].date, "20261030")
    }

    func testBingDirectArchiveJSONParsingFallback() {
        let archiveJSON = """
        {
          "images": [
            {
              "startdate": "20261031",
              "enddate": "20261101",
              "url": "/th?id=OHR.SchwarzwaldAutumn_ZH-CN6323627599_1920x1080.jpg&rf=LaDigue_1920x1080.jpg&pid=hp",
              "urlbase": "/th?id=OHR.SchwarzwaldAutumn_ZH-CN6323627599",
              "copyright": "黑森林，德国",
              "title": "林间迷雾"
            }
          ]
        }
        """.data(using: .utf8)!

        let parsed = HomeBackgroundManager.parseBingArchiveJSON(archiveJSON)
        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed[0].date, "20261101")
        XCTAssertEqual(parsed[0].title, "林间迷雾")
        XCTAssertEqual(
            parsed[0].resolvedImageURL?.absoluteString,
            "https://www.bing.com/th?id=OHR.SchwarzwaldAutumn_ZH-CN6323627599_1920x1080.jpg"
        )
        XCTAssertEqual(
            parsed[0].resolvedThumbnailURL?.absoluteString,
            "https://www.bing.com/th?id=OHR.SchwarzwaldAutumn_ZH-CN6323627599_400x240.jpg"
        )
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
        let userA = UserProfile(id: "123", email: "user@test.com", displayName: "Test User", avatarUrl: "/api/user/avatar/123")
        let userB = UserProfile(id: "123", email: "user@test.com", displayName: "Test User", avatarUrl: "/api/user/avatar/123")
        let userC = UserProfile(id: "456", email: "other@test.com", displayName: "Other")

        XCTAssertEqual(userA, userB)
        XCTAssertNotEqual(userA, userC)
    }

    func testUserProfileAvatarURLResolution() {
        let relativeUser = UserProfile(id: "123", email: "u@test.com", displayName: "User", avatarUrl: "/api/user/avatar/123")
        XCTAssertNotNil(relativeUser.resolvedAvatarURL)
        XCTAssertTrue(relativeUser.resolvedAvatarURL?.absoluteString.hasPrefix("https://") == true)
        XCTAssertTrue(relativeUser.resolvedAvatarURL?.absoluteString.contains("/api/user/avatar/123") == true)

        let absoluteUser = UserProfile(id: "123", email: "u@test.com", displayName: "User", avatarUrl: "https://example.com/avatar.jpg")
        XCTAssertEqual(absoluteUser.resolvedAvatarURL?.absoluteString, "https://example.com/avatar.jpg")

        let nilUser = UserProfile(id: "123", email: "u@test.com", displayName: "User", avatarUrl: nil)
        XCTAssertNil(nilUser.resolvedAvatarURL)
    }

    func testUserProfileCodableWithAvatarUrl() throws {
        let profile = UserProfile(id: "u1", email: "test@domain.com", displayName: "Tester", avatarUrl: "/api/user/avatar/u1")
        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(UserProfile.self, from: data)

        XCTAssertEqual(decoded.id, "u1")
        XCTAssertEqual(decoded.email, "test@domain.com")
        XCTAssertEqual(decoded.displayName, "Tester")
        XCTAssertEqual(decoded.avatarUrl, "/api/user/avatar/u1")
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

    func testClearWebsiteDataCompletes() {
        let session = BrowserSession()
        let expectation = expectation(description: "clearWebsiteData completion")
        session.clearWebsiteData(clearCookies: true, clearCache: true) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5.0)
    }

    func testAccountSessionPersistsAndRestoresAcrossReload() {
        let account = AccountManager.shared
        let profile = UserProfile(
            id: "user_persist_1",
            email: "persist@youdroid.com",
            displayName: "Persist User",
            avatarUrl: "/api/user/avatar/user_persist_1"
        )
        account.saveSession(token: "tok_persist_abc", profile: profile)
        XCTAssertTrue(account.isLoggedIn)
        XCTAssertEqual(account.token, "tok_persist_abc")
        XCTAssertEqual(account.currentUser, profile)

        // Simulate relaunching the app where Keychain fails after re-signing and fallback storage restores the session.
        KeychainHelper.deleteToken()
        account.reloadStoredSession()
        XCTAssertTrue(account.isLoggedIn)
        XCTAssertEqual(account.token, "tok_persist_abc")
        XCTAssertEqual(account.currentUser, profile)

        account.logout()
        XCTAssertFalse(account.isLoggedIn)
    }
}
