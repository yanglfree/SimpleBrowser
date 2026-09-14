import Foundation

enum AppearanceMode: Int, Codable, CaseIterable, Identifiable {
    case system = 0
    case light = 1
    case dark = 2

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }
}

enum HomeBackgroundStyle: Int, Codable, CaseIterable, Identifiable {
    case plain = 0
    case forest = 1
    case dusk = 2
    case ocean = 3

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .plain: return "纯色"
        case .forest: return "松林"
        case .dusk: return "暮色"
        case .ocean: return "远海"
        }
    }
}

struct BrowserSettings: Equatable {
    var searchEngine: SearchEngine = .bing
    var blockAds: Bool = true
    var searchSuggestionsEnabled: Bool = true
    var privacyConsentAccepted: Bool = false
    var onboardingCompleted: Bool = false
    var appearance: AppearanceMode = .system
    var quickSitesEnabled: Bool = true
    var quickSiteLimit: Int = 6
    var homeBackgroundStyle: HomeBackgroundStyle = .forest

    var searchEngineLabel: String {
        switch searchEngine {
        case .bing: return "Bing"
        case .baidu: return "百度"
        case .google: return "Google"
        case .duckDuckGo: return "DuckDuckGo"
        }
    }

    enum CodingKeys: String, CodingKey {
        case searchEngine, blockAds, searchSuggestionsEnabled
        case privacyConsentAccepted, onboardingCompleted, appearance
        case quickSitesEnabled, quickSiteLimit, homeBackgroundStyle
    }

    init(
        searchEngine: SearchEngine = .bing,
        blockAds: Bool = true,
        searchSuggestionsEnabled: Bool = true,
        privacyConsentAccepted: Bool = false,
        onboardingCompleted: Bool = false,
        appearance: AppearanceMode = .system,
        quickSitesEnabled: Bool = true,
        quickSiteLimit: Int = 6,
        homeBackgroundStyle: HomeBackgroundStyle = .forest
    ) {
        self.searchEngine = searchEngine
        self.blockAds = blockAds
        self.searchSuggestionsEnabled = searchSuggestionsEnabled
        self.privacyConsentAccepted = privacyConsentAccepted
        self.onboardingCompleted = onboardingCompleted
        self.appearance = appearance
        self.quickSitesEnabled = quickSitesEnabled
        self.quickSiteLimit = Self.clampedQuickSiteLimit(quickSiteLimit)
        self.homeBackgroundStyle = homeBackgroundStyle
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        searchEngine = try container.decodeIfPresent(SearchEngine.self, forKey: .searchEngine) ?? .bing
        blockAds = try container.decodeIfPresent(Bool.self, forKey: .blockAds) ?? true
        searchSuggestionsEnabled = try container.decodeIfPresent(Bool.self, forKey: .searchSuggestionsEnabled) ?? true
        privacyConsentAccepted = try container.decodeIfPresent(Bool.self, forKey: .privacyConsentAccepted) ?? false
        onboardingCompleted = try container.decodeIfPresent(Bool.self, forKey: .onboardingCompleted) ?? false
        appearance = try container.decodeIfPresent(AppearanceMode.self, forKey: .appearance) ?? .system
        quickSitesEnabled = try container.decodeIfPresent(Bool.self, forKey: .quickSitesEnabled) ?? true
        quickSiteLimit = Self.clampedQuickSiteLimit(
            try container.decodeIfPresent(Int.self, forKey: .quickSiteLimit) ?? 6
        )
        homeBackgroundStyle = try container.decodeIfPresent(HomeBackgroundStyle.self, forKey: .homeBackgroundStyle) ?? .forest
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(searchEngine, forKey: .searchEngine)
        try container.encode(blockAds, forKey: .blockAds)
        try container.encode(searchSuggestionsEnabled, forKey: .searchSuggestionsEnabled)
        try container.encode(privacyConsentAccepted, forKey: .privacyConsentAccepted)
        try container.encode(onboardingCompleted, forKey: .onboardingCompleted)
        try container.encode(appearance, forKey: .appearance)
        try container.encode(quickSitesEnabled, forKey: .quickSitesEnabled)
        try container.encode(Self.clampedQuickSiteLimit(quickSiteLimit), forKey: .quickSiteLimit)
        try container.encode(homeBackgroundStyle, forKey: .homeBackgroundStyle)
    }

    static func clampedQuickSiteLimit(_ value: Int) -> Int {
        min(8, max(4, value))
    }
}

extension BrowserSettings: Codable {}

extension SearchEngine: CaseIterable, Identifiable {
    var id: Int { rawValue }

    static var allCases: [SearchEngine] {
        [.bing, .baidu, .google, .duckDuckGo]
    }

    var label: String {
        BrowserSettings(searchEngine: self).searchEngineLabel
    }
}
