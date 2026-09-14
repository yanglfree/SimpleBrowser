import Foundation

struct HistoryEntry: Identifiable, Equatable, Codable {
    var id: String
    var title: String
    var url: String
    var visitedAt: TimeInterval
    var visitCount: Int
}

struct SavedItem: Identifiable, Equatable, Codable {
    var id: String
    var title: String
    var url: String
    var createdAt: TimeInterval
    var updatedAt: TimeInterval
    var isRead: Bool
    var tags: [String]

    init(
        id: String,
        title: String,
        url: String,
        createdAt: TimeInterval,
        updatedAt: TimeInterval,
        isRead: Bool = true,
        tags: [String] = []
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isRead = isRead
        self.tags = tags
    }

    enum CodingKeys: String, CodingKey {
        case id, title, url, createdAt, updatedAt, isRead, tags
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        url = try container.decode(String.self, forKey: .url)
        createdAt = try container.decode(TimeInterval.self, forKey: .createdAt)
        updatedAt = try container.decode(TimeInterval.self, forKey: .updatedAt)
        isRead = try container.decodeIfPresent(Bool.self, forKey: .isRead) ?? true
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
    }
}

enum LibraryEntryKind: String, Equatable {
    case bookmark
    case history
}

struct LibrarySearchEntry: Identifiable, Equatable {
    var id: String
    var kind: LibraryEntryKind
    var title: String
    var url: String
    var timestamp: TimeInterval
}

enum SuggestionKind: Int {
    case history = 0
    case bookmark = 1
    case search = 2
}

struct AddressSuggestion: Identifiable, Equatable {
    var id: String
    var kind: SuggestionKind
    var title: String
    var subtitle: String
    var url: String
}

enum LibraryPolicy {
    static let maxHistoryCount = 300
    static let maxBookmarkCount = 200
    static let maxSuggestionCount = 6

    static func recordHistory(
        _ history: [HistoryEntry],
        entry: HistoryEntry,
        retentionDays: Int = 0,
        now: TimeInterval = Date().timeIntervalSince1970
    ) -> [HistoryEntry] {
        let previous = history.first { $0.url == entry.url }
        var merged = entry
        merged.visitCount = (previous?.visitCount ?? 0) + 1
        let updated = [merged] + Array(history.filter { $0.url != entry.url }.prefix(Self.maxHistoryCount - 1))
        return applyingHistoryRetention(updated, retentionDays: retentionDays, now: now)
    }

    static func addSavedItem(_ items: [SavedItem], item: SavedItem) -> [SavedItem] {
        return [item] + Array(items.filter { $0.url != item.url }.prefix(Self.maxBookmarkCount - 1))
    }

    static func removeSavedItem(_ items: [SavedItem], id: String) -> [SavedItem] {
        items.filter { $0.id != id }
    }

    static func renameSavedItem(
        _ items: [SavedItem],
        id: String,
        title: String,
        updatedAt: TimeInterval = Date().timeIntervalSince1970
    ) -> [SavedItem] {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else {
            return items
        }
        return items.map { item in
            guard item.id == id else { return item }
            var updated = item
            updated.title = cleanTitle
            updated.updatedAt = updatedAt
            return updated
        }
    }

    static func saveForLater(
        _ items: [SavedItem],
        url: String,
        title: String,
        updatedAt: TimeInterval = Date().timeIntervalSince1970
    ) -> [SavedItem] {
        guard !url.isEmpty, !URLPolicy.isHomeURL(url) else {
            return items
        }
        if let existing = items.first(where: { $0.url == url }) {
            return items.map { item in
                guard item.id == existing.id else { return item }
                var updated = item
                updated.isRead = false
                updated.updatedAt = updatedAt
                return updated
            }
        }
        let item = SavedItem(
            id: "saved-\(Int(updatedAt * 1000))",
            title: title.isEmpty ? URLPolicy.displayHost(url) : title,
            url: url,
            createdAt: updatedAt,
            updatedAt: updatedAt,
            isRead: false
        )
        return addSavedItem(items, item: item)
    }

    static func markSavedItemRead(
        _ items: [SavedItem],
        url: String,
        updatedAt: TimeInterval = Date().timeIntervalSince1970
    ) -> [SavedItem] {
        guard items.contains(where: { $0.url == url && !$0.isRead }) else {
            return items
        }
        return items.map { item in
            guard item.url == url else { return item }
            var updated = item
            updated.isRead = true
            updated.updatedAt = updatedAt
            return updated
        }
    }

    static func isSaved(_ items: [SavedItem], url: String) -> Bool {
        !URLPolicy.isHomeURL(url) && items.contains { $0.url == url }
    }

    static func isSavedForLater(_ items: [SavedItem], url: String) -> Bool {
        !URLPolicy.isHomeURL(url) && items.contains { $0.url == url && !$0.isRead }
    }

    static func removeHistoryForHost(_ history: [HistoryEntry], host: String) -> [HistoryEntry] {
        let normalized = host.lowercased()
        return history.filter { URLPolicy.rawHost($0.url).lowercased() != normalized }
    }

    static func applyingHistoryRetention(
        _ history: [HistoryEntry],
        retentionDays: Int,
        now: TimeInterval = Date().timeIntervalSince1970
    ) -> [HistoryEntry] {
        guard retentionDays > 0 else {
            return history
        }
        let cutoff = now - TimeInterval(retentionDays * 24 * 60 * 60)
        return history.filter { $0.visitedAt >= cutoff }
    }

    static func mergeSavedItems(
        _ existing: [SavedItem],
        imported: [SavedItem]
    ) -> (items: [SavedItem], importedCount: Int) {
        var merged = existing
        var urls = Set(existing.map(\.url))
        var importedCount = 0
        for item in imported where merged.count < maxBookmarkCount {
            guard urls.insert(item.url).inserted else {
                continue
            }
            merged.append(item)
            importedCount += 1
        }
        return (merged, importedCount)
    }

    static func filteredSavedItems(_ items: [SavedItem], query: String) -> [SavedItem] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else {
            return items
        }
        return items.filter {
            $0.title.lowercased().contains(needle) || $0.url.lowercased().contains(needle)
        }
    }

    static func searchHistoryAndBookmarks(
        query: String,
        history: [HistoryEntry],
        savedItems: [SavedItem]
    ) -> [LibrarySearchEntry] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else {
            return []
        }
        var results = savedItems.map {
            LibrarySearchEntry(
                id: "bookmark-\($0.id)",
                kind: .bookmark,
                title: $0.title,
                url: $0.url,
                timestamp: $0.updatedAt
            )
        }
        let savedURLs = Set(savedItems.map(\.url))
        results += history.filter { !savedURLs.contains($0.url) }.map {
            LibrarySearchEntry(
                id: "history-\($0.id)",
                kind: .history,
                title: $0.title,
                url: $0.url,
                timestamp: $0.visitedAt
            )
        }
        return results
            .filter { $0.title.lowercased().contains(needle) || $0.url.lowercased().contains(needle) }
            .sorted {
                let leftScore = matchScore(title: $0.title, url: $0.url, query: needle)
                let rightScore = matchScore(title: $1.title, url: $1.url, query: needle)
                return leftScore == rightScore ? $0.timestamp > $1.timestamp : leftScore > rightScore
            }
    }

    static func suggestions(
        query: String,
        history: [HistoryEntry],
        savedItems: [SavedItem],
        searchSuggestionsEnabled: Bool,
        searchURL: String
    ) -> [AddressSuggestion] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var results: [AddressSuggestion] = []
        if trimmed.isEmpty {
            for entry in history where results.count < maxSuggestionCount {
                results.append(historySuggestion(entry))
            }
            for bookmark in savedItems where results.count < maxSuggestionCount {
                if !results.contains(where: { $0.url == bookmark.url }) {
                    results.append(bookmarkSuggestion(bookmark))
                }
            }
            return results
        }
        let needle = trimmed.lowercased()
        func matches(_ title: String, _ url: String) -> Bool {
            title.lowercased().contains(needle) || url.lowercased().contains(needle)
        }
        for entry in history where results.count < maxSuggestionCount {
            if matches(entry.title, entry.url) {
                results.append(historySuggestion(entry))
            }
        }
        for bookmark in savedItems where results.count < maxSuggestionCount {
            if matches(bookmark.title, bookmark.url) && !results.contains(where: { $0.url == bookmark.url }) {
                results.append(bookmarkSuggestion(bookmark))
            }
        }
        if searchSuggestionsEnabled && results.count < maxSuggestionCount && !searchURL.isEmpty {
            results.append(
                AddressSuggestion(
                    id: "search-\(trimmed)",
                    kind: .search,
                    title: trimmed,
                    subtitle: "",
                    url: searchURL
                )
            )
        }
        return results
    }

    private static func historySuggestion(_ entry: HistoryEntry) -> AddressSuggestion {
        let host = URLPolicy.displayHost(entry.url)
        return AddressSuggestion(
            id: "history-\(entry.id)",
            kind: .history,
            title: entry.title.isEmpty ? host : entry.title,
            subtitle: host,
            url: entry.url
        )
    }

    private static func bookmarkSuggestion(_ item: SavedItem) -> AddressSuggestion {
        let host = URLPolicy.displayHost(item.url)
        return AddressSuggestion(
            id: "bookmark-\(item.id)",
            kind: .bookmark,
            title: item.title.isEmpty ? host : item.title,
            subtitle: host,
            url: item.url
        )
    }

    private static func matchScore(title: String, url: String, query: String) -> Int {
        let title = title.lowercased()
        let url = url.lowercased()
        var score = 0
        if title == query || url == query { score += 1_000 }
        if title.hasPrefix(query) { score += 400 }
        if url.hasPrefix(query) { score += 300 }
        if title.contains(query) { score += 200 }
        if url.contains(query) { score += 100 }
        return score
    }
}
