import Foundation

public enum SearchEngine: String, CaseIterable, Identifiable, Codable {
    case bing = "Bing"
    case google = "Google"
    case baidu = "Baidu"
    case duckDuckGo = "DuckDuckGo"

    public var id: String { rawValue }

    public static func from(_ rawString: String) -> SearchEngine? {
        let trimmed = rawString.trimmingCharacters(in: .whitespacesAndNewlines)
        if let exact = SearchEngine(rawValue: trimmed) {
            return exact
        }
        return SearchEngine.allCases.first {
            $0.rawValue.caseInsensitiveCompare(trimmed) == .orderedSame
        }
    }

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

public enum SafeBrowsingLevel: String, CaseIterable, Identifiable, Codable {
    case enhanced = "enhanced"
    case standard = "standard"
    case disabled = "disabled"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .enhanced:
            return "增强型保护"
        case .standard:
            return "标准保护"
        case .disabled:
            return "不保护（不建议）"
        }
    }

    public var detailDescription: String {
        switch self {
        case .enhanced:
            return "根据系统向安全云端发送的浏览数据，实时提供 AI 赋能的保护，防范危险的网站、下载内容和扩展程序。"
        case .standard:
            return "防范已知危险的网站、下载内容和扩展程序。当您访问某个网站时，浏览器会通过可能隐藏 IP 地址的隐私保护服务器将经过混淆处理的网址片段发送给云端。如果网站有可疑行为，系统也会发送完整网址和少量网页内容。"
        case .disabled:
            return "不会防范危险的网站、下载内容和扩展程序。您在其他安全产品中的设置不受影响。"
        }
    }
}

public enum SecureDNSProvider: String, CaseIterable, Identifiable, Codable {
    case system = "system"
    case google = "google"
    case cloudflare = "cloudflare"
    case alidns = "alidns"
    case dnspod = "dnspod"
    case custom = "custom"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .system:
            return "操作系统默认设置（若有）"
        case .google:
            return "Google (Public DNS)"
        case .cloudflare:
            return "Cloudflare (1.1.1.1)"
        case .alidns:
            return "阿里公共 DNS (AliDNS)"
        case .dnspod:
            return "腾讯 DNSPod"
        case .custom:
            return "自定义提供商"
        }
    }

    public var defaultDoHURL: String {
        switch self {
        case .system:
            return ""
        case .google:
            return "https://dns.google/dns-query"
        case .cloudflare:
            return "https://cloudflare-dns.com/dns-query"
        case .alidns:
            return "https://dns.alidns.com/dns-query"
        case .dnspod:
            return "https://doh.pub/dns-query"
        case .custom:
            return ""
        }
    }
}

public struct PersistedBrowserSettings: Codable, Equatable {
    public var searchEngine: SearchEngine
    public var quickSitesEnabled: Bool
    public var liveWebViewBudget: Int
    public var tabHibernationEnabled: Bool
    public var adBlockEnabled: Bool
    public var cosmeticCleanupEnabled: Bool
    public var restoreSessionOnLaunch: Bool
    public var safeBrowsingLevel: SafeBrowsingLevel
    public var alwaysUseSecureConnections: Bool
    public var leakedPasswordDetectionEnabled: Bool
    public var secureDNSEnabled: Bool
    public var secureDNSProvider: SecureDNSProvider
    public var customSecureDNSURL: String
    public var javascriptJITOptimizationEnabled: Bool
    public var updatedAt: Int64
    public var hasPendingLocalChanges: Bool

    private enum CodingKeys: String, CodingKey {
        case searchEngine
        case quickSitesEnabled
        case liveWebViewBudget
        case tabHibernationEnabled
        case adBlockEnabled
        case cosmeticCleanupEnabled
        case restoreSessionOnLaunch
        case safeBrowsingLevel
        case alwaysUseSecureConnections
        case leakedPasswordDetectionEnabled
        case secureDNSEnabled
        case secureDNSProvider
        case customSecureDNSURL
        case javascriptJITOptimizationEnabled
        case updatedAt
        case hasPendingLocalChanges
    }

    public init(
        searchEngine: SearchEngine = .bing,
        quickSitesEnabled: Bool = true,
        liveWebViewBudget: Int = MemoryBudgetPolicy.defaultLiveBudget,
        tabHibernationEnabled: Bool = false,
        adBlockEnabled: Bool = true,
        cosmeticCleanupEnabled: Bool = true,
        restoreSessionOnLaunch: Bool = true,
        safeBrowsingLevel: SafeBrowsingLevel = .standard,
        alwaysUseSecureConnections: Bool = false,
        leakedPasswordDetectionEnabled: Bool = true,
        secureDNSEnabled: Bool = true,
        secureDNSProvider: SecureDNSProvider = .system,
        customSecureDNSURL: String = "",
        javascriptJITOptimizationEnabled: Bool = true,
        updatedAt: Int64 = 0,
        hasPendingLocalChanges: Bool = false
    ) {
        self.searchEngine = searchEngine
        self.quickSitesEnabled = quickSitesEnabled
        self.liveWebViewBudget = max(MemoryBudgetPolicy.minLiveBudget, min(liveWebViewBudget, MemoryBudgetPolicy.maxLiveBudget))
        self.tabHibernationEnabled = tabHibernationEnabled
        self.adBlockEnabled = adBlockEnabled
        self.cosmeticCleanupEnabled = cosmeticCleanupEnabled
        self.restoreSessionOnLaunch = restoreSessionOnLaunch
        self.safeBrowsingLevel = safeBrowsingLevel
        self.alwaysUseSecureConnections = alwaysUseSecureConnections
        self.leakedPasswordDetectionEnabled = leakedPasswordDetectionEnabled
        self.secureDNSEnabled = secureDNSEnabled
        self.secureDNSProvider = secureDNSProvider
        self.customSecureDNSURL = customSecureDNSURL
        self.javascriptJITOptimizationEnabled = javascriptJITOptimizationEnabled
        self.updatedAt = updatedAt
        self.hasPendingLocalChanges = hasPendingLocalChanges
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.searchEngine = try container.decodeIfPresent(SearchEngine.self, forKey: .searchEngine) ?? .bing
        self.quickSitesEnabled = try container.decodeIfPresent(Bool.self, forKey: .quickSitesEnabled) ?? true
        let budget = try container.decodeIfPresent(Int.self, forKey: .liveWebViewBudget) ?? MemoryBudgetPolicy.defaultLiveBudget
        self.liveWebViewBudget = max(MemoryBudgetPolicy.minLiveBudget, min(budget, MemoryBudgetPolicy.maxLiveBudget))
        self.tabHibernationEnabled = try container.decodeIfPresent(Bool.self, forKey: .tabHibernationEnabled) ?? false
        self.adBlockEnabled = try container.decodeIfPresent(Bool.self, forKey: .adBlockEnabled) ?? true
        self.cosmeticCleanupEnabled = try container.decodeIfPresent(Bool.self, forKey: .cosmeticCleanupEnabled) ?? true
        self.restoreSessionOnLaunch = try container.decodeIfPresent(Bool.self, forKey: .restoreSessionOnLaunch) ?? true
        self.safeBrowsingLevel = try container.decodeIfPresent(SafeBrowsingLevel.self, forKey: .safeBrowsingLevel) ?? .standard
        self.alwaysUseSecureConnections = try container.decodeIfPresent(Bool.self, forKey: .alwaysUseSecureConnections) ?? false
        self.leakedPasswordDetectionEnabled = try container.decodeIfPresent(Bool.self, forKey: .leakedPasswordDetectionEnabled) ?? true
        self.secureDNSEnabled = try container.decodeIfPresent(Bool.self, forKey: .secureDNSEnabled) ?? true
        self.secureDNSProvider = try container.decodeIfPresent(SecureDNSProvider.self, forKey: .secureDNSProvider) ?? .system
        self.customSecureDNSURL = try container.decodeIfPresent(String.self, forKey: .customSecureDNSURL) ?? ""
        self.javascriptJITOptimizationEnabled = try container.decodeIfPresent(Bool.self, forKey: .javascriptJITOptimizationEnabled) ?? true
        self.updatedAt = try container.decodeIfPresent(Int64.self, forKey: .updatedAt) ?? 0
        self.hasPendingLocalChanges = try container.decodeIfPresent(Bool.self, forKey: .hasPendingLocalChanges) ?? false
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
        static let restoreSessionOnLaunch = "ZhuoBrowser_RestoreSessionOnLaunch"
        static let tabHibernationEnabled = "ZhuoBrowser_TabHibernationEnabled"
        static let safeBrowsingLevel = "ZhuoBrowser_SafeBrowsingLevel"
        static let alwaysUseSecureConnections = "ZhuoBrowser_AlwaysUseSecureConnections"
        static let leakedPasswordDetectionEnabled = "ZhuoBrowser_LeakedPasswordDetectionEnabled"
        static let secureDNSEnabled = "ZhuoBrowser_SecureDNSEnabled"
        static let secureDNSProvider = "ZhuoBrowser_SecureDNSProvider"
        static let customSecureDNSURL = "ZhuoBrowser_CustomSecureDNSURL"
        static let javascriptJITOptimizationEnabled = "ZhuoBrowser_JavascriptJITOptimizationEnabled"
        static let updatedAt = "ZhuoBrowser_SettingsUpdatedAt"
        static let hasPendingLocalChanges = "ZhuoBrowser_SettingsHasPendingLocalChanges"
    }

    /// Unit tests mutate settings to exercise policies; they must not leak into the
    /// user's real preferences.
    private let persistsAutomatically: Bool
    private let userDefaults: UserDefaults
    private let settingsFileURL: URL?
    private var isApplyingRemoteSettings: Bool = false
    private let ioQueue = DispatchQueue(label: "com.youdroid.zhuobrowser.mac.settings", qos: .utility)

    /// Monotonic millisecond timestamp of the most recent settings change (local or cloud).
    public private(set) var updatedAt: Int64

    /// Indicates whether local settings have been modified since the last successful cloud sync.
    public private(set) var hasPendingLocalChanges: Bool

    /// Optional callback invoked when the user mutates any setting locally.
    public var onLocalSettingsChanged: ((BrowserSettings) -> Void)?

    @Published public var searchEngine: SearchEngine {
        didSet {
            guard searchEngine != oldValue else { return }
            recordLocalMutation()
        }
    }

    @Published public var quickSitesEnabled: Bool {
        didSet {
            guard quickSitesEnabled != oldValue else { return }
            recordLocalMutation()
        }
    }

    /// Only takes effect when `tabHibernationEnabled` is on.
    @Published public var liveWebViewBudget: Int {
        didSet {
            let clamped = max(MemoryBudgetPolicy.minLiveBudget, min(liveWebViewBudget, MemoryBudgetPolicy.maxLiveBudget))
            if liveWebViewBudget != clamped {
                liveWebViewBudget = clamped
                return
            }
            guard liveWebViewBudget != oldValue else { return }
            recordLocalMutation()
        }
    }

    /// Opt-in memory-saver mode. **Off by default**: every open tab keeps its live
    /// `WKWebView`, so switching tabs never reloads a page.
    @Published public var tabHibernationEnabled: Bool {
        didSet {
            guard tabHibernationEnabled != oldValue else { return }
            recordLocalMutation()
        }
    }

    @Published public var adBlockEnabled: Bool {
        didSet {
            guard adBlockEnabled != oldValue else { return }
            recordLocalMutation()
        }
    }

    @Published public var cosmeticCleanupEnabled: Bool {
        didSet {
            guard cosmeticCleanupEnabled != oldValue else { return }
            recordLocalMutation()
        }
    }

    /// Reopens the tabs from the previous launch.
    @Published public var restoreSessionOnLaunch: Bool {
        didSet {
            guard restoreSessionOnLaunch != oldValue else { return }
            recordLocalMutation()
        }
    }

    /// Safe Browsing protection tier (.enhanced, .standard, .disabled).
    @Published public var safeBrowsingLevel: SafeBrowsingLevel {
        didSet {
            guard safeBrowsingLevel != oldValue else { return }
            recordLocalMutation()
        }
    }

    /// When true, automatically upgrades public http:// requests to https:// and warns on insecure transport.
    @Published public var alwaysUseSecureConnections: Bool {
        didSet {
            guard alwaysUseSecureConnections != oldValue else { return }
            recordLocalMutation()
        }
    }

    /// Warns user when passwords are known to be exposed in a data breach.
    @Published public var leakedPasswordDetectionEnabled: Bool {
        didSet {
            guard leakedPasswordDetectionEnabled != oldValue else { return }
            recordLocalMutation()
        }
    }

    /// Uses secure DNS (DNS-over-HTTPS) to prevent ISP/network snooping.
    @Published public var secureDNSEnabled: Bool {
        didSet {
            guard secureDNSEnabled != oldValue else { return }
            recordLocalMutation()
        }
    }

    /// Active Secure DNS provider preset or custom endpoint.
    @Published public var secureDNSProvider: SecureDNSProvider {
        didSet {
            guard secureDNSProvider != oldValue else { return }
            recordLocalMutation()
        }
    }

    /// Custom DoH server template URL (used when secureDNSProvider == .custom).
    @Published public var customSecureDNSURL: String {
        didSet {
            guard customSecureDNSURL != oldValue else { return }
            recordLocalMutation()
        }
    }

    /// Accelerates script execution via JIT; can be toggled off for hardened security.
    @Published public var javascriptJITOptimizationEnabled: Bool {
        didSet {
            guard javascriptJITOptimizationEnabled != oldValue else { return }
            recordLocalMutation()
        }
    }

    public init(
        persistsAutomatically: Bool = !RuntimeEnvironment.isRunningUnitTests,
        userDefaults: UserDefaults? = nil,
        settingsFileURL: URL? = nil
    ) {
        self.persistsAutomatically = persistsAutomatically

        let resolvedDefaults: UserDefaults
        let resolvedFileURL: URL?
        if persistsAutomatically {
            resolvedDefaults = userDefaults ?? .standard
            if let settingsFileURL {
                resolvedFileURL = settingsFileURL
            } else if let base = try? FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ) {
                let dir = base.appendingPathComponent("ZhuoBrowserMac", isDirectory: true)
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                resolvedFileURL = dir.appendingPathComponent("settings.json")
            } else {
                resolvedFileURL = nil
            }
        } else {
            resolvedDefaults = userDefaults
                ?? UserDefaults(suiteName: "com.youdroid.zhuobrowser.mac.settings-tests.\(UUID().uuidString)")
                ?? .standard
            resolvedFileURL = settingsFileURL
        }

        self.userDefaults = resolvedDefaults
        self.settingsFileURL = resolvedFileURL

        let fileSnapshot = Self.loadFileSnapshot(from: resolvedFileURL)
        let defaultsSnapshot = Self.loadDefaultsSnapshot(from: resolvedDefaults)

        let chosen: PersistedBrowserSettings
        let needsMigrationWrite: Bool

        if let fileSnapshot, let defaultsSnapshot {
            if fileSnapshot.updatedAt > defaultsSnapshot.updatedAt {
                chosen = fileSnapshot
                needsMigrationWrite = true
            } else if defaultsSnapshot.updatedAt == 0 && defaultsSnapshot != fileSnapshot {
                var migrated = defaultsSnapshot
                migrated.updatedAt = max(Self.currentTimestampMillis(), fileSnapshot.updatedAt + 1)
                migrated.hasPendingLocalChanges = true
                chosen = migrated
                needsMigrationWrite = true
            } else {
                chosen = defaultsSnapshot
                needsMigrationWrite = false
            }
        } else if let defaultsSnapshot {
            if defaultsSnapshot.updatedAt == 0 && persistsAutomatically {
                var migrated = defaultsSnapshot
                migrated.updatedAt = Self.currentTimestampMillis()
                migrated.hasPendingLocalChanges = true
                chosen = migrated
                needsMigrationWrite = true
            } else {
                chosen = defaultsSnapshot
                needsMigrationWrite = (fileSnapshot == nil && persistsAutomatically)
            }
        } else if let fileSnapshot {
            chosen = fileSnapshot
            needsMigrationWrite = true
        } else {
            chosen = PersistedBrowserSettings()
            needsMigrationWrite = false
        }

        self.searchEngine = chosen.searchEngine
        self.quickSitesEnabled = chosen.quickSitesEnabled
        self.liveWebViewBudget = chosen.liveWebViewBudget
        self.tabHibernationEnabled = chosen.tabHibernationEnabled
        self.adBlockEnabled = chosen.adBlockEnabled
        self.cosmeticCleanupEnabled = chosen.cosmeticCleanupEnabled
        self.restoreSessionOnLaunch = chosen.restoreSessionOnLaunch
        self.safeBrowsingLevel = chosen.safeBrowsingLevel
        self.alwaysUseSecureConnections = chosen.alwaysUseSecureConnections
        self.leakedPasswordDetectionEnabled = chosen.leakedPasswordDetectionEnabled
        self.secureDNSEnabled = chosen.secureDNSEnabled
        self.secureDNSProvider = chosen.secureDNSProvider
        self.customSecureDNSURL = chosen.customSecureDNSURL
        self.javascriptJITOptimizationEnabled = chosen.javascriptJITOptimizationEnabled
        self.updatedAt = chosen.updatedAt
        self.hasPendingLocalChanges = chosen.hasPendingLocalChanges

        if needsMigrationWrite {
            persistToStorage()
        }
    }

    public static func currentTimestampMillis() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }

    public var snapshot: PersistedBrowserSettings {
        PersistedBrowserSettings(
            searchEngine: searchEngine,
            quickSitesEnabled: quickSitesEnabled,
            liveWebViewBudget: liveWebViewBudget,
            tabHibernationEnabled: tabHibernationEnabled,
            adBlockEnabled: adBlockEnabled,
            cosmeticCleanupEnabled: cosmeticCleanupEnabled,
            restoreSessionOnLaunch: restoreSessionOnLaunch,
            safeBrowsingLevel: safeBrowsingLevel,
            alwaysUseSecureConnections: alwaysUseSecureConnections,
            leakedPasswordDetectionEnabled: leakedPasswordDetectionEnabled,
            secureDNSEnabled: secureDNSEnabled,
            secureDNSProvider: secureDNSProvider,
            customSecureDNSURL: customSecureDNSURL,
            javascriptJITOptimizationEnabled: javascriptJITOptimizationEnabled,
            updatedAt: updatedAt,
            hasPendingLocalChanges: hasPendingLocalChanges
        )
    }

    /// Applies settings received from cloud sync without marking them as unsynced local edits.
    public func performRemoteUpdate(remoteUpdatedAt: Int64? = nil, _ updates: (BrowserSettings) -> Void) {
        isApplyingRemoteSettings = true
        updates(self)
        isApplyingRemoteSettings = false

        if let remoteUpdatedAt, remoteUpdatedAt > 0 {
            self.updatedAt = max(self.updatedAt, remoteUpdatedAt)
        }
        self.hasPendingLocalChanges = false
        persistToStorage()
    }

    /// Marks the current local settings as successfully pushed to the cloud.
    public func markSynced(at timestamp: Int64) {
        if timestamp > 0 {
            self.updatedAt = max(self.updatedAt, timestamp)
        }
        self.hasPendingLocalChanges = false
        persistToStorage()
    }

    /// Synchronously flushes current settings to both UserDefaults and Application Support disk storage.
    public func flushSynchronously() {
        persistToStorage(synchronously: true)
        if persistsAutomatically {
            userDefaults.synchronize()
        }
    }

    private func recordLocalMutation() {
        guard !isApplyingRemoteSettings else { return }
        self.updatedAt = max(Self.currentTimestampMillis(), self.updatedAt + 1)
        self.hasPendingLocalChanges = true
        persistToStorage(synchronously: false)
        onLocalSettingsChanged?(self)
        if persistsAutomatically && self === BrowserSettings.shared {
            Task { @MainActor in
                AccountManager.shared.scheduleSettingsSync()
            }
        }
    }

    private func persistToStorage(synchronously: Bool = false) {
        guard persistsAutomatically || settingsFileURL != nil else { return }
        let current = snapshot
        userDefaults.set(current.searchEngine.rawValue, forKey: Keys.searchEngine)
        userDefaults.set(current.quickSitesEnabled, forKey: Keys.quickSitesEnabled)
        userDefaults.set(current.liveWebViewBudget, forKey: Keys.liveWebViewBudget)
        userDefaults.set(current.tabHibernationEnabled, forKey: Keys.tabHibernationEnabled)
        userDefaults.set(current.adBlockEnabled, forKey: Keys.adBlockEnabled)
        userDefaults.set(current.cosmeticCleanupEnabled, forKey: Keys.cosmeticCleanupEnabled)
        userDefaults.set(current.restoreSessionOnLaunch, forKey: Keys.restoreSessionOnLaunch)
        userDefaults.set(current.safeBrowsingLevel.rawValue, forKey: Keys.safeBrowsingLevel)
        userDefaults.set(current.alwaysUseSecureConnections, forKey: Keys.alwaysUseSecureConnections)
        userDefaults.set(current.leakedPasswordDetectionEnabled, forKey: Keys.leakedPasswordDetectionEnabled)
        userDefaults.set(current.secureDNSEnabled, forKey: Keys.secureDNSEnabled)
        userDefaults.set(current.secureDNSProvider.rawValue, forKey: Keys.secureDNSProvider)
        userDefaults.set(current.customSecureDNSURL, forKey: Keys.customSecureDNSURL)
        userDefaults.set(current.javascriptJITOptimizationEnabled, forKey: Keys.javascriptJITOptimizationEnabled)
        userDefaults.set(current.updatedAt, forKey: Keys.updatedAt)
        userDefaults.set(current.hasPendingLocalChanges, forKey: Keys.hasPendingLocalChanges)

        guard let settingsFileURL else { return }
        let writeWork = {
            if let data = try? JSONEncoder().encode(current) {
                try? data.write(to: settingsFileURL, options: .atomic)
            }
        }
        if synchronously {
            ioQueue.sync(execute: writeWork)
        } else {
            ioQueue.async(execute: writeWork)
        }
    }

    private static func loadDefaultsSnapshot(from defaults: UserDefaults) -> PersistedBrowserSettings? {
        let allKeys = [
            Keys.searchEngine,
            Keys.liveWebViewBudget,
            Keys.adBlockEnabled,
            Keys.cosmeticCleanupEnabled,
            Keys.quickSitesEnabled,
            Keys.restoreSessionOnLaunch,
            Keys.tabHibernationEnabled,
            Keys.safeBrowsingLevel,
            Keys.alwaysUseSecureConnections,
            Keys.leakedPasswordDetectionEnabled,
            Keys.secureDNSEnabled,
            Keys.secureDNSProvider,
            Keys.customSecureDNSURL,
            Keys.javascriptJITOptimizationEnabled,
            Keys.updatedAt,
            Keys.hasPendingLocalChanges
        ]
        guard allKeys.contains(where: { defaults.object(forKey: $0) != nil }) else {
            return nil
        }

        let engine: SearchEngine = {
            if let raw = defaults.string(forKey: Keys.searchEngine),
               let parsed = SearchEngine.from(raw) {
                return parsed
            }
            return .bing
        }()

        let savedBudget = defaults.integer(forKey: Keys.liveWebViewBudget)
        let budget = savedBudget > 0
            ? max(MemoryBudgetPolicy.minLiveBudget, min(savedBudget, MemoryBudgetPolicy.maxLiveBudget))
            : MemoryBudgetPolicy.defaultLiveBudget

        let hibernation = defaults.object(forKey: Keys.tabHibernationEnabled) != nil
            ? defaults.bool(forKey: Keys.tabHibernationEnabled)
            : false

        let adBlock = defaults.object(forKey: Keys.adBlockEnabled) != nil
            ? defaults.bool(forKey: Keys.adBlockEnabled)
            : true

        let cosmetic = defaults.object(forKey: Keys.cosmeticCleanupEnabled) != nil
            ? defaults.bool(forKey: Keys.cosmeticCleanupEnabled)
            : true

        let quickSites = defaults.object(forKey: Keys.quickSitesEnabled) != nil
            ? defaults.bool(forKey: Keys.quickSitesEnabled)
            : true

        let restoreSession = defaults.object(forKey: Keys.restoreSessionOnLaunch) != nil
            ? defaults.bool(forKey: Keys.restoreSessionOnLaunch)
            : true

        let safeBrowsing: SafeBrowsingLevel = {
            if let raw = defaults.string(forKey: Keys.safeBrowsingLevel),
               let parsed = SafeBrowsingLevel(rawValue: raw) {
                return parsed
            }
            return .standard
        }()

        let alwaysHTTPS = defaults.object(forKey: Keys.alwaysUseSecureConnections) != nil
            ? defaults.bool(forKey: Keys.alwaysUseSecureConnections)
            : false

        let leakedPassword = defaults.object(forKey: Keys.leakedPasswordDetectionEnabled) != nil
            ? defaults.bool(forKey: Keys.leakedPasswordDetectionEnabled)
            : true

        let secureDNS = defaults.object(forKey: Keys.secureDNSEnabled) != nil
            ? defaults.bool(forKey: Keys.secureDNSEnabled)
            : true

        let dnsProvider: SecureDNSProvider = {
            if let raw = defaults.string(forKey: Keys.secureDNSProvider),
               let parsed = SecureDNSProvider(rawValue: raw) {
                return parsed
            }
            return .system
        }()

        let customDNS = defaults.string(forKey: Keys.customSecureDNSURL) ?? ""

        let jsJIT = defaults.object(forKey: Keys.javascriptJITOptimizationEnabled) != nil
            ? defaults.bool(forKey: Keys.javascriptJITOptimizationEnabled)
            : true

        let updatedAt = (defaults.object(forKey: Keys.updatedAt) as? NSNumber)?.int64Value ?? 0
        let hasPending = defaults.object(forKey: Keys.hasPendingLocalChanges) != nil
            ? defaults.bool(forKey: Keys.hasPendingLocalChanges)
            : false

        return PersistedBrowserSettings(
            searchEngine: engine,
            quickSitesEnabled: quickSites,
            liveWebViewBudget: budget,
            tabHibernationEnabled: hibernation,
            adBlockEnabled: adBlock,
            cosmeticCleanupEnabled: cosmetic,
            restoreSessionOnLaunch: restoreSession,
            safeBrowsingLevel: safeBrowsing,
            alwaysUseSecureConnections: alwaysHTTPS,
            leakedPasswordDetectionEnabled: leakedPassword,
            secureDNSEnabled: secureDNS,
            secureDNSProvider: dnsProvider,
            customSecureDNSURL: customDNS,
            javascriptJITOptimizationEnabled: jsJIT,
            updatedAt: updatedAt,
            hasPendingLocalChanges: hasPending
        )
    }

    private static func loadFileSnapshot(from url: URL?) -> PersistedBrowserSettings? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PersistedBrowserSettings.self, from: data)
    }
}
