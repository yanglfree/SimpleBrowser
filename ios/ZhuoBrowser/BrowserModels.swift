import Foundation

struct BrowserTab: Identifiable, Equatable, Codable {
    var id: String
    var url: String
    var title: String
    var isPrivate: Bool
    var isLoading: Bool
    var progress: Double
    var canGoBack: Bool
    var lastVisitedAt: TimeInterval

    static func home(isPrivate: Bool) -> BrowserTab {
        BrowserTab(
            id: UUID().uuidString,
            url: URLPolicy.homeURL,
            title: isPrivate ? "无痕" : "新标签页",
            isPrivate: isPrivate,
            isLoading: false,
            progress: 0,
            canGoBack: false,
            lastVisitedAt: Date().timeIntervalSince1970
        )
    }

    var displayTitle: String {
        if !title.isEmpty && title != url {
            return title
        }
        let host = URLPolicy.displayHost(url)
        return host.isEmpty ? (isPrivate ? "无痕" : "新标签页") : host
    }
}

struct PersistedSession: Codable {
    var tabs: [BrowserTab]
    var activeTabID: String
}
