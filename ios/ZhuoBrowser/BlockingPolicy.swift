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

    var id: String { host }

    var hasOverride: Bool {
        networkBlocking != .inherit || trackerBlocking != .inherit ||
            cosmeticCleanup != .inherit || autoReader != .inherit
    }
}

struct EffectiveSiteControl: Equatable {
    let networkBlockingEnabled: Bool
    let trackerBlockingEnabled: Bool
    let cosmeticCleanupEnabled: Bool
    let autoReaderEnabled: Bool
}

struct BlockStats: Codable, Equatable {
    var ads = 0
    var trackers = 0
    var popups = 0
    var cookieBanners = 0

    var total: Int { ads + trackers + popups + cookieBanners }

    mutating func add(_ other: BlockStats) {
        ads += max(0, other.ads)
        trackers += max(0, other.trackers)
        popups += max(0, other.popups)
        cookieBanners += max(0, other.cookieBanners)
    }
}

struct SiteBlockStats: Codable, Equatable, Identifiable {
    let host: String
    var stats: BlockStats

    var id: String { host }
}

enum BlockCategory: Int, Codable, CaseIterable, Identifiable {
    case advertisement = 0
    case tracker = 1
    case popup = 2
    case cookieBanner = 3

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .advertisement: return "广告元素"
        case .tracker: return "跟踪器"
        case .popup: return "弹窗"
        case .cookieBanner: return "Cookie 提示"
        }
    }
}

struct BlockEvent: Identifiable, Equatable {
    let id: String
    let tabID: String
    let pageURL: String
    let category: BlockCategory
    let count: Int
    let occurredAt: Date
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
            autoReaderEnabled: resolve(control.autoReader, fallback: false)
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

    private static func resolve(_ mode: SiteControlMode, fallback: Bool) -> Bool {
        switch mode {
        case .inherit: return fallback
        case .enabled: return true
        case .disabled: return false
        }
    }
}
