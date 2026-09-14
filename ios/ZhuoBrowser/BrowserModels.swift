import Foundation

struct BrowserTab: Identifiable, Equatable, Codable {
    var id: String
    var url: String
    var title: String
    var isPrivate: Bool
    var isLoading: Bool
    var progress: Double
    var canGoBack: Bool
    var canGoForward: Bool
    var lastVisitedAt: TimeInterval
    var isReader: Bool
    var isDesktop: Bool
    var isPinned: Bool

    static func home(isPrivate: Bool) -> BrowserTab {
        BrowserTab(
            id: UUID().uuidString,
            url: URLPolicy.homeURL,
            title: isPrivate ? "无痕" : "新标签页",
            isPrivate: isPrivate,
            isLoading: false,
            progress: 0,
            canGoBack: false,
            canGoForward: false,
            lastVisitedAt: Date().timeIntervalSince1970,
            isReader: false,
            isDesktop: false,
            isPinned: false
        )
    }

    var displayTitle: String {
        if !title.isEmpty && title != url {
            return title
        }
        let host = URLPolicy.displayHost(url)
        return host.isEmpty ? (isPrivate ? "无痕" : "新标签页") : host
    }

    init(
        id: String,
        url: String,
        title: String,
        isPrivate: Bool,
        isLoading: Bool,
        progress: Double,
        canGoBack: Bool,
        canGoForward: Bool = false,
        lastVisitedAt: TimeInterval,
        isReader: Bool,
        isDesktop: Bool,
        isPinned: Bool = false
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.isPrivate = isPrivate
        self.isLoading = isLoading
        self.progress = progress
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
        self.lastVisitedAt = lastVisitedAt
        self.isReader = isReader
        self.isDesktop = isDesktop
        self.isPinned = isPinned
    }

    enum CodingKeys: String, CodingKey {
        case id, url, title, isPrivate, isLoading, progress, canGoBack, canGoForward
        case lastVisitedAt, isReader, isDesktop, isPinned
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        url = try container.decode(String.self, forKey: .url)
        title = try container.decode(String.self, forKey: .title)
        isPrivate = try container.decode(Bool.self, forKey: .isPrivate)
        isLoading = try container.decodeIfPresent(Bool.self, forKey: .isLoading) ?? false
        progress = try container.decodeIfPresent(Double.self, forKey: .progress) ?? 0
        canGoBack = try container.decodeIfPresent(Bool.self, forKey: .canGoBack) ?? false
        canGoForward = try container.decodeIfPresent(Bool.self, forKey: .canGoForward) ?? false
        lastVisitedAt = try container.decode(TimeInterval.self, forKey: .lastVisitedAt)
        isReader = try container.decodeIfPresent(Bool.self, forKey: .isReader) ?? false
        isDesktop = try container.decodeIfPresent(Bool.self, forKey: .isDesktop) ?? false
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(url, forKey: .url)
        try container.encode(title, forKey: .title)
        try container.encode(isPrivate, forKey: .isPrivate)
        try container.encode(isLoading, forKey: .isLoading)
        try container.encode(progress, forKey: .progress)
        try container.encode(canGoBack, forKey: .canGoBack)
        try container.encode(canGoForward, forKey: .canGoForward)
        try container.encode(lastVisitedAt, forKey: .lastVisitedAt)
        try container.encode(isReader, forKey: .isReader)
        try container.encode(isDesktop, forKey: .isDesktop)
        try container.encode(isPinned, forKey: .isPinned)
    }
}

struct PersistedSession: Codable {
    var tabs: [BrowserTab]
    var activeTabID: String
}
