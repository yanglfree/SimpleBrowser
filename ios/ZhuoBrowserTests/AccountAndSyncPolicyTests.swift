import XCTest
@testable import ZhuoBrowser

final class AccountAndSyncPolicyTests: XCTestCase {

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
    }

    func testSupersetBookmarkMergePreservesFoldersReadLaterTagsAndTombstones() {
        let now: TimeInterval = 1_765_000_000
        let localFolder = BookmarkFolder(id: "f1", name: "阅读", createdAt: 1_760_000_000, updatedAt: 1_760_000_050, sortOrder: 0)
        let localItem = SavedItem(
            id: "i1",
            title: "Local",
            url: "https://example.com/post/",
            folderID: "f1",
            createdAt: 1_760_000_000,
            updatedAt: 1_760_000_100,
            isRead: false,
            tags: ["ios"]
        )
        let deletedItem = SavedItem(
            id: "i-del",
            title: "Deleted",
            url: "https://example.com/del",
            createdAt: 1_760_000_000,
            updatedAt: 1_760_000_050
        )

        let remotePayload: [String: Any] = [
            "version": 3,
            "folders": [[
                "id": "f1",
                "name": "深度阅读",
                "createdAt": Int64(1_760_000_000_000),
                "updatedAt": Int64(1_760_000_200_000),
                "sortOrder": 0,
                "isPinnedToStartPage": true
            ]],
            "items": [[
                "id": "i1",
                "title": "Updated Title",
                "url": "https://example.com/post",
                "folderId": "f1",
                "createdAt": Int64(1_760_000_000_000),
                "updatedAt": Int64(1_760_000_300_000),
                "isRead": false,
                "tags": ["ios", "mac"]
            ]],
            "tombstones": [[
                "id": "i-del",
                "url": "https://example.com/del",
                "isFolder": false,
                "deletedAt": Int64(1_760_000_200_000)
            ]]
        ]

        let parsed = CloudSyncEngine.parseBookmarksPayload(remotePayload)
        let merged = CloudSyncEngine.mergeBookmarks(
            localFolders: [localFolder],
            localItems: [localItem, deletedItem],
            localTombstones: [],
            remoteFolders: parsed.folders,
            remoteItems: parsed.items,
            remoteTombstones: parsed.tombstones,
            now: now
        )

        XCTAssertEqual(merged.folders.count, 1)
        XCTAssertEqual(merged.folders[0].name, "深度阅读")
        XCTAssertEqual(merged.items.count, 1)
        XCTAssertEqual(merged.items[0].title, "Updated Title")
        XCTAssertEqual(merged.items[0].isRead, false)
        XCTAssertEqual(merged.items[0].tags, ["ios", "mac"])
        XCTAssertEqual(merged.tombstones.count, 1)
    }

    func testSanitizeDeviceTabsDropsPrivateAndHome() {
        let home = BrowserTab.home(isPrivate: false)
        var priv = BrowserTab.home(isPrivate: true)
        priv.url = "https://private.test"
        priv.title = "无痕"
        var pub = BrowserTab.home(isPrivate: false)
        pub.url = "https://swift.org"
        pub.title = "Swift"
        let clean = RegionAuthPolicy.sanitizeDeviceTabs([home, priv, pub])
        XCTAssertEqual(clean.count, 1)
        XCTAssertEqual(clean[0]["url"] as? String, "https://swift.org")
    }

    func testMergeArticlesMetaCombinesHighlightsAndReadingPosition() {
        let local = SavedArticle(
            id: "a1",
            sourceUrl: "https://news.test/1",
            canonicalUrl: "https://news.test/1",
            title: "News",
            author: "",
            excerpt: "",
            searchText: "",
            createdAt: 1_760_000_000,
            updatedAt: 1_760_000_100,
            readingPosition: 0.35,
            highlights: [ArticleHighlight(id: "h1", quote: "one", prefix: "", suffix: "", createdAt: 1_760_000_050)],
            quality: .complete
        )
        let remote: [[String: Any]] = [[
            "id": "a1",
            "sourceUrl": "https://news.test/1",
            "canonicalUrl": "https://news.test/1/",
            "title": "News",
            "readingPosition": 0.72,
            "createdAt": Int64(1_760_000_000_000),
            "updatedAt": Int64(1_760_000_250_000),
            "highlights": [[
                "id": "h2",
                "quote": "two",
                "prefixContext": "",
                "suffixContext": "",
                "createdAt": Int64(1_760_000_200_000)
            ]],
            "notes": [[
                "id": "n1",
                "content": "Note 1",
                "createdAt": Int64(1_760_000_200_000),
                "updatedAt": Int64(1_760_000_200_000)
            ]]
        ]]

        let merged = CloudSyncEngine.mergeArticlesMetadata(local: [local], remoteDicts: remote, tombstones: [])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].readingPosition, 0.72, accuracy: 0.001)
        XCTAssertEqual(merged[0].highlights.count, 2)
        XCTAssertEqual(merged[0].notes.count, 1)
    }
}
