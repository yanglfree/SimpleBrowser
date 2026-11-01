import Foundation

/// Manages disk persistence for bookmarks, bookmark folders, and browsing history.
/// Uses background thread writes and atomic file updates to guarantee 0 main thread jank.
public final class LibraryStore: @unchecked Sendable {
    public static let shared = LibraryStore()

    private let ioQueue = DispatchQueue(label: "com.youdroid.zhuobrowser.mac.library-io", qos: .utility)
    private let directoryURL: URL
    private let isPersistenceEnabled: Bool

    private var bookmarksFileURL: URL {
        directoryURL.appendingPathComponent("bookmarks.json")
    }

    private var bookmarkFoldersFileURL: URL {
        directoryURL.appendingPathComponent("bookmark_folders.json")
    }

    private var historyFileURL: URL {
        directoryURL.appendingPathComponent("history.json")
    }

    public init(isPersistenceEnabled: Bool = !RuntimeEnvironment.isRunningUnitTests) {
        self.isPersistenceEnabled = isPersistenceEnabled
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("ZhuoBrowserMac", isDirectory: true)

        if isPersistenceEnabled && !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        }
        self.directoryURL = dir
    }

    // MARK: - Unified Bookmarks & Folders Loading

    public func loadInitialBookmarksAndFolders() -> (folders: [BookmarkFolder], bookmarks: [BookmarkEntry]) {
        guard isPersistenceEnabled else {
            return FavoritesManager.seedDefaultLibrary()
        }

        let fileManager = FileManager.default
        let hasFoldersFile = fileManager.fileExists(atPath: bookmarkFoldersFileURL.path)
        let existingBookmarks = loadBookmarks()

        if hasFoldersFile {
            let folders = loadBookmarkFolders()
            if !folders.isEmpty || !existingBookmarks.isEmpty {
                return (folders, existingBookmarks)
            }
        }

        // First launch or migration from flat legacy bookmarks.json:
        // Seed the structured folders and default bookmarks, then merge any pre-existing user bookmarks.
        let seeded = FavoritesManager.seedDefaultLibrary()
        var mergedBookmarks = seeded.bookmarks
        let seededURLs = Set(seeded.bookmarks.map { LibraryPolicy.normalizeComparableURL($0.url) })

        let customExisting = existingBookmarks.filter {
            !seededURLs.contains(LibraryPolicy.normalizeComparableURL($0.url))
        }.map { entry -> BookmarkEntry in
            var copy = entry
            copy.isPinnedToStartPage = true
            return copy
        }

        if !customExisting.isEmpty {
            mergedBookmarks = customExisting + mergedBookmarks
        }

        saveBookmarkFolders(seeded.folders)
        saveBookmarks(mergedBookmarks)
        return (seeded.folders, mergedBookmarks)
    }

    // MARK: - Bookmark Folders

    public func loadBookmarkFolders() -> [BookmarkFolder] {
        guard isPersistenceEnabled,
              let data = try? Data(contentsOf: bookmarkFoldersFileURL),
              let list = try? JSONDecoder().decode([BookmarkFolder].self, from: data) else {
            return []
        }
        return list
    }

    public func saveBookmarkFolders(_ folders: [BookmarkFolder]) {
        guard isPersistenceEnabled else { return }
        let snapshot = folders
        ioQueue.async { [weak self] in
            guard let self = self else { return }
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: self.bookmarkFoldersFileURL, options: .atomic)
        }
    }

    // MARK: - Bookmarks

    public func loadBookmarks() -> [BookmarkEntry] {
        guard isPersistenceEnabled,
              let data = try? Data(contentsOf: bookmarksFileURL),
              let list = try? JSONDecoder().decode([BookmarkEntry].self, from: data) else {
            return []
        }
        return list
    }

    public func saveBookmarks(_ bookmarks: [BookmarkEntry]) {
        guard isPersistenceEnabled else { return }
        let snapshot = bookmarks
        ioQueue.async { [weak self] in
            guard let self = self else { return }
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: self.bookmarksFileURL, options: .atomic)
        }
    }

    // MARK: - History

    public func loadHistory() -> [HistoryEntry] {
        guard isPersistenceEnabled,
              let data = try? Data(contentsOf: historyFileURL),
              let list = try? JSONDecoder().decode([HistoryEntry].self, from: data) else {
            return []
        }
        return list
    }

    public func saveHistory(_ history: [HistoryEntry]) {
        guard isPersistenceEnabled else { return }
        let snapshot = history
        ioQueue.async { [weak self] in
            guard let self = self else { return }
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: self.historyFileURL, options: .atomic)
        }
    }

    public func clearHistory() {
        guard isPersistenceEnabled else { return }
        ioQueue.async { [weak self] in
            guard let self = self else { return }
            try? FileManager.default.removeItem(at: self.historyFileURL)
        }
    }
}
