import XCTest
@testable import ZhuoBrowserMac

@MainActor
final class CrossPlatformSyncAndAuthTests: XCTestCase {

    func testGoogleSignInRegionGating() {
        XCTAssertFalse(RegionAuthPolicy.isGoogleSignInAvailable(regionCode: "CN", timeZoneIdentifier: "Asia/Shanghai"))
        XCTAssertFalse(RegionAuthPolicy.isGoogleSignInAvailable(regionCode: "cn", timeZoneIdentifier: "America/New_York"))
        XCTAssertTrue(RegionAuthPolicy.isGoogleSignInAvailable(regionCode: "HK", timeZoneIdentifier: "Asia/Shanghai"))
        XCTAssertTrue(RegionAuthPolicy.isGoogleSignInAvailable(regionCode: "TW", timeZoneIdentifier: "Asia/Shanghai"))
        XCTAssertTrue(RegionAuthPolicy.isGoogleSignInAvailable(regionCode: "US", timeZoneIdentifier: "America/Los_Angeles"))
        XCTAssertFalse(RegionAuthPolicy.isGoogleSignInAvailable(regionCode: nil, timeZoneIdentifier: "Asia/Shanghai"))
        XCTAssertTrue(RegionAuthPolicy.isGoogleSignInAvailable(regionCode: nil, timeZoneIdentifier: "America/Los_Angeles"))

        let cnProviders = RegionAuthPolicy.availableProviders(regionCode: "CN", timeZoneIdentifier: "Asia/Shanghai")
        XCTAssertTrue(cnProviders.contains(.apple))
        XCTAssertFalse(cnProviders.contains(.google))

        let sgProviders = RegionAuthPolicy.availableProviders(regionCode: "SG", timeZoneIdentifier: "Asia/Singapore")
        XCTAssertTrue(sgProviders.contains(.apple))
        XCTAssertTrue(sgProviders.contains(.google))
    }

    func testSupersetBookmarkPayloadRoundTripAndTimestampNormalization() {
        let folder = BookmarkFolder(id: "f-work", name: "工作", createdAt: 1_760_000_000, updatedAt: 1_760_000_100, sortOrder: 0)
        let entry = BookmarkEntry(
            id: "b-1",
            title: "稍后读文章",
            url: "https://example.com/read",
            folderID: "f-work",
            createdAt: 1_760_000_000,
            updatedAt: 1_760_000_200,
            isRead: false,
            tags: ["swift", "sync"],
            isPinnedToStartPage: false
        )
        let tombstone = BookmarkTombstone(id: "b-del", url: "https://example.com/old", isFolder: false, deletedAt: 1_760_000_300)

        let payload = LibraryPolicy.encodeBookmarksPayload(folders: [folder], bookmarks: [entry], tombstones: [tombstone])
        XCTAssertEqual(payload["version"] as? Int, 3)

        let parsed = LibraryPolicy.parseRemoteBookmarksPayload(payload)
        XCTAssertEqual(parsed.folders.count, 1)
        XCTAssertEqual(parsed.bookmarks.count, 1)
        XCTAssertEqual(parsed.bookmarks[0].isRead, false)
        XCTAssertEqual(parsed.bookmarks[0].tags, ["swift", "sync"])
        XCTAssertEqual(parsed.bookmarks[0].folderID, "f-work")
        XCTAssertEqual(parsed.bookmarks[0].updatedAt, 1_760_000_200, accuracy: 0.001)
        XCTAssertEqual(parsed.tombstones.count, 1)
        XCTAssertEqual(parsed.tombstones[0].deletedAt, 1_760_000_300, accuracy: 0.001)
    }

    func testSanitizeDeviceTabsExcludesPrivateAndInternalPages() {
        let tabs = [
            BrowserTab(url: "zhuo://home", title: "起始页", isPrivate: false),
            BrowserTab(url: "https://secret.example", title: "无痕", isPrivate: true),
            BrowserTab(url: "https://developer.apple.com", title: "Apple Dev", isPrivate: false),
            BrowserTab(url: "https://developer.apple.com/", title: "Dup", isPrivate: false)
        ]
        let sanitized = RegionAuthPolicy.sanitizeDeviceTabs(tabs)
        XCTAssertEqual(sanitized.count, 1)
        XCTAssertEqual(sanitized[0]["url"] as? String, "https://developer.apple.com")
    }

    func testCrossPlatformSettingsProjectionExcludesDesktopBudget() {
        let account = AccountManager(isPersistenceEnabled: false)
        let settings = BrowserSettings(persistsAutomatically: false)
        settings.liveWebViewBudget = 2
        settings.adBlockEnabled = false
        settings.searchEngine = .google

        let payload = account.crossPlatformSettingsPayload(from: settings)
        XCTAssertNil(payload["liveWebViewBudget"])
        XCTAssertEqual(payload["adBlockEnabled"] as? Bool, false)
        XCTAssertEqual(payload["searchEngine"] as? String, "Google")

        let otherSettings = BrowserSettings(persistsAutomatically: false)
        otherSettings.liveWebViewBudget = 4
        account.applyRemoteSyncSettings([
            "adBlockEnabled": false,
            "liveWebViewBudget": 1,
            "searchEngine": "DuckDuckGo",
            "updatedAt": Int64(Date().timeIntervalSince1970 * 1000)
        ], to: otherSettings)

        XCTAssertEqual(otherSettings.liveWebViewBudget, 4)
        XCTAssertFalse(otherSettings.adBlockEnabled)
        XCTAssertEqual(otherSettings.searchEngine, .duckDuckGo)
    }
}
