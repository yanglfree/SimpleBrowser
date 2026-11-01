import Foundation

/// Persists per-tab page snapshots plus the open-tab list.
///
/// Three tiers cooperate here:
/// * **hot / warm** tabs live inside `BrowserSession` as real `WKWebView` instances;
/// * **cold** tabs keep only a `TabStateSnapshot` here (memory first, disk second);
/// * a relaunch reads the tab list + snapshots back, so the browser opens exactly
///   where the user left it.
///
/// The store is deliberately bounded (snapshot count + per-snapshot byte cap) so a
/// long browsing session can never grow the on-disk state without limit.
public final class TabStateStore {
    public static let shared = TabStateStore()

    /// Snapshot payloads larger than this are dropped instead of persisted.
    public static let maxSnapshotBytes = 4 * 1024 * 1024
    /// Upper bound of frozen snapshots kept on disk (least recently used are evicted).
    public static let maxPersistedSnapshots = 16

    public let isPersistenceEnabled: Bool

    private let fileManager: FileManager
    private let rootURL: URL?
    private let ioQueue = DispatchQueue(label: "com.youdroid.zhuobrowser.tab-state", qos: .utility)

    private var memoryCache: [String: TabStateSnapshot] = [:]
    private var memoryOrder: [String] = []

    public init(fileManager: FileManager = .default, isPersistenceEnabled: Bool = !RuntimeEnvironment.isRunningUnitTests) {
        self.fileManager = fileManager
        self.isPersistenceEnabled = isPersistenceEnabled

        if isPersistenceEnabled,
           let base = try? fileManager.url(
               for: .applicationSupportDirectory,
               in: .userDomainMask,
               appropriateFor: nil,
               create: true
           ) {
            let root = base
                .appendingPathComponent("ZhuoBrowserMac", isDirectory: true)
                .appendingPathComponent("TabState", isDirectory: true)
            try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)
            self.rootURL = root
        } else {
            self.rootURL = nil
        }
    }

    // MARK: - Snapshots

    public func snapshot(for tabID: String) -> TabStateSnapshot? {
        if let cached = memoryCache[tabID] {
            touch(tabID)
            return cached
        }
        guard isPersistenceEnabled, let url = snapshotURL(for: tabID) else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let snapshot = try? JSONDecoder().decode(TabStateSnapshot.self, from: data) else {
            try? fileManager.removeItem(at: url)
            return nil
        }
        memoryCache[tabID] = snapshot
        touch(tabID)
        return snapshot
    }

    /// - Parameter persistToDisk: pass `false` for private tabs, whose state must never
    ///   leave the process even if the tab is frozen to save memory.
    public func store(
        _ snapshot: TabStateSnapshot,
        for tabID: String,
        persistToDisk: Bool = true,
        synchronously: Bool = false
    ) {
        guard snapshot.hasRestorableState else { return }
        if let rawBytes = snapshot.interactionState?.count, rawBytes > Self.maxSnapshotBytes {
            return
        }

        memoryCache[tabID] = snapshot
        touch(tabID)

        guard persistToDisk, isPersistenceEnabled, let url = snapshotURL(for: tabID) else { return }
        let writeWork = { [weak self] in
            guard let self else { return }
            guard let encoded = try? JSONEncoder().encode(snapshot),
                  encoded.count <= Self.maxSnapshotBytes else { return }
            try? encoded.write(to: url, options: .atomic)
            self.evictIfNeeded(protecting: tabID)
        }
        if synchronously {
            ioQueue.sync(execute: writeWork)
        } else {
            ioQueue.async(execute: writeWork)
        }
    }

    public func removeSnapshot(for tabID: String) {
        memoryCache.removeValue(forKey: tabID)
        memoryOrder.removeAll { $0 == tabID }
        guard isPersistenceEnabled, let url = snapshotURL(for: tabID) else { return }
        ioQueue.async { [weak self] in
            try? self?.fileManager.removeItem(at: url)
        }
    }

    /// Drops snapshots whose tab no longer exists (closed tabs, crashed sessions).
    public func pruneSnapshots(keeping tabIDs: Set<String>) {
        // Copy the keys first: `removeSnapshot` mutates the cache we would be iterating.
        let orphanedIDs = Array(memoryCache.keys).filter { !tabIDs.contains($0) }
        for id in orphanedIDs {
            removeSnapshot(for: id)
        }
        guard isPersistenceEnabled, let rootURL else { return }
        ioQueue.async { [weak self] in
            guard let self else { return }
            let files = (try? self.fileManager.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil)) ?? []
            for file in files where file.pathExtension == "snapshot" {
                let id = file.deletingPathExtension().lastPathComponent
                if !tabIDs.contains(id) {
                    try? self.fileManager.removeItem(at: file)
                }
            }
        }
    }

    public var cachedSnapshotCount: Int {
        memoryCache.count
    }

    // MARK: - Tab session (open tab list)

    public func loadTabSession() -> [PersistedTabState]? {
        guard isPersistenceEnabled, let url = sessionURL else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([PersistedTabState].self, from: data)
    }

    public func saveTabSession(_ tabs: [PersistedTabState], synchronously: Bool = false) {
        guard isPersistenceEnabled, let url = sessionURL else { return }
        let writeWork: () -> Void = {
            guard let data = try? JSONEncoder().encode(tabs) else { return }
            try? data.write(to: url, options: .atomic)
        }
        if synchronously {
            ioQueue.sync(execute: writeWork)
        } else {
            ioQueue.async(execute: writeWork)
        }
    }

    public func clearSession() {
        memoryCache.removeAll()
        memoryOrder.removeAll()
        guard isPersistenceEnabled, let rootURL else { return }
        ioQueue.async { [weak self] in
            try? self?.fileManager.removeItem(at: rootURL)
            try? self?.fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        }
    }

    // MARK: - Private

    private var sessionURL: URL? {
        guard let rootURL else { return nil }
        return rootURL.appendingPathComponent("session.json")
    }

    private func snapshotURL(for tabID: String) -> URL? {
        guard let rootURL else { return nil }
        let safeID = tabID.replacingOccurrences(of: "/", with: "_")
        return rootURL.appendingPathComponent(safeID).appendingPathExtension("snapshot")
    }

    private func touch(_ tabID: String) {
        memoryOrder.removeAll { $0 == tabID }
        memoryOrder.append(tabID)
    }

    private func evictIfNeeded(protecting tabID: String) {
        guard let rootURL else { return }
        let files = (try? fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []

        let snapshots = files
            .filter { $0.pathExtension == "snapshot" }
            .sorted { lhs, rhs in
                let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return l > r
            }

        guard snapshots.count > Self.maxPersistedSnapshots else { return }
        for file in snapshots.dropFirst(Self.maxPersistedSnapshots) {
            let id = file.deletingPathExtension().lastPathComponent
            if id == tabID { continue }
            try? fileManager.removeItem(at: file)
        }
    }
}
