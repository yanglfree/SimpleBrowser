import AppKit
import SwiftUI
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

    // MARK: - Bookmark Folders, Moving, Batch Operations, and Sorting Tests

    func testFolderCreationRenameReorderAndRemoval() {
        var folders: [BookmarkFolder] = []
        var bookmarks: [BookmarkEntry] = []

        folders = LibraryPolicy.createFolder(folders, name: "阅读清单")
        folders = LibraryPolicy.createFolder(folders, name: "AI 工具")
        XCTAssertEqual(folders.count, 2)
        // Duplicate folder name should not create a duplicate
        folders = LibraryPolicy.createFolder(folders, name: "阅读清单")
        XCTAssertEqual(folders.count, 2)

        let readingID = folders[0].id
        let aiID = folders[1].id

        // Rename folder
        folders = LibraryPolicy.renameFolder(folders, id: readingID, newName: "深度阅读")
        XCTAssertEqual(folders.first(where: { $0.id == readingID })?.name, "深度阅读")

        // Reorder folders
        folders = LibraryPolicy.moveFolder(folders, id: aiID, direction: -1)
        XCTAssertEqual(folders[0].id, aiID)
        XCTAssertEqual(folders[1].id, readingID)

        // Add bookmarks into both folders
        bookmarks = LibraryPolicy.addBookmark(bookmarks, url: "https://openai.com", title: "OpenAI", folderID: aiID)
        bookmarks = LibraryPolicy.addBookmark(bookmarks, url: "https://paulgraham.com", title: "Paul Graham", folderID: readingID)
        XCTAssertEqual(LibraryPolicy.bookmarks(inFolderID: aiID, from: bookmarks).count, 1)
        XCTAssertEqual(LibraryPolicy.bookmarks(inFolderID: readingID, from: bookmarks).count, 1)

        // Remove folder while keeping contained bookmarks in ungrouped (folderID == nil)
        let keptResult = LibraryPolicy.removeFolder(folders, bookmarks: bookmarks, folderID: aiID, deleteContainedBookmarks: false)
        folders = keptResult.folders
        bookmarks = keptResult.bookmarks
        XCTAssertEqual(folders.count, 1)
        XCTAssertEqual(bookmarks.count, 2)
        let openAIBookmark = bookmarks.first(where: { $0.url == "https://openai.com" })
        XCTAssertNil(openAIBookmark?.folderID)
        XCTAssertEqual(openAIBookmark?.isPinnedToStartPage, true)

        // Remove folder and delete contained bookmarks
        let deletedResult = LibraryPolicy.removeFolder(folders, bookmarks: bookmarks, folderID: readingID, deleteContainedBookmarks: true)
        folders = deletedResult.folders
        bookmarks = deletedResult.bookmarks
        XCTAssertTrue(folders.isEmpty)
        XCTAssertEqual(bookmarks.count, 1)
        XCTAssertEqual(bookmarks.first?.url, "https://openai.com")
    }

    func testMoveSingleAndBatchBookmarksBetweenFolders() {
        let folderA = BookmarkFolder(id: "folder-a", name: "Folder A")
        let folderB = BookmarkFolder(id: "folder-b", name: "Folder B")

        var bookmarks: [BookmarkEntry] = []
        bookmarks = LibraryPolicy.addBookmark(bookmarks, url: "https://one.com", title: "One", folderID: folderA.id)
        bookmarks = LibraryPolicy.addBookmark(bookmarks, url: "https://two.com", title: "Two", folderID: folderA.id)
        bookmarks = LibraryPolicy.addBookmark(bookmarks, url: "https://three.com", title: "Three", folderID: nil)

        let oneID = bookmarks.first(where: { $0.url == "https://one.com" })!.id
        let twoID = bookmarks.first(where: { $0.url == "https://two.com" })!.id
        let threeID = bookmarks.first(where: { $0.url == "https://three.com" })!.id

        // Move single bookmark from Folder A to Folder B
        bookmarks = LibraryPolicy.moveBookmark(bookmarks, id: oneID, toFolderID: folderB.id)
        XCTAssertEqual(bookmarks.first(where: { $0.id == oneID })?.folderID, folderB.id)

        // Batch move twoID and threeID to Folder B
        bookmarks = LibraryPolicy.moveBookmarks(bookmarks, ids: [twoID, threeID], toFolderID: folderB.id)
        XCTAssertEqual(LibraryPolicy.bookmarks(inFolderID: folderB.id, from: bookmarks).count, 3)
        XCTAssertEqual(LibraryPolicy.bookmarks(inFolderID: folderA.id, from: bookmarks).count, 0)

        // Batch delete twoID and threeID
        bookmarks = LibraryPolicy.removeBookmarks(bookmarks, ids: [twoID, threeID])
        XCTAssertEqual(bookmarks.count, 1)
        XCTAssertEqual(bookmarks.first?.id, oneID)
    }

    func testBookmarkSortingOrders() {
        let entries: [BookmarkEntry] = [
            BookmarkEntry(id: "1", title: "Zebra", url: "https://b.org", createdAt: 100),
            BookmarkEntry(id: "2", title: "Alpha", url: "https://c.org", createdAt: 300),
            BookmarkEntry(id: "3", title: "Beta", url: "https://a.org", createdAt: 200)
        ]

        let newest = LibraryPolicy.sortBookmarks(entries, by: .newestFirst)
        XCTAssertEqual(newest.map(\.id), ["2", "3", "1"])

        let oldest = LibraryPolicy.sortBookmarks(entries, by: .oldestFirst)
        XCTAssertEqual(oldest.map(\.id), ["1", "3", "2"])

        let byTitle = LibraryPolicy.sortBookmarks(entries, by: .titleAscending)
        XCTAssertEqual(byTitle.map(\.title), ["Alpha", "Beta", "Zebra"])

        let byDomain = LibraryPolicy.sortBookmarks(entries, by: .domainAscending)
        XCTAssertEqual(byDomain.map(\.hostDisplay), ["a.org", "b.org", "c.org"])
    }

    func testBookmarkHTMLExportAndImportRoundTrip() {
        let folders = [
            BookmarkFolder(id: "f-dev", name: "开发文档", createdAt: 1_700_000_000),
            BookmarkFolder(id: "f-news", name: "科技资讯", createdAt: 1_700_000_100)
        ]
        let bookmarks = [
            BookmarkEntry(id: "b1", title: "Swift.org", url: "https://swift.org", folderID: "f-dev", createdAt: 1_700_000_010),
            BookmarkEntry(id: "b2", title: "Hacker News", url: "https://news.ycombinator.com", folderID: "f-news", createdAt: 1_700_000_020),
            BookmarkEntry(id: "b3", title: "Example Root", url: "https://example.com", folderID: nil, createdAt: 1_700_000_030, isPinnedToStartPage: true)
        ]

        let exportedHTML = BookmarkHTMLTransfer.exportHTML(folders: folders, bookmarks: bookmarks)
        XCTAssertTrue(exportedHTML.contains("<!DOCTYPE NETSCAPE-Bookmark-file-1>"))
        XCTAssertTrue(exportedHTML.contains("开发文档"))
        XCTAssertTrue(exportedHTML.contains("https://swift.org"))

        let imported = BookmarkHTMLTransfer.importHTML(
            exportedHTML,
            existingFolders: [],
            existingBookmarks: []
        )
        XCTAssertEqual(imported.importedCount, 3)
        XCTAssertEqual(imported.folders.count, 2)
        XCTAssertEqual(imported.bookmarks.count, 3)

        let devFolder = imported.folders.first(where: { $0.name == "开发文档" })
        XCTAssertNotNil(devFolder)
        let swiftBM = imported.bookmarks.first(where: { $0.url == "https://swift.org" })
        XCTAssertEqual(swiftBM?.folderID, devFolder?.id)
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

    @MainActor
    func testSessionFolderAndBookmarkManagementSyncsWithStartPageFavorites() {
        let session = BrowserSession()
        defer {
            FavoritesManager.shared.resetToDefaults()
        }

        XCTAssertEqual(session.bookmarkFolders.count, 6)

        // Create a new folder
        let newFolder = session.createBookmarkFolder(name: "云原生专栏")
        XCTAssertNotNil(newFolder)
        XCTAssertEqual(session.bookmarkFolders.count, 7)
        XCTAssertTrue(FavoritesManager.shared.items.contains(where: { $0.isFolder && $0.title == "云原生专栏" }))

        // Add a bookmark into the new folder
        let added = session.addBookmark(
            url: "https://kubernetes.io",
            title: "Kubernetes",
            folderID: newFolder?.id,
            isPinnedToStartPage: false
        )
        XCTAssertNotNil(added)
        XCTAssertEqual(added?.folderID, newFolder?.id)
        let syncedFolder = FavoritesManager.shared.items.first(where: { $0.id == newFolder?.id })
        XCTAssertEqual(syncedFolder?.children.count, 1)
        XCTAssertEqual(syncedFolder?.children.first?.title, "Kubernetes")

        // Move bookmark to "工具" folder ("folder-tools")
        if let bmID = added?.id {
            session.moveBookmark(id: bmID, toFolderID: "folder-tools")
            XCTAssertEqual(session.bookmark(forID: bmID)?.folderID, "folder-tools")
            let toolsFolder = FavoritesManager.shared.items.first(where: { $0.id == "folder-tools" })
            XCTAssertTrue(toolsFolder?.children.contains(where: { $0.url == "https://kubernetes.io" }) == true)
        }

        // Host BookmarkManagerView and LibraryManagerView to verify SwiftUI layout
        let managerView = BookmarkManagerView(session: session, isPresented: .constant(true))
        let managerHost = NSHostingView(rootView: managerView)
        managerHost.frame = NSRect(x: 0, y: 0, width: 860, height: 580)
        XCTAssertNotNil(managerHost)

        let popoverView = LibraryManagerView(session: session, isPresented: .constant(true))
        let popoverHost = NSHostingView(rootView: popoverView)
        popoverHost.frame = NSRect(x: 0, y: 0, width: 430, height: 520)
        XCTAssertNotNil(popoverHost)
    }
}
