import Foundation

public struct HistoryEntry: Identifiable, Equatable, Codable {
    public let id: String
    public var title: String
    public var url: String
    public var visitedAt: TimeInterval
    public var visitCount: Int

    public init(
        id: String = UUID().uuidString,
        title: String,
        url: String,
        visitedAt: TimeInterval = Date().timeIntervalSince1970,
        visitCount: Int = 1
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.visitedAt = visitedAt
        self.visitCount = visitCount
    }

    public var displayTitle: String {
        if !title.isEmpty && title != url {
            return title
        }
        if let host = URL(string: url)?.host {
            return host
        }
        return url
    }
}

public struct BookmarkEntry: Identifiable, Equatable, Codable {
    public let id: String
    public var title: String
    public var url: String
    public var createdAt: TimeInterval

    public init(
        id: String = UUID().uuidString,
        title: String,
        url: String,
        createdAt: TimeInterval = Date().timeIntervalSince1970
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.createdAt = createdAt
    }

    public var displayTitle: String {
        if !title.isEmpty && title != url {
            return title
        }
        if let host = URL(string: url)?.host {
            return host
        }
        return url
    }
}

public enum LibraryPolicy {
    public static let maxHistoryCount = 500
    public static let maxBookmarkCount = 300

    public static func normalizeComparableURL(_ url: String) -> String {
        var trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        return trimmed.lowercased()
    }

    /// Records a new visit into history, deduplicating by URL and bumping visitCount.
    public static func recordHistory(
        _ history: [HistoryEntry],
        url: String,
        title: String,
        now: TimeInterval = Date().timeIntervalSince1970
    ) -> [HistoryEntry] {
        guard !url.isEmpty, url != "zhuo://home" else { return history }

        let target = normalizeComparableURL(url)
        let previous = history.first { normalizeComparableURL($0.url) == target }
        let entryTitle = !title.isEmpty ? title : (previous?.title ?? url)
        let merged = HistoryEntry(
            id: previous?.id ?? UUID().uuidString,
            title: entryTitle,
            url: url,
            visitedAt: now,
            visitCount: (previous?.visitCount ?? 0) + 1
        )

        let filtered = history.filter { normalizeComparableURL($0.url) != target }
        return [merged] + Array(filtered.prefix(maxHistoryCount - 1))
    }

    /// Adds or updates a bookmark entry by URL.
    public static func addBookmark(
        _ bookmarks: [BookmarkEntry],
        url: String,
        title: String,
        now: TimeInterval = Date().timeIntervalSince1970
    ) -> [BookmarkEntry] {
        guard !url.isEmpty, url != "zhuo://home" else { return bookmarks }

        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = !cleanTitle.isEmpty ? cleanTitle : (URL(string: url)?.host ?? url)
        let target = normalizeComparableURL(url)

        let newBookmark = BookmarkEntry(
            id: bookmarks.first(where: { normalizeComparableURL($0.url) == target })?.id ?? UUID().uuidString,
            title: displayTitle,
            url: url,
            createdAt: now
        )

        let filtered = bookmarks.filter { normalizeComparableURL($0.url) != target }
        return [newBookmark] + Array(filtered.prefix(maxBookmarkCount - 1))
    }

    /// Removes a bookmark by its ID.
    public static func removeBookmark(_ bookmarks: [BookmarkEntry], id: String) -> [BookmarkEntry] {
        bookmarks.filter { $0.id != id }
    }

    /// Removes a bookmark by its exact URL.
    public static func removeBookmarkByUrl(_ bookmarks: [BookmarkEntry], url: String) -> [BookmarkEntry] {
        let target = normalizeComparableURL(url)
        return bookmarks.filter { normalizeComparableURL($0.url) != target }
    }

    /// Updates title and URL of an existing bookmark.
    public static func updateBookmark(
        _ bookmarks: [BookmarkEntry],
        id: String,
        title: String,
        url: String
    ) -> [BookmarkEntry] {
        bookmarks.map { item in
            guard item.id == id else { return item }
            var updated = item
            let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanTitle.isEmpty {
                updated.title = cleanTitle
            }
            let cleanURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanURL.isEmpty {
                updated.url = cleanURL
            }
            return updated
        }
    }

    /// Checks whether the specified URL is bookmarked.
    public static func isBookmarked(_ bookmarks: [BookmarkEntry], url: String) -> Bool {
        guard !url.isEmpty, url != "zhuo://home" else { return false }
        let target = normalizeComparableURL(url)
        return bookmarks.contains { normalizeComparableURL($0.url) == target }
    }

    /// Removes a single history item by ID.
    public static func removeHistoryItem(_ history: [HistoryEntry], id: String) -> [HistoryEntry] {
        history.filter { $0.id != id }
    }
}
