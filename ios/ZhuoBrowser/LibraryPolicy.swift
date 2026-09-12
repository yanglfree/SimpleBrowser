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

    static func recordHistory(_ history: [HistoryEntry], entry: HistoryEntry) -> [HistoryEntry] {
        let previous = history.first { $0.url == entry.url }
        var merged = entry
        merged.visitCount = (previous?.visitCount ?? 0) + 1
        return [merged] + Array(history.filter { $0.url != entry.url }.prefix(Self.maxHistoryCount - 1))
    }

    static func addSavedItem(_ items: [SavedItem], item: SavedItem) -> [SavedItem] {
        return [item] + Array(items.filter { $0.url != item.url }.prefix(Self.maxBookmarkCount - 1))
    }

    static func removeSavedItem(_ items: [SavedItem], id: String) -> [SavedItem] {
        items.filter { $0.id != id }
    }

    static func isSaved(_ items: [SavedItem], url: String) -> Bool {
        !URLPolicy.isHomeURL(url) && items.contains { $0.url == url }
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
}
