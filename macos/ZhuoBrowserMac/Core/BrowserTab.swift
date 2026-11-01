import Foundation

/// Represents a single browser tab in ZhuoBrowser Mac.
/// Designed for extreme memory frugality: inactive tabs can be hibernated,
/// releasing the underlying WKWebView and WebContent process while preserving navigation state.
public struct BrowserTab: Identifiable, Codable, Equatable {
    public let id: String
    public var url: String
    public var title: String
    public var isLoading: Bool
    public var loadingProgress: Double
    public var canGoBack: Bool
    public var canGoForward: Bool
    public var isPrivate: Bool
    public var isHibernated: Bool
    public var lastActiveTime: Date
    public var scrollPositionY: Double
    public var blockedItemsCount: Int
    public var isReaderModeActive: Bool
    public var readerContentHTML: String?
    /// True when the tab was revived from a snapshot old enough that its content may
    /// no longer reflect the live site. Purely informational: the page is already
    /// visible, so the user can keep reading or refresh on demand.
    public var isSnapshotStale: Bool

    public init(
        id: String = UUID().uuidString,
        url: String = "",
        title: String = "新标签页",
        isLoading: Bool = false,
        loadingProgress: Double = 0.0,
        canGoBack: Bool = false,
        canGoForward: Bool = false,
        isPrivate: Bool = false,
        isHibernated: Bool = false,
        lastActiveTime: Date = Date(),
        scrollPositionY: Double = 0.0,
        blockedItemsCount: Int = 0,
        isReaderModeActive: Bool = false,
        readerContentHTML: String? = nil,
        isSnapshotStale: Bool = false
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.isLoading = isLoading
        self.loadingProgress = loadingProgress
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
        self.isPrivate = isPrivate
        self.isHibernated = isHibernated
        self.lastActiveTime = lastActiveTime
        self.scrollPositionY = scrollPositionY
        self.blockedItemsCount = blockedItemsCount
        self.isReaderModeActive = isReaderModeActive
        self.readerContentHTML = readerContentHTML
        self.isSnapshotStale = isSnapshotStale
    }

    public var isHome: Bool {
        url.isEmpty || url == "zhuo://home"
    }

    public var displayTitle: String {
        if isHome {
            return isPrivate ? "无痕新标签" : "新标签页"
        }
        if !title.isEmpty {
            return title
        }
        if let host = URL(string: url)?.host {
            return host
        }
        return url
    }
}
