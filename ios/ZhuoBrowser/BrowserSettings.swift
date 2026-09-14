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

enum TabExpiry: Int, Codable, CaseIterable, Identifiable {
    case never = 0
    case oneDay = 1
    case threeDays = 3
    case sevenDays = 7

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .never: return "永不"
        case .oneDay: return "1 天"
        case .threeDays: return "3 天"
        case .sevenDays: return "7 天"
        }
    }
}

enum HistoryRetention: Int, Codable, CaseIterable, Identifiable {
    case never = 0
    case oneDay = 1
    case sevenDays = 7
    case thirtyDays = 30

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .never: return "永不"
        case .oneDay: return "24 小时"
        case .sevenDays: return "7 天"
        case .thirtyDays: return "30 天"
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
    var tabExpiry: TabExpiry = .sevenDays
    var historyRetention: HistoryRetention = .thirtyDays
    var liveWebViewLimit: Int = 4
    var tabSoftLimit: Int = 12
    var downloadConcurrency: Int = 2
    var largeDownloadThresholdMB: Int = 50
    var wifiOnlyDownloads: Bool = false
    var downloadNotificationsEnabled: Bool = false
    var clearCookiesOnTabClose: Bool = false

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
        case tabExpiry, historyRetentionDays, liveWebViewLimit, tabSoftLimit
        case downloadConcurrency, largeDownloadThresholdMB, wifiOnlyDownloads
        case downloadNotificationsEnabled
        case clearCookiesOnTabClose
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
        homeBackgroundStyle: HomeBackgroundStyle = .forest,
        tabExpiry: TabExpiry = .sevenDays,
        historyRetention: HistoryRetention = .thirtyDays,
        liveWebViewLimit: Int = 4,
        tabSoftLimit: Int = 12,
        downloadConcurrency: Int = 2,
        largeDownloadThresholdMB: Int = 50,
        wifiOnlyDownloads: Bool = false,
        downloadNotificationsEnabled: Bool = false,
        clearCookiesOnTabClose: Bool = false
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
        self.tabExpiry = tabExpiry
        self.historyRetention = historyRetention
        self.liveWebViewLimit = Self.clampedLiveWebViewLimit(liveWebViewLimit)
        self.tabSoftLimit = Self.clampedTabSoftLimit(tabSoftLimit)
        self.downloadConcurrency = Self.clampedDownloadConcurrency(downloadConcurrency)
        self.largeDownloadThresholdMB = Self.clampedLargeDownloadThresholdMB(largeDownloadThresholdMB)
        self.wifiOnlyDownloads = wifiOnlyDownloads
        self.downloadNotificationsEnabled = downloadNotificationsEnabled
        self.clearCookiesOnTabClose = clearCookiesOnTabClose
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
        tabExpiry = try container.decodeIfPresent(TabExpiry.self, forKey: .tabExpiry) ?? .sevenDays
        historyRetention = try container.decodeIfPresent(
            HistoryRetention.self,
            forKey: .historyRetentionDays
        ) ?? .thirtyDays
        liveWebViewLimit = Self.clampedLiveWebViewLimit(
            try container.decodeIfPresent(Int.self, forKey: .liveWebViewLimit) ?? 4
        )
        tabSoftLimit = Self.clampedTabSoftLimit(
            try container.decodeIfPresent(Int.self, forKey: .tabSoftLimit) ?? 12
        )
        downloadConcurrency = Self.clampedDownloadConcurrency(
            try container.decodeIfPresent(Int.self, forKey: .downloadConcurrency) ?? 2
        )
        largeDownloadThresholdMB = Self.clampedLargeDownloadThresholdMB(
            try container.decodeIfPresent(Int.self, forKey: .largeDownloadThresholdMB) ?? 50
        )
        wifiOnlyDownloads = try container.decodeIfPresent(Bool.self, forKey: .wifiOnlyDownloads) ?? false
        downloadNotificationsEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .downloadNotificationsEnabled
        ) ?? false
        clearCookiesOnTabClose = try container.decodeIfPresent(Bool.self, forKey: .clearCookiesOnTabClose) ?? false
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
        try container.encode(tabExpiry, forKey: .tabExpiry)
        try container.encode(historyRetention, forKey: .historyRetentionDays)
        try container.encode(Self.clampedLiveWebViewLimit(liveWebViewLimit), forKey: .liveWebViewLimit)
        try container.encode(Self.clampedTabSoftLimit(tabSoftLimit), forKey: .tabSoftLimit)
        try container.encode(Self.clampedDownloadConcurrency(downloadConcurrency), forKey: .downloadConcurrency)
        try container.encode(
            Self.clampedLargeDownloadThresholdMB(largeDownloadThresholdMB),
            forKey: .largeDownloadThresholdMB
        )
        try container.encode(wifiOnlyDownloads, forKey: .wifiOnlyDownloads)
        try container.encode(downloadNotificationsEnabled, forKey: .downloadNotificationsEnabled)
        try container.encode(clearCookiesOnTabClose, forKey: .clearCookiesOnTabClose)
    }

    static func clampedQuickSiteLimit(_ value: Int) -> Int {
        min(8, max(4, value))
    }

    static func clampedLiveWebViewLimit(_ value: Int) -> Int {
        if value <= 1 { return 1 }
        if value <= 2 { return 2 }
        if value <= 4 { return 4 }
        return 6
    }

    static func clampedTabSoftLimit(_ value: Int) -> Int {
        if value <= 8 { return 8 }
        if value <= 12 { return 12 }
        if value <= 20 { return 20 }
        return 40
    }

    static func clampedDownloadConcurrency(_ value: Int) -> Int {
        min(6, max(1, value))
    }

    static func clampedLargeDownloadThresholdMB(_ value: Int) -> Int {
        min(1_024, max(1, value))
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
