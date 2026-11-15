import Foundation

enum BrowserPersistenceKey: String, CaseIterable {
    case session = "browser_session"
    case archivedTabs = "browser_archived_tabs"
    case settings = "browser_settings"
    case readerSettings = "reader_settings"
    case history = "browser_history"
    case savedItems = "browser_saved_items"
    case allowedHosts = "allowed_hosts"
    case sitePermissions = "site_permissions"
    case quickSites = "browser_quick_sites"
    case siteBlockStats = "browser_site_block_stats"
}

/// File-backed JSON store that keeps persistence I/O off the main thread while
/// transparently migrating legacy `UserDefaults` payloads on first read.
final class BrowserPersistenceStore {
    static let shared = BrowserPersistenceStore()

    let directoryURL: URL
    private let defaults: UserDefaults
    private let queue = DispatchQueue(label: "com.zhuobrowser.persistence", qos: .utility)

    init(directoryURL: URL? = nil, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let directoryURL {
            self.directoryURL = directoryURL
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.directoryURL = base
                .appendingPathComponent("ZhuoBrowser", isDirectory: true)
                .appendingPathComponent("state", isDirectory: true)
        }
    }

    func fileURL(for key: BrowserPersistenceKey) -> URL {
        directoryURL.appendingPathComponent("\(key.rawValue).json", isDirectory: false)
    }

    func load<T: Decodable & Encodable>(
        _ key: BrowserPersistenceKey,
        as type: T.Type,
        default fallback: () -> T
    ) -> T {
        let targetURL = fileURL(for: key)
        if let data = try? Data(contentsOf: targetURL),
           let decoded = try? JSONDecoder().decode(T.self, from: data) {
            return decoded
        }

        if let legacyData = defaults.data(forKey: key.rawValue),
           let migrated = try? JSONDecoder().decode(T.self, from: legacyData) {
            save(migrated, for: key)
            return migrated
        }

        return fallback()
    }

    func save<T: Encodable>(_ value: T, for key: BrowserPersistenceKey) {
        let targetURL = fileURL(for: key)
        let folderURL = directoryURL
        queue.async {
            do {
                try FileManager.default.createDirectory(
                    at: folderURL,
                    withIntermediateDirectories: true
                )
                let data = try JSONEncoder().encode(value)
                try data.write(to: targetURL, options: .atomic)
            } catch {
                // Keep in-memory state responsive if disk write encounters transient error.
            }
        }
    }

    func remove(_ key: BrowserPersistenceKey) {
        let targetURL = fileURL(for: key)
        let defaultsKey = key.rawValue
        let userDefaults = defaults
        queue.async {
            try? FileManager.default.removeItem(at: targetURL)
            userDefaults.removeObject(forKey: defaultsKey)
        }
    }

    /// Waits for all queued background writes to complete on disk.
    func flush() {
        queue.sync {}
    }
}
