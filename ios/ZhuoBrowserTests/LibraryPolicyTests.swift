import XCTest
@testable import ZhuoBrowser

final class LibraryPolicyTests: XCTestCase {
    func testLegacySavedItemDefaultsToReadWithoutTags() throws {
        let data = #"{"id":"saved-1","title":"Example","url":"https://example.com","createdAt":1,"updatedAt":2}"#
            .data(using: .utf8)!

        let item = try JSONDecoder().decode(SavedItem.self, from: data)

        XCTAssertTrue(item.isRead)
        XCTAssertEqual(item.tags, [])
    }

    func testSavedItemReadStateAndTagsRoundTrip() throws {
        let expected = makeSavedItem(isRead: false)

        let restored = try JSONDecoder().decode(
            SavedItem.self,
            from: JSONEncoder().encode(expected)
        )

        XCTAssertEqual(restored, expected)
    }

    func testSaveForLaterAndVisitShareOneSavedItem() {
        let original = makeSavedItem(isRead: true)

        let unread = LibraryPolicy.saveForLater(
            [original],
            url: original.url,
            title: "Ignored",
            updatedAt: 20
        )
        let read = LibraryPolicy.markSavedItemRead(unread, url: original.url, updatedAt: 30)

        XCTAssertEqual(unread.count, 1)
        XCTAssertFalse(unread[0].isRead)
        XCTAssertEqual(unread[0].title, original.title)
        XCTAssertTrue(read[0].isRead)
        XCTAssertEqual(read[0].updatedAt, 30)
    }

    func testRenameRejectsWhitespaceAndPreservesMetadata() {
        let original = makeSavedItem(isRead: false)

        XCTAssertEqual(LibraryPolicy.renameSavedItem([original], id: original.id, title: "   "), [original])

        let renamed = LibraryPolicy.renameSavedItem(
            [original],
            id: original.id,
            title: "  Renamed  ",
            updatedAt: 50
        )[0]
        XCTAssertEqual(renamed.title, "Renamed")
        XCTAssertFalse(renamed.isRead)
        XCTAssertEqual(renamed.tags, original.tags)
        XCTAssertEqual(renamed.updatedAt, 50)
    }

    func testHistoryRetentionAndHostDeletionUseRealHosts() {
        let now: TimeInterval = 1_000_000
        let recent = makeHistory(id: "recent", url: "https://example.com/new", visitedAt: now - 60)
        let old = makeHistory(id: "old", url: "https://example.com/old", visitedAt: now - 8 * 86_400)
        let other = makeHistory(id: "other", url: "https://example.org", visitedAt: now - 120)

        XCTAssertEqual(
            LibraryPolicy.applyingHistoryRetention([recent, old, other], retentionDays: 7, now: now).map(\.id),
            ["recent", "other"]
        )
        XCTAssertEqual(
            LibraryPolicy.removeHistoryForHost([recent, other], host: "EXAMPLE.COM").map(\.id),
            ["other"]
        )
    }

    func testHistorySearchMergesBookmarksAndDeduplicatesURLs() {
        let bookmark = makeSavedItem(title: "Swift Guide")
        let duplicate = makeHistory(id: "duplicate", url: bookmark.url, visitedAt: 20)
        let history = makeHistory(id: "history", url: "https://swift.org", visitedAt: 30)

        let results = LibraryPolicy.searchHistoryAndBookmarks(
            query: "swift",
            history: [duplicate, history],
            savedItems: [bookmark]
        )

        XCTAssertEqual(results.map(\.kind), [.bookmark, .history])
        XCTAssertEqual(Set(results.map(\.url)).count, 2)
    }

    func testImportedBookmarksAppendWithoutReplacingExistingURLs() {
        let existing = makeSavedItem()
        let duplicate = makeSavedItem(id: "duplicate")
        let imported = makeSavedItem(id: "imported", title: "Imported", url: "https://imported.example")

        let result = LibraryPolicy.mergeSavedItems([existing], imported: [duplicate, imported])

        XCTAssertEqual(result.importedCount, 1)
        XCTAssertEqual(result.items.map(\.id), [existing.id, imported.id])
    }

    private func makeSavedItem(
        id: String = "saved-1",
        title: String = "Example",
        url: String = "https://example.com",
        isRead: Bool = true
    ) -> SavedItem {
        SavedItem(
            id: id,
            title: title,
            url: url,
            createdAt: 1,
            updatedAt: 2,
            isRead: isRead,
            tags: ["reference"]
        )
    }

    private func makeHistory(id: String, url: String, visitedAt: TimeInterval) -> HistoryEntry {
        HistoryEntry(id: id, title: url, url: url, visitedAt: visitedAt, visitCount: 1)
    }
}
