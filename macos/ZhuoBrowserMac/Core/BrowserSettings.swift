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

public struct PersistedBrowserSettings: Codable, Equatable {
    public var searchEngine: SearchEngine
    public var quickSitesEnabled: Bool
    public var liveWebViewBudget: Int
    public var tabHibernationEnabled: Bool
    public var adBlockEnabled: Bool
    public var cosmeticCleanupEnabled: Bool
    public var restoreSessionOnLaunch: Bool
    public var updatedAt: Int64
    public var hasPendingLocalChanges: Bool

    public init(
        searchEngine: SearchEngine = .bing,
        quickSitesEnabled: Bool = true,
        liveWebViewBudget: Int = MemoryBudgetPolicy.defaultLiveBudget,
        tabHibernationEnabled: Bool = false,
        adBlockEnabled: Bool = true,
        cosmeticCleanupEnabled: Bool = true,
        restoreSessionOnLaunch: Bool = true,
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
        self.updatedAt = updatedAt
        self.hasPendingLocalChanges = hasPendingLocalChanges
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
            updatedAt: updatedAt,
            hasPendingLocalChanges: hasPending
        )
    }

    private static func loadFileSnapshot(from url: URL?) -> PersistedBrowserSettings? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PersistedBrowserSettings.self, from: data)
    }
}
