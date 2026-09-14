import Foundation

enum QuickSiteEditorSource: String, CaseIterable, Identifiable {
    case custom
    case favorites
    case history

    var id: String { rawValue }

    var label: String {
        switch self {
        case .custom: return "自定义"
        case .favorites: return "收藏"
        case .history: return "历史"
        }
    }

    var systemImage: String {
        switch self {
        case .custom: return "pencil"
        case .favorites: return "bookmark"
        case .history: return "clock"
        }
    }
}

struct QuickSiteSourceEntry: Equatable, Identifiable {
    let id: String
    let title: String
    let url: String

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? URLPolicy.displayHost(url) : trimmed
    }
}

enum QuickSiteSourcePolicy {
    static let maximumCount = 30

    static func entries(
        for source: QuickSiteEditorSource,
        savedItems: [SavedItem],
        history: [HistoryEntry]
    ) -> [QuickSiteSourceEntry] {
        switch source {
        case .custom:
            return []
        case .favorites:
            return savedItems.prefix(maximumCount).map { item in
                QuickSiteSourceEntry(
                    id: "favorite-\(item.id)",
                    title: item.title,
                    url: item.url
                )
            }
        case .history:
            return history.prefix(maximumCount).map { entry in
                QuickSiteSourceEntry(
                    id: "history-\(entry.id)",
                    title: entry.title,
                    url: entry.url
                )
            }
        }
    }
}
