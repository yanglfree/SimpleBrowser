import Foundation

enum RuleStrength: Int, Codable, CaseIterable, Identifiable {
    case standard = 0
    case strict = 1

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .standard: return "标准"
        case .strict: return "严格"
        }
    }
}

enum SiteControlMode: Int, Codable, CaseIterable, Identifiable {
    case inherit = 0
    case enabled = 1
    case disabled = 2

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .inherit: return "跟随全局"
        case .enabled: return "开启"
        case .disabled: return "关闭"
        }
    }
}

struct SiteControl: Codable, Equatable, Identifiable {
    var host: String
    var networkBlocking: SiteControlMode = .inherit
    var trackerBlocking: SiteControlMode = .inherit
    var cosmeticCleanup: SiteControlMode = .inherit
    var autoReader: SiteControlMode = .inherit
    var darkMode: SiteControlMode = .inherit
    var desktopUserAgent: SiteControlMode = .inherit

    init(
        host: String,
        networkBlocking: SiteControlMode = .inherit,
        trackerBlocking: SiteControlMode = .inherit,
        cosmeticCleanup: SiteControlMode = .inherit,
        autoReader: SiteControlMode = .inherit,
        darkMode: SiteControlMode = .inherit,
        desktopUserAgent: SiteControlMode = .inherit
    ) {
        self.host = host
        self.networkBlocking = networkBlocking
        self.trackerBlocking = trackerBlocking
        self.cosmeticCleanup = cosmeticCleanup
        self.autoReader = autoReader
        self.darkMode = darkMode
        self.desktopUserAgent = desktopUserAgent
    }

    private enum CodingKeys: String, CodingKey {
        case host, networkBlocking, trackerBlocking, cosmeticCleanup, autoReader
        case darkMode, desktopUserAgent
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        host = try container.decode(String.self, forKey: .host)
        networkBlocking = try container.decodeIfPresent(SiteControlMode.self, forKey: .networkBlocking) ?? .inherit
        trackerBlocking = try container.decodeIfPresent(SiteControlMode.self, forKey: .trackerBlocking) ?? .inherit
        cosmeticCleanup = try container.decodeIfPresent(SiteControlMode.self, forKey: .cosmeticCleanup) ?? .inherit
        autoReader = try container.decodeIfPresent(SiteControlMode.self, forKey: .autoReader) ?? .inherit
        darkMode = try container.decodeIfPresent(SiteControlMode.self, forKey: .darkMode) ?? .inherit
        desktopUserAgent = try container.decodeIfPresent(SiteControlMode.self, forKey: .desktopUserAgent) ?? .inherit
    }

    var id: String { host }

    var hasOverride: Bool {
        networkBlocking != .inherit || trackerBlocking != .inherit ||
            cosmeticCleanup != .inherit || autoReader != .inherit ||
            darkMode != .inherit || desktopUserAgent != .inherit
    }
}

struct EffectiveSiteControl: Equatable {
    let networkBlockingEnabled: Bool
    let trackerBlockingEnabled: Bool
    let cosmeticCleanupEnabled: Bool
    let autoReaderEnabled: Bool
    let webDarkMode: WebDarkModePreference
    let desktopUserAgentEnabled: Bool
}

struct BlockStats: Codable, Equatable {
    var ads = 0
    var trackers = 0
    var malicious = 0
    var popups = 0
    var cookieBanners = 0

    var total: Int { ads + trackers + malicious + popups + cookieBanners }

    init(ads: Int = 0, trackers: Int = 0, malicious: Int = 0, popups: Int = 0, cookieBanners: Int = 0) {
        self.ads = ads
        self.trackers = trackers
        self.malicious = malicious
        self.popups = popups
        self.cookieBanners = cookieBanners
    }

    private enum CodingKeys: String, CodingKey {
        case ads, trackers, malicious, popups, cookieBanners
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ads = try container.decodeIfPresent(Int.self, forKey: .ads) ?? 0
        trackers = try container.decodeIfPresent(Int.self, forKey: .trackers) ?? 0
        malicious = try container.decodeIfPresent(Int.self, forKey: .malicious) ?? 0
        popups = try container.decodeIfPresent(Int.self, forKey: .popups) ?? 0
        cookieBanners = try container.decodeIfPresent(Int.self, forKey: .cookieBanners) ?? 0
    }

    mutating func add(_ other: BlockStats) {
        ads += max(0, other.ads)
        trackers += max(0, other.trackers)
        malicious += max(0, other.malicious)
        popups += max(0, other.popups)
        cookieBanners += max(0, other.cookieBanners)
    }
}

struct SiteBlockStats: Codable, Equatable, Identifiable {
    let host: String
    var stats: BlockStats

    var id: String { host }
}

enum BlockCategory: Int, Codable, CaseIterable, Hashable, Identifiable {
    case advertisement = 0
    case tracker = 1
    case popup = 2
    case cookieBanner = 3
    case malicious = 4

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .advertisement: return "广告元素"
        case .tracker: return "跟踪器"
        case .malicious: return "恶意内容"
        case .popup: return "弹窗"
        case .cookieBanner: return "Cookie 提示"
        }
    }
}

enum BlockEventEngine: Equatable {
    case resourceCleanup
    case elementCleanup

    var label: String {
        switch self {
        case .resourceCleanup: return "WebKit 资源清理"
        case .elementCleanup: return "WebKit 页面清理"
        }
    }
}

struct ObservedBlockResource: Equatable {
    let host: String
    let category: BlockCategory
}

struct BlockEventDraft: Equatable {
    let category: BlockCategory
    let count: Int
    let resourceHost: String?
    let engine: BlockEventEngine
}

struct BlockEvent: Identifiable, Equatable {
    let id: String
    let tabID: String
    let pageURL: String
    let category: BlockCategory
    let count: Int
    let occurredAt: Date
    let resourceHost: String?
    let engine: BlockEventEngine

    init(
        id: String,
        tabID: String,
        pageURL: String,
        category: BlockCategory,
        count: Int,
        occurredAt: Date,
        resourceHost: String? = nil,
        engine: BlockEventEngine = .elementCleanup
    ) {
        self.id = id
        self.tabID = tabID
        self.pageURL = pageURL
        self.category = category
        self.count = count
        self.occurredAt = occurredAt
        self.resourceHost = resourceHost
        self.engine = engine
    }
}

enum BlockObservationPolicy {
    static let maximumResourceDetails = 50

    static func resources(from value: Any?) -> [ObservedBlockResource] {
        guard let values = value as? [[String: Any]] else { return [] }
        return values.prefix(maximumResourceDetails).compactMap { item in
            guard let rawURL = item["url"] as? String else { return nil }
            let host = URLPolicy.rawHost(rawURL)
            guard !host.isEmpty else { return nil }
            let category: BlockCategory
            switch item["category"] as? String {
            case "tracker": category = .tracker
            case "malicious": category = .malicious
            default: return nil
            }
            return ObservedBlockResource(host: host, category: category)
        }
    }

    static func eventDrafts(stats: BlockStats, resources: [ObservedBlockResource]) -> [BlockEventDraft] {
        var drafts: [BlockEventDraft] = []
        var detailBudget: [BlockCategory: Int] = [
            .tracker: max(0, stats.trackers),
            .malicious: max(0, stats.malicious)
        ]
        for resource in resources where detailBudget[resource.category, default: 0] > 0 {
            drafts.append(
                BlockEventDraft(
                    category: resource.category,
                    count: 1,
                    resourceHost: resource.host,
                    engine: .resourceCleanup
                )
            )
            detailBudget[resource.category, default: 0] -= 1
        }
        var detailedCounts: [BlockCategory: Int] = [:]
        drafts.forEach { detailedCounts[$0.category, default: 0] += 1 }
        let totals: [(BlockCategory, Int)] = [
            (.advertisement, stats.ads), (.tracker, stats.trackers),
            (.malicious, stats.malicious), (.popup, stats.popups),
            (.cookieBanner, stats.cookieBanners)
        ]
        for (category, total) in totals {
            let remaining = max(0, total - detailedCounts[category, default: 0])
            if remaining > 0 {
                drafts.append(
                    BlockEventDraft(
                        category: category,
                        count: remaining,
                        resourceHost: nil,
                        engine: .elementCleanup
                    )
                )
            }
        }
        return drafts
    }
}

enum BlockEventPresentationPolicy {
    static let maximumVisibleEvents = 200

    static func visibleEvents(
        _ events: [BlockEvent],
        tabID: String,
        limit: Int = maximumVisibleEvents
    ) -> [BlockEvent] {
        guard limit > 0 else { return [] }
        return Array(
            events
                .filter { $0.tabID == tabID && $0.count > 0 }
                .sorted { lhs, rhs in
                    if lhs.occurredAt != rhs.occurredAt {
                        return lhs.occurredAt > rhs.occurredAt
                    }
                    return lhs.id < rhs.id
                }
                .prefix(limit)
        )
    }
}

enum BlockingPolicy {
    static func normalizedSiteControls(_ controls: [SiteControl]) -> [SiteControl] {
        var byHost: [String: SiteControl] = [:]
        controls.forEach { control in
            var normalized = control
            normalized.host = control.host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !normalized.host.isEmpty, normalized.hasOverride {
                byHost[normalized.host] = normalized
            }
        }
        return byHost.keys.sorted().compactMap { byHost[$0] }
    }

    static func siteControl(for rawURL: String, controls: [SiteControl]) -> SiteControl {
        let host = WebAppearancePolicy.host(for: rawURL)
        return controls.first(where: { $0.host == host }) ?? SiteControl(host: host)
    }

    static func effectiveControl(for rawURL: String, settings: BrowserSettings) -> EffectiveSiteControl {
        let control = siteControl(for: rawURL, controls: settings.siteControls)
        return EffectiveSiteControl(
            networkBlockingEnabled: resolve(control.networkBlocking, fallback: settings.blockAds),
            trackerBlockingEnabled: resolve(control.trackerBlocking, fallback: settings.blockAds),
            cosmeticCleanupEnabled: resolve(control.cosmeticCleanup, fallback: settings.blockAds),
            autoReaderEnabled: resolve(control.autoReader, fallback: false),
            webDarkMode: resolveWebDarkMode(control.darkMode, fallback: settings.webDarkMode),
            desktopUserAgentEnabled: resolve(
                control.desktopUserAgent,
                fallback: WebAppearancePolicy.usesDesktopUserAgent(for: rawURL, settings: settings)
            )
        )
    }

    static func normalizedSiteStats(_ entries: [SiteBlockStats]) -> [SiteBlockStats] {
        var byHost: [String: BlockStats] = [:]
        entries.forEach { entry in
            let host = entry.host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !host.isEmpty else { return }
            var stats = byHost[host] ?? BlockStats()
            stats.add(entry.stats)
            byHost[host] = stats
        }
        return byHost.keys.sorted().compactMap { host in
            byHost[host].map { SiteBlockStats(host: host, stats: $0) }
        }
    }

    static func cumulativeStats(_ entries: [SiteBlockStats]) -> BlockStats {
        entries.reduce(into: BlockStats()) { result, entry in
            result.add(entry.stats)
        }
    }

    private static func resolve(_ mode: SiteControlMode, fallback: Bool) -> Bool {
        switch mode {
        case .inherit: return fallback
        case .enabled: return true
        case .disabled: return false
        }
    }

    private static func resolveWebDarkMode(
        _ mode: SiteControlMode,
        fallback: WebDarkModePreference
    ) -> WebDarkModePreference {
        switch mode {
        case .inherit: return fallback
        case .enabled: return .dark
        case .disabled: return .light
        }
    }
}
