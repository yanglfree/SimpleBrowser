import Foundation

public enum SearchEngine: String, CaseIterable, Identifiable, Codable {
    case bing = "Bing"
    case google = "Google"
    case baidu = "Baidu"
    case duckDuckGo = "DuckDuckGo"

    public var id: String { rawValue }

    public func searchURL(for query: String) -> URL? {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        switch self {
        case .bing:
            return URL(string: "https://www.bing.com/search?q=\(encoded)")
        case .google:
            return URL(string: "https://www.google.com/search?q=\(encoded)")
        case .baidu:
            return URL(string: "https://www.baidu.com/s?wd=\(encoded)")
        case .duckDuckGo:
            return URL(string: "https://duckduckgo.com/?q=\(encoded)")
        }
    }
}

public class BrowserSettings: ObservableObject {
    public static let shared = BrowserSettings()

    private enum Keys {
        static let searchEngine = "ZhuoBrowser_SearchEngine"
        static let liveWebViewBudget = "ZhuoBrowser_LiveWebViewBudget"
        static let adBlockEnabled = "ZhuoBrowser_AdBlockEnabled"
        static let cosmeticCleanupEnabled = "ZhuoBrowser_CosmeticCleanupEnabled"
        static let quickSitesEnabled = "ZhuoBrowser_QuickSitesEnabled"
    }

    @Published public var searchEngine: SearchEngine {
        didSet {
            UserDefaults.standard.set(searchEngine.rawValue, forKey: Keys.searchEngine)
        }
    }

    @Published public var quickSitesEnabled: Bool {
        didSet {
            UserDefaults.standard.set(quickSitesEnabled, forKey: Keys.quickSitesEnabled)
        }
    }

    @Published public var liveWebViewBudget: Int {
        didSet {
            let clamped = max(MemoryBudgetPolicy.minLiveBudget, min(liveWebViewBudget, MemoryBudgetPolicy.maxLiveBudget))
            UserDefaults.standard.set(clamped, forKey: Keys.liveWebViewBudget)
        }
    }

    @Published public var adBlockEnabled: Bool {
        didSet {
            UserDefaults.standard.set(adBlockEnabled, forKey: Keys.adBlockEnabled)
        }
    }

    @Published public var cosmeticCleanupEnabled: Bool {
        didSet {
            UserDefaults.standard.set(cosmeticCleanupEnabled, forKey: Keys.cosmeticCleanupEnabled)
        }
    }

    public init() {
        let defaults = UserDefaults.standard
        if let engineRaw = defaults.string(forKey: Keys.searchEngine),
           let engine = SearchEngine(rawValue: engineRaw) {
            self.searchEngine = engine
        } else {
            self.searchEngine = .bing
        }

        let savedBudget = defaults.integer(forKey: Keys.liveWebViewBudget)
        self.liveWebViewBudget = savedBudget > 0 ? savedBudget : MemoryBudgetPolicy.defaultLiveBudget

        self.adBlockEnabled = defaults.object(forKey: Keys.adBlockEnabled) != nil
            ? defaults.bool(forKey: Keys.adBlockEnabled)
            : true

        self.cosmeticCleanupEnabled = defaults.object(forKey: Keys.cosmeticCleanupEnabled) != nil
            ? defaults.bool(forKey: Keys.cosmeticCleanupEnabled)
            : true

        self.quickSitesEnabled = defaults.object(forKey: Keys.quickSitesEnabled) != nil
            ? defaults.bool(forKey: Keys.quickSitesEnabled)
            : true
    }
}
