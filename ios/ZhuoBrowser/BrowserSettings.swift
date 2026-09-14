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

enum WebDarkModePreference: Int, Codable, CaseIterable, Identifiable {
    case system = 0
    case light = 1
    case dark = 2

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "始终浅色"
        case .dark: return "始终深色"
        }
    }
}

enum UserAgentPreference: Int, Codable, CaseIterable, Identifiable {
    case `default` = 0
    case mobile = 1
    case desktop = 2

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .default: return "默认"
        case .mobile: return "移动版"
        case .desktop: return "桌面版"
        }
    }
}

struct SiteUserAgentPreference: Codable, Equatable {
    let host: String
    let preference: UserAgentPreference
}

struct SiteZoomRatio: Codable, Equatable {
    let host: String
    let percent: Int
}

enum HomeBackgroundStyle: Int, Codable, CaseIterable, Identifiable {
    case plain = 0
    case forest = 1
    case dusk = 2
    case ocean = 3
    case daily = 4
    case custom = 5

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .plain: return "纯色"
        case .forest: return "松林"
        case .dusk: return "暮色"
        case .ocean: return "远海"
        case .daily: return "每日美图"
        case .custom: return "自定义照片"
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
    var customSearchTemplate: String = ""
    var blockAds: Bool = true
    var searchSuggestionsEnabled: Bool = true
    var gesturesEnabled: Bool = true
    var gestureTabSwitchEnabled: Bool = true
    var autoHideToolbarEnabled: Bool = true
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
    var minimumFontSize: Int = 14
    var siteZoomRatios: [SiteZoomRatio] = []
    var defaultUserAgentPreference: UserAgentPreference = .default
    var siteUserAgentPreferences: [SiteUserAgentPreference] = []
    var webDarkMode: WebDarkModePreference = .system
    var webDarkModeExcludedHosts: [String] = []
    var ruleStrength: RuleStrength = .standard
    var siteControls: [SiteControl] = []
    var rulesLastUpdatedAt: TimeInterval = 0

    var searchEngineLabel: String {
        switch searchEngine {
        case .bing: return "Bing"
        case .baidu: return "百度"
        case .google: return "Google"
        case .duckDuckGo: return "DuckDuckGo"
        }
    }

    enum CodingKeys: String, CodingKey {
        case searchEngine, customSearchTemplate, blockAds, searchSuggestionsEnabled
        case gesturesEnabled, gestureTabSwitchEnabled, autoHideToolbarEnabled
        case privacyConsentAccepted, onboardingCompleted, appearance
        case quickSitesEnabled, quickSiteLimit, homeBackgroundStyle
        case tabExpiry, historyRetentionDays, liveWebViewLimit, tabSoftLimit
        case downloadConcurrency, largeDownloadThresholdMB, wifiOnlyDownloads
        case downloadNotificationsEnabled
        case clearCookiesOnTabClose
        case minimumFontSize, siteZoomRatios
        case defaultUserAgentPreference, siteUserAgentPreferences
        case webDarkMode, webDarkModeExcludedHosts
        case ruleStrength, siteControls, rulesLastUpdatedAt
    }

    init(
        searchEngine: SearchEngine = .bing,
        customSearchTemplate: String = "",
        blockAds: Bool = true,
        searchSuggestionsEnabled: Bool = true,
        gesturesEnabled: Bool = true,
        gestureTabSwitchEnabled: Bool = true,
        autoHideToolbarEnabled: Bool = true,
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
        clearCookiesOnTabClose: Bool = false,
        minimumFontSize: Int = 14,
        siteZoomRatios: [SiteZoomRatio] = [],
        defaultUserAgentPreference: UserAgentPreference = .default,
        siteUserAgentPreferences: [SiteUserAgentPreference] = [],
        webDarkMode: WebDarkModePreference = .system,
        webDarkModeExcludedHosts: [String] = [],
        ruleStrength: RuleStrength = .standard,
        siteControls: [SiteControl] = [],
        rulesLastUpdatedAt: TimeInterval = 0
    ) {
        self.searchEngine = searchEngine
        self.customSearchTemplate = Self.normalizedSearchTemplate(customSearchTemplate)
        self.blockAds = blockAds
        self.searchSuggestionsEnabled = searchSuggestionsEnabled
        self.gesturesEnabled = gesturesEnabled
        self.gestureTabSwitchEnabled = gestureTabSwitchEnabled
        self.autoHideToolbarEnabled = autoHideToolbarEnabled
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
        self.minimumFontSize = Self.clampedMinimumFontSize(minimumFontSize)
        self.siteZoomRatios = WebAppearancePolicy.normalizedZoomRatios(siteZoomRatios)
        self.defaultUserAgentPreference = defaultUserAgentPreference
        self.siteUserAgentPreferences = WebAppearancePolicy.normalizedUserAgentPreferences(siteUserAgentPreferences)
        self.webDarkMode = webDarkMode
        self.webDarkModeExcludedHosts = WebAppearancePolicy.normalizedHosts(webDarkModeExcludedHosts)
        self.ruleStrength = ruleStrength
        self.siteControls = BlockingPolicy.normalizedSiteControls(siteControls)
        self.rulesLastUpdatedAt = max(0, rulesLastUpdatedAt)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        searchEngine = try container.decodeIfPresent(SearchEngine.self, forKey: .searchEngine) ?? .bing
        customSearchTemplate = Self.normalizedSearchTemplate(
            try container.decodeIfPresent(String.self, forKey: .customSearchTemplate) ?? ""
        )
        blockAds = try container.decodeIfPresent(Bool.self, forKey: .blockAds) ?? true
        searchSuggestionsEnabled = try container.decodeIfPresent(Bool.self, forKey: .searchSuggestionsEnabled) ?? true
        gesturesEnabled = try container.decodeIfPresent(Bool.self, forKey: .gesturesEnabled) ?? true
        gestureTabSwitchEnabled = try container.decodeIfPresent(Bool.self, forKey: .gestureTabSwitchEnabled) ?? true
        autoHideToolbarEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoHideToolbarEnabled) ?? true
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
        minimumFontSize = Self.clampedMinimumFontSize(
            try container.decodeIfPresent(Int.self, forKey: .minimumFontSize) ?? 14
        )
        siteZoomRatios = WebAppearancePolicy.normalizedZoomRatios(
            try container.decodeIfPresent([SiteZoomRatio].self, forKey: .siteZoomRatios) ?? []
        )
        defaultUserAgentPreference = try container.decodeIfPresent(
            UserAgentPreference.self,
            forKey: .defaultUserAgentPreference
        ) ?? .default
        siteUserAgentPreferences = WebAppearancePolicy.normalizedUserAgentPreferences(
            try container.decodeIfPresent(
                [SiteUserAgentPreference].self,
                forKey: .siteUserAgentPreferences
            ) ?? []
        )
        webDarkMode = try container.decodeIfPresent(WebDarkModePreference.self, forKey: .webDarkMode) ?? .system
        webDarkModeExcludedHosts = WebAppearancePolicy.normalizedHosts(
            try container.decodeIfPresent([String].self, forKey: .webDarkModeExcludedHosts) ?? []
        )
        ruleStrength = try container.decodeIfPresent(RuleStrength.self, forKey: .ruleStrength) ?? .standard
        siteControls = BlockingPolicy.normalizedSiteControls(
            try container.decodeIfPresent([SiteControl].self, forKey: .siteControls) ?? []
        )
        rulesLastUpdatedAt = max(
            0,
            try container.decodeIfPresent(TimeInterval.self, forKey: .rulesLastUpdatedAt) ?? 0
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(searchEngine, forKey: .searchEngine)
        try container.encode(Self.normalizedSearchTemplate(customSearchTemplate), forKey: .customSearchTemplate)
        try container.encode(blockAds, forKey: .blockAds)
        try container.encode(searchSuggestionsEnabled, forKey: .searchSuggestionsEnabled)
        try container.encode(gesturesEnabled, forKey: .gesturesEnabled)
        try container.encode(gestureTabSwitchEnabled, forKey: .gestureTabSwitchEnabled)
        try container.encode(autoHideToolbarEnabled, forKey: .autoHideToolbarEnabled)
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
        try container.encode(Self.clampedMinimumFontSize(minimumFontSize), forKey: .minimumFontSize)
        try container.encode(WebAppearancePolicy.normalizedZoomRatios(siteZoomRatios), forKey: .siteZoomRatios)
        try container.encode(defaultUserAgentPreference, forKey: .defaultUserAgentPreference)
        try container.encode(
            WebAppearancePolicy.normalizedUserAgentPreferences(siteUserAgentPreferences),
            forKey: .siteUserAgentPreferences
        )
        try container.encode(webDarkMode, forKey: .webDarkMode)
        try container.encode(
            WebAppearancePolicy.normalizedHosts(webDarkModeExcludedHosts),
            forKey: .webDarkModeExcludedHosts
        )
        try container.encode(ruleStrength, forKey: .ruleStrength)
        try container.encode(BlockingPolicy.normalizedSiteControls(siteControls), forKey: .siteControls)
        try container.encode(max(0, rulesLastUpdatedAt), forKey: .rulesLastUpdatedAt)
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

    static func clampedMinimumFontSize(_ value: Int) -> Int {
        [12, 14, 16, 18].min(by: { abs($0 - value) < abs($1 - value) }) ?? 14
    }

    static func normalizedSearchTemplate(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.contains("%s") ? trimmed : ""
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
