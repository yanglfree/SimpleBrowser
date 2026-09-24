import Foundation

/// Manages disk persistence for bookmarks and browsing history.
/// Uses background thread writes and atomic file updates to guarantee 0 main thread jank.
public final class LibraryStore: @unchecked Sendable {
    public static let shared = LibraryStore()

    private let ioQueue = DispatchQueue(label: "com.youdroid.zhuobrowser.mac.library-io", qos: .utility)
    private let directoryURL: URL

    private var bookmarksFileURL: URL {
        directoryURL.appendingPathComponent("bookmarks.json")
    }

    private var historyFileURL: URL {
        directoryURL.appendingPathComponent("history.json")
    }

    public init() {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("ZhuoBrowserMac", isDirectory: true)

        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        }
        self.directoryURL = dir
    }

    // MARK: - Bookmarks

    public func loadBookmarks() -> [BookmarkEntry] {
        guard let data = try? Data(contentsOf: bookmarksFileURL),
              let list = try? JSONDecoder().decode([BookmarkEntry].self, from: data) else {
            return []
        }
        return list
    }

    public func saveBookmarks(_ bookmarks: [BookmarkEntry]) {
        let snapshot = bookmarks
        ioQueue.async { [weak self] in
            guard let self = self else { return }
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: self.bookmarksFileURL, options: .atomic)
        }
    }

    // MARK: - History

    public func loadHistory() -> [HistoryEntry] {
        guard let data = try? Data(contentsOf: historyFileURL),
              let list = try? JSONDecoder().decode([HistoryEntry].self, from: data) else {
            return []
        }
        return list
    }

    public func saveHistory(_ history: [HistoryEntry]) {
        let snapshot = history
        ioQueue.async { [weak self] in
            guard let self = self else { return }
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: self.historyFileURL, options: .atomic)
        }
    }

    public func clearHistory() {
        ioQueue.async { [weak self] in
            guard let self = self else { return }
            try? FileManager.default.removeItem(at: self.historyFileURL)
        }
    }
}
