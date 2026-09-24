import XCTest
@testable import ZhuoBrowserMac

final class LibraryTests: XCTestCase {

    // MARK: - Bookmarks Tests

    func testAddBookmarkAndDeduplication() {
        var bookmarks: [BookmarkEntry] = []

        bookmarks = LibraryPolicy.addBookmark(bookmarks, url: "https://github.com", title: "GitHub")
        XCTAssertEqual(bookmarks.count, 1)
        XCTAssertEqual(bookmarks.first?.title, "GitHub")
        XCTAssertEqual(bookmarks.first?.url, "https://github.com")

        // Adding same URL updates/moves it to top without duplication
        bookmarks = LibraryPolicy.addBookmark(bookmarks, url: "https://github.com", title: "GitHub Official")
        XCTAssertEqual(bookmarks.count, 1)
        XCTAssertEqual(bookmarks.first?.title, "GitHub Official")
    }

    func testBookmarkRemovalAndEditing() {
        var bookmarks: [BookmarkEntry] = []
        bookmarks = LibraryPolicy.addBookmark(bookmarks, url: "https://apple.com", title: "Apple")
        let bookmarkID = bookmarks.first!.id

        // Edit
        bookmarks = LibraryPolicy.updateBookmark(bookmarks, id: bookmarkID, title: "Apple Inc.", url: "https://apple.com/cn")
        XCTAssertEqual(bookmarks.first?.title, "Apple Inc.")
        XCTAssertEqual(bookmarks.first?.url, "https://apple.com/cn")

        // Remove by ID
        bookmarks = LibraryPolicy.removeBookmark(bookmarks, id: bookmarkID)
        XCTAssertTrue(bookmarks.isEmpty)
    }

    func testIsBookmarked() {
        var bookmarks: [BookmarkEntry] = []
        XCTAssertFalse(LibraryPolicy.isBookmarked(bookmarks, url: "https://v2ex.com"))

        bookmarks = LibraryPolicy.addBookmark(bookmarks, url: "https://v2ex.com", title: "V2EX")
        XCTAssertTrue(LibraryPolicy.isBookmarked(bookmarks, url: "https://v2ex.com"))
        XCTAssertFalse(LibraryPolicy.isBookmarked(bookmarks, url: "zhuo://home"))
    }

    func testMaxBookmarkCapacity() {
        var bookmarks: [BookmarkEntry] = []
        for i in 1...350 {
            bookmarks = LibraryPolicy.addBookmark(bookmarks, url: "https://site\(i).com", title: "Site \(i)")
        }
        XCTAssertLessThanOrEqual(bookmarks.count, LibraryPolicy.maxBookmarkCount)
    }

    // MARK: - History Tests

    func testRecordHistoryBumpsVisitCount() {
        var history: [HistoryEntry] = []

        history = LibraryPolicy.recordHistory(history, url: "https://news.ycombinator.com", title: "Hacker News")
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.first?.visitCount, 1)

        // Visit again
        history = LibraryPolicy.recordHistory(history, url: "https://news.ycombinator.com", title: "Hacker News (New)")
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.first?.visitCount, 2)
        XCTAssertEqual(history.first?.title, "Hacker News (New)")
    }

    func testHistoryIgnoredForHomeURL() {
        var history: [HistoryEntry] = []
        history = LibraryPolicy.recordHistory(history, url: "zhuo://home", title: "新标签页")
        XCTAssertTrue(history.isEmpty)

        history = LibraryPolicy.recordHistory(history, url: "", title: "")
        XCTAssertTrue(history.isEmpty)
    }

    func testRemoveHistoryItem() {
        var history: [HistoryEntry] = []
        history = LibraryPolicy.recordHistory(history, url: "https://a.com", title: "A")
        history = LibraryPolicy.recordHistory(history, url: "https://b.com", title: "B")
        XCTAssertEqual(history.count, 2)

        let aID = history.first(where: { $0.url == "https://a.com" })!.id
        history = LibraryPolicy.removeHistoryItem(history, id: aID)
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.first?.url, "https://b.com")
    }

    func testMaxHistoryCapacity() {
        var history: [HistoryEntry] = []
        for i in 1...550 {
            history = LibraryPolicy.recordHistory(history, url: "https://page\(i).com", title: "Page \(i)")
        }
        XCTAssertLessThanOrEqual(history.count, LibraryPolicy.maxHistoryCount)
    }

    // MARK: - Session Integration Tests

    @MainActor
    func testSessionBookmarkToggle() {
        let session = BrowserSession()
        session.navigate(to: "https://example.org")

        XCTAssertFalse(session.isBookmarked(url: "https://example.org"))

        // Toggle on
        session.toggleBookmarkForActiveTab()
        XCTAssertTrue(session.isBookmarked(url: "https://example.org"))

        // Toggle off
        session.toggleBookmarkForActiveTab()
        XCTAssertFalse(session.isBookmarked(url: "https://example.org"))
    }
}
