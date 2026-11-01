import Foundation
import WebKit

/// Persists browser cookies (both session-only and persistent) across process restarts
/// and app reinstalls (`run_release.sh`).
///
/// WebKit keeps cookies without an expiry date (`HTTPCookie.isSessionOnly`) only in the
/// NetworkProcess memory, and buffers persistent cookie writes asynchronously. Real
/// browsers promote session cookies to disk and flush cookie changes immediately so
/// "继续上次浏览" or reinstalling a build never signs the user out of websites.
public final class CookieSessionStore: NSObject, WKHTTPCookieStoreObserver {
    public static let shared = CookieSessionStore()

    /// Archives older than this are ignored (30 days).
    public static let maxArchiveAge: TimeInterval = 30 * 24 * 60 * 60
    /// Periodic flush interval while the app is running.
    public static let flushInterval: TimeInterval = 30

    private let fileManager: FileManager
    private let dataStore: WKWebsiteDataStore
    private let archiveURL: URL?
    public let isPersistenceEnabled: Bool

    private var flushTimer: Timer?
    private var debounceWorkItem: DispatchWorkItem?
    private var isRestoring: Bool = false
    private var readyCallbacks: [() -> Void] = []
    private var isObservingCookieStore: Bool = false
    private let ioQueue = DispatchQueue(label: "com.youdroid.zhuobrowser.cookie-session", qos: .utility)

    public init(
        dataStore: WKWebsiteDataStore = .default(),
        fileManager: FileManager = .default,
        isPersistenceEnabled: Bool = !RuntimeEnvironment.isRunningUnitTests
    ) {
        self.dataStore = dataStore
        self.fileManager = fileManager
        self.isPersistenceEnabled = isPersistenceEnabled

        if isPersistenceEnabled,
           let base = try? fileManager.url(
               for: .applicationSupportDirectory,
               in: .userDomainMask,
               appropriateFor: nil,
               create: true
           ) {
            let directory = base.appendingPathComponent("ZhuoBrowserMac/SessionCookies", isDirectory: true)
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            self.archiveURL = directory.appendingPathComponent("session-cookies.archive")
        } else {
            self.archiveURL = nil
        }

        super.init()

        if isPersistenceEnabled {
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.isObservingCookieStore else { return }
                self.isObservingCookieStore = true
                self.dataStore.httpCookieStore.add(self)
            }
        }
    }

    deinit {
        if isObservingCookieStore {
            let store = dataStore.httpCookieStore
            DispatchQueue.main.async {
                store.remove(self)
            }
        }
    }

    // MARK: - WKHTTPCookieStoreObserver

    public func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        guard isPersistenceEnabled, !isRestoring else { return }
        debounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.persistSessionCookies()
        }
        debounceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    // MARK: - Lifecycle

    /// Executes `block` immediately if cookie restoration is idle, or right after the
    /// in-flight launch cookie restoration finishes injecting cookies into WebKit.
    public func performWhenReady(_ block: @escaping () -> Void) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.performWhenReady(block)
            }
            return
        }
        if isRestoring {
            readyCallbacks.append(block)
        } else {
            block()
        }
    }

    /// Restores previously archived cookies into `WKHTTPCookieStore` before pages load.
    /// The archive file is kept on disk and continuously updated so an abrupt rebuild
    /// shortly after launch never loses cookies.
    public func restoreArchivedCookies(completion: (() -> Void)? = nil) {
        guard isPersistenceEnabled, let archiveURL,
              let data = try? Data(contentsOf: archiveURL) else {
            completion?()
            return
        }

        if let attributes = try? fileManager.attributesOfItem(atPath: archiveURL.path),
           let modified = attributes[.modificationDate] as? Date,
           Date().timeIntervalSince(modified) >= Self.maxArchiveAge {
            try? fileManager.removeItem(at: archiveURL)
            completion?()
            return
        }

        guard let cookies = Self.decodeCookies(from: data), !cookies.isEmpty else {
            completion?()
            return
        }

        // Rewrite in canonical PropertyList format if decoded from a legacy archive.
        if let reencoded = Self.encodeCookies(cookies) {
            ioQueue.async {
                try? reencoded.write(to: archiveURL, options: .atomic)
            }
        }

        isRestoring = true
        let cookieStore = dataStore.httpCookieStore
        let group = DispatchGroup()
        for cookie in cookies {
            group.enter()
            cookieStore.setCookie(cookie) {
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in
            guard let self else {
                completion?()
                return
            }
            self.isRestoring = false
            let callbacks = self.readyCallbacks
            self.readyCallbacks.removeAll()
            for callback in callbacks {
                callback()
            }
            completion?()
        }
    }

    /// Archives all valid (session-only and non-expired persistent) cookies to disk.
    public func persistSessionCookies(completion: (() -> Void)? = nil) {
        guard isPersistenceEnabled, archiveURL != nil else {
            completion?()
            return
        }
        dataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            guard let self, let archiveURL = self.archiveURL else {
                completion?()
                return
            }
            self.ioQueue.async {
                let now = Date()
                let validCookies = cookies.filter { cookie in
                    if let expires = cookie.expiresDate {
                        return expires > now
                    }
                    return true
                }
                if !validCookies.isEmpty, let data = Self.encodeCookies(validCookies) {
                    try? data.write(to: archiveURL, options: .atomic)
                }
                if let completion {
                    DispatchQueue.main.async {
                        completion()
                    }
                }
            }
        }
    }

    /// Synchronously flushes cookies to disk before the process exits.
    public func persistSessionCookiesSynchronously(timeout: TimeInterval = 0.6) {
        guard isPersistenceEnabled, let archiveURL else { return }
        debounceWorkItem?.cancel()
        debounceWorkItem = nil

        var finished = false
        dataStore.httpCookieStore.getAllCookies { cookies in
            let now = Date()
            let validCookies = cookies.filter { cookie in
                if let expires = cookie.expiresDate {
                    return expires > now
                }
                return true
            }
            if !validCookies.isEmpty, let data = Self.encodeCookies(validCookies) {
                try? data.write(to: archiveURL, options: .atomic)
            }
            finished = true
        }

        let deadline = Date().addingTimeInterval(timeout)
        while !finished && Date() < deadline {
            _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        ioQueue.sync {}
    }

    /// Clears the on-disk cookie archive when the user explicitly clears website cookies.
    public func clearArchive() {
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        guard isPersistenceEnabled, let archiveURL else { return }
        ioQueue.async { [weak self] in
            try? self?.fileManager.removeItem(at: archiveURL)
        }
    }

    /// Starts the periodic safety-net flush used while the app stays running.
    public func startPeriodicFlush() {
        guard isPersistenceEnabled, flushTimer == nil else { return }
        let timer = Timer(timeInterval: Self.flushInterval, repeats: true) { [weak self] _ in
            self?.persistSessionCookies()
        }
        RunLoop.main.add(timer, forMode: .common)
        flushTimer = timer
    }

    public func stopPeriodicFlush() {
        flushTimer?.invalidate()
        flushTimer = nil
    }

    // MARK: - Codec

    /// Serializes cookies as a binary PropertyList of cookie property dictionaries.
    /// Avoids `NSKeyedArchiver` with `NSSecureCoding` because `NSHTTPCookie` does not
    /// conform to `NSSecureCoding` on macOS (which caused `unarchivedObject` to fail with
    /// `NSCocoaErrorDomain Code=4864`).
    static func encodeCookies(_ cookies: [HTTPCookie]) -> Data? {
        let serialized: [[String: Any]] = cookies.compactMap { cookie in
            guard let properties = cookie.properties else { return nil }
            var dict: [String: Any] = [:]
            for (key, value) in properties {
                if value is String || value is NSNumber || value is Date || value is Data {
                    dict[key.rawValue] = value
                } else if let url = value as? URL {
                    dict[key.rawValue] = url.absoluteString
                } else if let array = value as? [Any] {
                    let numbers = array.compactMap { $0 as? NSNumber }
                    if !numbers.isEmpty {
                        dict[key.rawValue] = numbers
                    }
                }
            }
            if cookie.isHTTPOnly {
                dict["HttpOnly"] = "TRUE"
            }
            if cookie.isSecure {
                dict[HTTPCookiePropertyKey.secure.rawValue] = "TRUE"
            }
            if cookie.isSessionOnly {
                dict[HTTPCookiePropertyKey.discard.rawValue] = "TRUE"
                dict.removeValue(forKey: HTTPCookiePropertyKey.expires.rawValue)
            }
            return dict.isEmpty ? nil : dict
        }
        guard !serialized.isEmpty else { return nil }
        return try? PropertyListSerialization.data(fromPropertyList: serialized, format: .binary, options: 0)
    }

    static func decodeCookies(from data: Data) -> [HTTPCookie]? {
        guard !data.isEmpty,
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) else {
            return nil
        }

        let now = Date()

        // 1. Canonical format: array of cookie property dictionaries.
        if let rawArray = plist as? [[String: Any]] {
            let cookies = rawArray.compactMap { Self.makeCookie(from: $0, now: now) }
            return cookies.isEmpty && !rawArray.isEmpty ? nil : cookies
        }

        // 2. Legacy migration: extract cookie property dicts from NSKeyedArchiver plist.
        if let archiveDict = plist as? [String: Any],
           archiveDict["$archiver"] as? String == "NSKeyedArchiver",
           let objects = archiveDict["$objects"] as? [Any] {
            let extracted = Self.extractLegacyArchivedCookieDictionaries(from: objects)
            let cookies = extracted.compactMap { Self.makeCookie(from: $0, now: now) }
            return cookies.isEmpty ? nil : cookies
        }

        return nil
    }

    private static func makeCookie(from rawDict: [String: Any], now: Date) -> HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [:]
        for (key, value) in rawDict {
            properties[HTTPCookiePropertyKey(key)] = value
        }
        if let expires = properties[.expires] as? Date, expires <= now {
            return nil
        }
        return HTTPCookie(properties: properties)
    }

    private static func extractLegacyArchivedCookieDictionaries(from objects: [Any]) -> [[String: Any]] {
        var results: [[String: Any]] = []
        for obj in objects {
            guard let dict = obj as? [String: Any],
                  let keys = dict["NS.keys"] as? [Any],
                  let vals = dict["NS.objects"] as? [Any],
                  keys.count == vals.count else {
                continue
            }
            var resolved: [String: Any] = [:]
            for (kRef, vRef) in zip(keys, vals) {
                guard let kIdx = cfKeyedArchiverUIDIndex(kRef),
                      let vIdx = cfKeyedArchiverUIDIndex(vRef),
                      kIdx < objects.count,
                      vIdx < objects.count,
                      let keyString = objects[kIdx] as? String else {
                    continue
                }
                let valObj = objects[vIdx]
                if valObj is String || valObj is NSNumber || valObj is Date {
                    resolved[keyString] = valObj
                }
            }
            if resolved["Name"] != nil, resolved["Domain"] != nil, resolved["Value"] != nil {
                results.append(resolved)
            }
        }
        return results
    }

    private static func cfKeyedArchiverUIDIndex(_ ref: Any) -> Int? {
        let description = String(describing: ref)
        guard let range = description.range(of: "value = ") else { return nil }
        let suffix = description[range.upperBound...]
        let digits = suffix.prefix { $0.isNumber }
        return Int(digits)
    }
}

/// Persists per-origin `window.sessionStorage` across process restarts for non-private tabs.
///
/// Many web applications (such as creator platforms and OAuth SPAs) cache active login
/// tokens or user state in `window.sessionStorage`, which WebKit otherwise discards
/// when the app process exits during a rebuild or restart.
public final class WebSessionStorageStore {
    public static let shared = WebSessionStorageStore()
    public static let messageHandlerName = "zhuoSessionStorage"

    private let fileManager: FileManager
    private let fileURL: URL?
    public let isPersistenceEnabled: Bool

    private let lock = NSLock()
    private var storageByOrigin: [String: [String: String]] = [:]
    private var cachedBootstrapScript: WKUserScript?
    private var isBootstrapScriptDirty: Bool = true
    private var debounceWorkItem: DispatchWorkItem?
    private let ioQueue = DispatchQueue(label: "com.youdroid.zhuobrowser.session-storage", qos: .utility)

    public init(
        fileManager: FileManager = .default,
        isPersistenceEnabled: Bool = !RuntimeEnvironment.isRunningUnitTests,
        storageURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.isPersistenceEnabled = isPersistenceEnabled

        if let storageURL {
            self.fileURL = isPersistenceEnabled ? storageURL : nil
            if isPersistenceEnabled,
               let data = try? Data(contentsOf: storageURL),
               let decoded = try? JSONDecoder().decode([String: [String: String]].self, from: data) {
                self.storageByOrigin = decoded
            }
        } else if isPersistenceEnabled,
           let base = try? fileManager.url(
               for: .applicationSupportDirectory,
               in: .userDomainMask,
               appropriateFor: nil,
               create: true
           ) {
            let directory = base.appendingPathComponent("ZhuoBrowserMac/SessionCookies", isDirectory: true)
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("web-session-storage.json")
            self.fileURL = url
            if let data = try? Data(contentsOf: url),
               let decoded = try? JSONDecoder().decode([String: [String: String]].self, from: data) {
                self.storageByOrigin = decoded
            }
        } else {
            self.fileURL = nil
        }
    }

    public func entries(forOrigin origin: String) -> [String: String] {
        lock.lock()
        defer { lock.unlock() }
        return storageByOrigin[origin] ?? [:]
    }

    public func updateEntries(_ entries: [String: String], forOrigin origin: String) {
        update(origin: origin, entries: entries)
    }

    public func update(origin: String, entries: [String: String]) {
        guard !origin.isEmpty, origin != "null" else { return }
        lock.lock()
        if entries.isEmpty {
            storageByOrigin.removeValue(forKey: origin)
        } else {
            storageByOrigin[origin] = entries
        }
        isBootstrapScriptDirty = true
        cachedBootstrapScript = nil
        lock.unlock()
        scheduleFlush()
    }

    public func clearAll() {
        lock.lock()
        storageByOrigin.removeAll()
        isBootstrapScriptDirty = true
        cachedBootstrapScript = nil
        lock.unlock()
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        guard isPersistenceEnabled, let fileURL else { return }
        ioQueue.async { [weak self] in
            try? self?.fileManager.removeItem(at: fileURL)
        }
    }

    public func flushAsync() {
        guard isPersistenceEnabled, let fileURL else { return }
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        lock.lock()
        let snapshot = storageByOrigin
        lock.unlock()
        ioQueue.async {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    public func flushSynchronously() {
        guard isPersistenceEnabled, let fileURL else { return }
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        lock.lock()
        let snapshot = storageByOrigin
        lock.unlock()
        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private func scheduleFlush() {
        guard isPersistenceEnabled else { return }
        debounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.flushAsync()
        }
        debounceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    public func makeBootstrapUserScript() -> WKUserScript? {
        lock.lock()
        if !isBootstrapScriptDirty, let cached = cachedBootstrapScript {
            lock.unlock()
            return cached
        }
        let snapshot = storageByOrigin
        lock.unlock()
        guard let jsonData = try? JSONEncoder().encode(snapshot),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return nil
        }

        let source = """
        (function() {
            try {
                const savedByOrigin = \(jsonString);
                const origin = window.location && window.location.origin;
                if (!origin || origin === 'null' || !window.sessionStorage) return;

                const saved = savedByOrigin[origin];
                if (saved && typeof saved === 'object') {
                    for (const [k, v] of Object.entries(saved)) {
                        if (window.sessionStorage.getItem(k) === null) {
                            window.sessionStorage.setItem(k, v);
                        }
                    }
                }

                function syncToNative() {
                    try {
                        const dump = {};
                        for (let i = 0; i < window.sessionStorage.length; i++) {
                            const key = window.sessionStorage.key(i);
                            if (key !== null) {
                                dump[key] = window.sessionStorage.getItem(key) || '';
                            }
                        }
                        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.\(Self.messageHandlerName)) {
                            window.webkit.messageHandlers.\(Self.messageHandlerName).postMessage({
                                origin: origin,
                                entries: dump
                            });
                        }
                    } catch (_) {}
                }

                const rawSetItem = Storage.prototype.setItem;
                const rawRemoveItem = Storage.prototype.removeItem;
                const rawClear = Storage.prototype.clear;

                Storage.prototype.setItem = function(k, v) {
                    rawSetItem.apply(this, arguments);
                    if (this === window.sessionStorage) syncToNative();
                };
                Storage.prototype.removeItem = function(k) {
                    rawRemoveItem.apply(this, arguments);
                    if (this === window.sessionStorage) syncToNative();
                };
                Storage.prototype.clear = function() {
                    rawClear.apply(this, arguments);
                    if (this === window.sessionStorage) syncToNative();
                };

                window.addEventListener('pagehide', syncToNative, { capture: true });
            } catch (_) {}
        })();
        """
        let script = WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        lock.lock()
        cachedBootstrapScript = script
        isBootstrapScriptDirty = false
        lock.unlock()
        return script
    }
}
