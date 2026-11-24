import AppKit
import Foundation
import UniformTypeIdentifiers
import WebKit

/// Materializes staged downloads into fresh destination files and applies standard
/// Gatekeeper web-download quarantine metadata without `QTN_FLAG_HARD`.
///
/// Note: `Info.plist` must NOT set `LSFileQuarantineEnabled = true` while
/// `com.apple.security.app-sandbox` is enabled, because `NSApplication.shared`
/// would otherwise taint the host process itself with `QTN_FLAG_HARD` (`0087`).
public enum DownloadFileFinalizer: Sendable {
    public static let hardQuarantineFlag: UInt32 = 0x0004
    public static let chunkSize: Int = 1024 * 1024

    public static func parseQuarantineFlags(_ rawAttribute: String) -> UInt32? {
        guard let firstToken = rawAttribute.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false).first else {
            return nil
        }
        let hexToken = firstToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !hexToken.isEmpty else { return nil }
        return UInt32(hexToken, radix: 16)
    }

    public static func isHardQuarantineFlags(_ flags: UInt32) -> Bool {
        (flags & hardQuarantineFlag) != 0
    }

    public static func quarantineAttributeString(at fileURL: URL) -> String? {
        fileURL.withUnsafeFileSystemRepresentation { fileSystemPath in
            guard let fileSystemPath else { return nil }
            let length = getxattr(fileSystemPath, "com.apple.quarantine", nil, 0, 0, 0)
            guard length > 0 else { return nil }
            var buffer = [UInt8](repeating: 0, count: length)
            let bytesRead = getxattr(fileSystemPath, "com.apple.quarantine", &buffer, length, 0, 0)
            guard bytesRead > 0 else { return nil }
            let trimmed = buffer.prefix(bytesRead).prefix { $0 != 0 }
            return String(bytes: trimmed, encoding: .utf8)
        }
    }

    public static func hasHardQuarantineFlag(at fileURL: URL) -> Bool {
        guard let rawAttribute = quarantineAttributeString(at: fileURL),
              let flags = parseQuarantineFlags(rawAttribute) else {
            return false
        }
        return isHardQuarantineFlags(flags)
    }

    /// Streams bytes from a WebKit-owned staging file into a freshly created destination file
    /// owned by the host app process.
    ///
    /// Never use `FileManager.moveItem` or `FileManager.copyItem` here: macOS preserves
    /// `com.apple.quarantine` (`0287` / `QTN_FLAG_HARD`) across both move and copy.
    @discardableResult
    public static func materializeFile(
        from stagingURL: URL,
        to destinationURL: URL,
        removeSource: Bool = true,
        shouldCancel: () -> Bool = { false }
    ) throws -> Int64 {
        let fm = FileManager.default
        let parentDir = destinationURL.deletingLastPathComponent()
        if !fm.fileExists(atPath: parentDir.path) {
            try fm.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }
        if fm.fileExists(atPath: destinationURL.path) {
            try fm.removeItem(at: destinationURL)
        }
        guard fm.createFile(atPath: destinationURL.path, contents: nil) else {
            throw NSError(
                domain: NSPOSIXErrorDomain,
                code: Int(errno != 0 ? errno : EIO),
                userInfo: [
                    NSLocalizedDescriptionKey: "无法创建下载目标文件：\(destinationURL.lastPathComponent)"
                ]
            )
        }

        let reader: FileHandle
        let writer: FileHandle
        do {
            reader = try FileHandle(forReadingFrom: stagingURL)
            writer = try FileHandle(forWritingTo: destinationURL)
        } catch {
            try? fm.removeItem(at: destinationURL)
            throw error
        }

        var totalWritten: Int64 = 0
        do {
            while true {
                if shouldCancel() {
                    try? reader.close()
                    try? writer.close()
                    try? fm.removeItem(at: destinationURL)
                    if removeSource {
                        try? fm.removeItem(at: stagingURL)
                    }
                    throw CancellationError()
                }
                let chunk: Data? = try autoreleasepool {
                    try reader.read(upToCount: chunkSize)
                }
                guard let chunk, !chunk.isEmpty else { break }
                try autoreleasepool {
                    try writer.write(contentsOf: chunk)
                }
                totalWritten += Int64(chunk.count)
            }
            try? reader.close()
            try? writer.close()
        } catch {
            try? reader.close()
            try? writer.close()
            try? fm.removeItem(at: destinationURL)
            throw error
        }

        if removeSource {
            try? fm.removeItem(at: stagingURL)
        }
        return totalWritten
    }

    public static func applyWebDownloadQuarantine(
        to fileURL: URL,
        sourceURL: URL?,
        originURL: URL?,
        agentName: String? = nil,
        bundleIdentifier: String? = nil
    ) {
        let resolvedAgentName = agentName
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? "ZhuoBrowserMac"
        let resolvedBundleID = bundleIdentifier
            ?? Bundle.main.bundleIdentifier
            ?? "com.youdroid.zhuobrowser.mac"

        var properties: [String: Any] = [
            kLSQuarantineTypeKey as String: kLSQuarantineTypeWebDownload as String,
            kLSQuarantineAgentNameKey as String: resolvedAgentName,
            kLSQuarantineAgentBundleIdentifierKey as String: resolvedBundleID
        ]
        if let sourceURL, let scheme = sourceURL.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            properties[kLSQuarantineDataURLKey as String] = sourceURL
        }
        if let originURL, let scheme = originURL.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            properties[kLSQuarantineOriginURLKey as String] = originURL
        }
        try? (fileURL as NSURL).setResourceValue(properties, forKey: .quarantinePropertiesKey)
    }
}

private final class FinalizationCancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.withLock { cancelled }
    }

    func cancel() {
        lock.withLock { cancelled = true }
    }
}

/// Central coordinator for browser file downloads on macOS.
///
/// Bridges `WKDownload` (and direct `URLSession` retry tasks) into an observable
/// Safari-style download list persisted under Application Support.
@MainActor
public final class DownloadManager: NSObject, ObservableObject, WKDownloadDelegate {
    public static let shared = DownloadManager()

    @Published public private(set) var items: [DownloadItem] = []
    @Published public var isShowingPopover: Bool = false

    private let ioQueue = DispatchQueue(label: "com.youdroid.zhuobrowser.mac.downloads-io", qos: .utility)
    private let storageFileURL: URL?
    private let downloadsDirectoryProvider: () -> URL
    private let stagingDirectoryProvider: () -> URL
    private let autoOpenPopoverOnNewDownload: Bool

    private var activeWKDownloads: [String: WKDownload] = [:]
    private var wkDownloadIDByObject: [ObjectIdentifier: String] = [:]
    private var progressObservations: [String: [NSKeyValueObservation]] = [:]
    private var resumeDataByID: [String: Data] = [:]
    private var customDestinationsByID: [String: URL] = [:]
    private var stagingURLsByID: [String: URL] = [:]
    private var finalDestinationURLsByID: [String: URL] = [:]
    private var isCustomDestinationByID: [String: Bool] = [:]
    private var originURLsByID: [String: URL] = [:]
    private var reservedDestinationPaths: Set<String> = []
    private var finalizationTokensByID: [String: FinalizationCancellationToken] = [:]
    private var directTasks: [String: URLSessionDownloadTask] = [:]

    private lazy var directCoordinator = DirectDownloadCoordinator(owner: self)
    private lazy var directSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 3600
        return URLSession(configuration: config, delegate: directCoordinator, delegateQueue: nil)
    }()

    public init(
        storageFileURL: URL? = DownloadManager.defaultStorageFileURL(),
        downloadsDirectoryProvider: @escaping () -> URL = DownloadManager.defaultDownloadsDirectory,
        stagingDirectoryProvider: @escaping () -> URL = DownloadManager.defaultStagingDirectory,
        autoOpenPopoverOnNewDownload: Bool = !RuntimeEnvironment.isRunningUnitTests
    ) {
        self.storageFileURL = storageFileURL
        self.downloadsDirectoryProvider = downloadsDirectoryProvider
        self.stagingDirectoryProvider = stagingDirectoryProvider
        self.autoOpenPopoverOnNewDownload = autoOpenPopoverOnNewDownload
        super.init()
        self.items = loadPersistedItems()
        if !RuntimeEnvironment.isRunningUnitTests {
            let stagingDir = stagingDirectoryProvider()
            let staleEntries = (try? FileManager.default.contentsOfDirectory(
                at: stagingDir,
                includingPropertiesForKeys: nil
            )) ?? []
            if !staleEntries.isEmpty {
                ioQueue.async {
                    for entry in staleEntries {
                        try? FileManager.default.removeItem(at: entry)
                    }
                }
            }
        }
    }

    nonisolated public static func defaultStorageFileURL() -> URL? {
        guard !RuntimeEnvironment.isRunningUnitTests else { return nil }
        let fm = FileManager.default
        guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = appSupport.appendingPathComponent("ZhuoBrowserMac", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("downloads.json", isDirectory: false)
    }

    nonisolated public static func defaultDownloadsDirectory() -> URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads", isDirectory: true)
    }

    nonisolated public static func defaultStagingDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("ZhuoDownloads", isDirectory: true)
    }

    // MARK: - Computed Status

    /// On-demand visibility for the top-right toolbar button (Safari style).
    public var shouldShowToolbarButton: Bool {
        DownloadPolicy.shouldShowToolbarButton(items: items, isPopoverPresented: isShowingPopover)
    }

    public var activeDownloadsCount: Int {
        items.filter { $0.state == .downloading }.count
    }

    public var hasClearableItems: Bool {
        items.contains { $0.state != .downloading }
    }

    /// Aggregate progress (0.0 ... 1.0) across active downloads when known, or `nil` when idle.
    public var overallProgress: Double? {
        let active = items.filter { $0.state == .downloading }
        guard !active.isEmpty else { return nil }
        let known = active.filter { $0.totalBytes > 0 }
        guard !known.isEmpty else { return 0.05 }
        let total = known.reduce(Int64(0)) { $0 + $1.totalBytes }
        let received = known.reduce(Int64(0)) { $0 + min($1.receivedBytes, $1.totalBytes) }
        guard total > 0 else { return 0.05 }
        return min(1.0, max(0.05, Double(received) / Double(total)))
    }

    // MARK: - WKDownload Registration

    public func handleWebKitDownload(
        _ download: WKDownload,
        fallbackURL: URL? = nil,
        customDestinationURL: URL? = nil,
        originURL: URL? = nil
    ) {
        let id = UUID().uuidString
        let requestURL = download.originalRequest?.url ?? fallbackURL
        let rawFilename = customDestinationURL?.lastPathComponent
            ?? (requestURL?.lastPathComponent.isEmpty == false
                ? (requestURL?.lastPathComponent ?? "正在准备下载…")
                : "正在准备下载…")
        let initialName = DownloadPolicy.sanitizeFilename(rawFilename, fallback: "正在准备下载…")

        let newItem = DownloadItem(
            id: id,
            sourceURL: requestURL?.absoluteString ?? "",
            filename: initialName,
            destinationPath: customDestinationURL?.path ?? "",
            receivedBytes: 0,
            totalBytes: -1,
            state: .downloading
        )

        if let customDestinationURL {
            customDestinationsByID[id] = customDestinationURL
        }
        if let originURL {
            originURLsByID[id] = originURL
        }
        insertOrUpdate(newItem)
        activeWKDownloads[id] = download
        wkDownloadIDByObject[ObjectIdentifier(download)] = id
        download.delegate = self
        observeProgress(of: download, id: id)

        if autoOpenPopoverOnNewDownload {
            isShowingPopover = true
        }
    }

    private func observeProgress(of download: WKDownload, id: String) {
        let progress = download.progress
        let completedObs = progress.observe(\.completedUnitCount, options: [.new]) { [weak self] prog, _ in
            let completed = prog.completedUnitCount
            let total = prog.totalUnitCount
            Task { @MainActor [weak self] in
                self?.updateProgress(id: id, receivedBytes: completed, totalBytes: total)
            }
        }
        let totalObs = progress.observe(\.totalUnitCount, options: [.new]) { [weak self] prog, _ in
            let completed = prog.completedUnitCount
            let total = prog.totalUnitCount
            Task { @MainActor [weak self] in
                self?.updateProgress(id: id, receivedBytes: completed, totalBytes: total)
            }
        }
        progressObservations[id] = [completedObs, totalObs]
    }

    private func updateProgress(id: String, receivedBytes: Int64, totalBytes: Int64) {
        guard let idx = items.firstIndex(where: { $0.id == id }),
              items[idx].state == .downloading else { return }
        let clampedReceived = max(0, receivedBytes)
        let resolvedTotal = totalBytes > 0 ? totalBytes : items[idx].totalBytes
        if items[idx].receivedBytes != clampedReceived || items[idx].totalBytes != resolvedTotal {
            items[idx].receivedBytes = clampedReceived
            items[idx].totalBytes = resolvedTotal
        }
    }

    // MARK: - WKDownloadDelegate

    nonisolated public func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping (URL?) -> Void
    ) {
        let runBlock = { @MainActor [weak self] in
            guard let self else {
                completionHandler(nil)
                return
            }
            let key = ObjectIdentifier(download)
            guard let downloadID = self.wkDownloadIDByObject[key] else {
                let targetDir = self.downloadsDirectoryProvider()
                try? FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
                let fallbackURL = DownloadPolicy.uniqueDestinationURL(
                    in: targetDir,
                    suggestedFilename: suggestedFilename,
                    fileExists: { FileManager.default.fileExists(atPath: $0) || self.reservedDestinationPaths.contains($0) }
                )
                completionHandler(fallbackURL)
                return
            }

            let isCustom: Bool
            let finalDestinationURL: URL
            if let customURL = self.customDestinationsByID.removeValue(forKey: downloadID) {
                isCustom = true
                try? FileManager.default.createDirectory(
                    at: customURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                finalDestinationURL = customURL
            } else {
                isCustom = false
                let targetDir = self.downloadsDirectoryProvider()
                try? FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
                finalDestinationURL = DownloadPolicy.uniqueDestinationURL(
                    in: targetDir,
                    suggestedFilename: suggestedFilename,
                    fileExists: { FileManager.default.fileExists(atPath: $0) || self.reservedDestinationPaths.contains($0) }
                )
            }

            self.finalDestinationURLsByID[downloadID] = finalDestinationURL
            self.isCustomDestinationByID[downloadID] = isCustom
            self.reservedDestinationPaths.insert(finalDestinationURL.path)

            let stagingDir = self.stagingDirectoryProvider()
            try? FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
            let stagingName = "\(downloadID)-\(DownloadPolicy.sanitizeFilename(finalDestinationURL.lastPathComponent)).part"
            let stagingURL = stagingDir.appendingPathComponent(stagingName, isDirectory: false)
            if FileManager.default.fileExists(atPath: stagingURL.path) {
                try? FileManager.default.removeItem(at: stagingURL)
            }
            self.stagingURLsByID[downloadID] = stagingURL

            if let idx = self.items.firstIndex(where: { $0.id == downloadID }) {
                self.items[idx].filename = finalDestinationURL.lastPathComponent
                self.items[idx].destinationPath = finalDestinationURL.path
                if let urlString = response.url?.absoluteString, !urlString.isEmpty, self.items[idx].sourceURL.isEmpty {
                    self.items[idx].sourceURL = urlString
                }
                let expected = response.expectedContentLength
                if expected > 0 {
                    self.items[idx].totalBytes = expected
                }
                self.saveItems()
            }

            completionHandler(stagingURL)
        }

        if Thread.isMainThread {
            MainActor.assumeIsolated {
                runBlock()
            }
        } else {
            Task { @MainActor in
                runBlock()
            }
        }
    }

    nonisolated public func downloadDidFinish(_ download: WKDownload) {
        let runBlock = { @MainActor [weak self] in
            guard let self else { return }
            let key = ObjectIdentifier(download)
            guard let id = self.wkDownloadIDByObject.removeValue(forKey: key) else { return }
            self.cleanupTracking(for: id)
            self.resumeDataByID.removeValue(forKey: id)

            let stagingURL = self.stagingURLsByID[id]
            let finalDestinationURL = self.finalDestinationURLsByID[id]
            let isCustomDestination = self.isCustomDestinationByID[id] ?? false
            let originURL = self.originURLsByID[id]
            let sourceURLString = self.items.first(where: { $0.id == id })?.sourceURL ?? ""

            guard let stagingURL, let finalDestinationURL else {
                self.releaseFinalizationTracking(for: id)
                if let idx = self.items.firstIndex(where: { $0.id == id }) {
                    let path = self.items[idx].destinationPath
                    if !path.isEmpty,
                       let attrs = try? FileManager.default.attributesOfItem(atPath: path),
                       let fileSize = (attrs[.size] as? NSNumber)?.int64Value,
                       fileSize > 0 {
                        self.items[idx].receivedBytes = fileSize
                        self.items[idx].totalBytes = fileSize
                    } else if self.items[idx].receivedBytes > 0 && self.items[idx].totalBytes <= 0 {
                        self.items[idx].totalBytes = self.items[idx].receivedBytes
                    }
                    self.items[idx].state = .completed
                    self.items[idx].completedAt = Date().timeIntervalSince1970
                    self.items[idx].errorMessage = nil
                    self.saveItems()
                }
                return
            }

            let token = FinalizationCancellationToken()
            self.finalizationTokensByID[id] = token
            let ioQueue = self.ioQueue
            ioQueue.async {
                let resolvedDestination: URL
                if !isCustomDestination && FileManager.default.fileExists(atPath: finalDestinationURL.path) {
                    resolvedDestination = DownloadPolicy.uniqueDestinationURL(
                        in: finalDestinationURL.deletingLastPathComponent(),
                        suggestedFilename: finalDestinationURL.lastPathComponent
                    )
                } else {
                    resolvedDestination = finalDestinationURL
                }

                do {
                    let bytesWritten = try DownloadFileFinalizer.materializeFile(
                        from: stagingURL,
                        to: resolvedDestination,
                        removeSource: true,
                        shouldCancel: { token.isCancelled }
                    )
                    DownloadFileFinalizer.applyWebDownloadQuarantine(
                        to: resolvedDestination,
                        sourceURL: URL(string: sourceURLString),
                        originURL: originURL
                    )
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.releaseFinalizationTracking(for: id, reservedPath: finalDestinationURL.path)
                        guard !token.isCancelled,
                              let idx = self.items.firstIndex(where: { $0.id == id }),
                              self.items[idx].state == .downloading else {
                            return
                        }
                        self.items[idx].filename = resolvedDestination.lastPathComponent
                        self.items[idx].destinationPath = resolvedDestination.path
                        self.items[idx].receivedBytes = bytesWritten
                        self.items[idx].totalBytes = bytesWritten
                        self.items[idx].state = .completed
                        self.items[idx].completedAt = Date().timeIntervalSince1970
                        self.items[idx].errorMessage = nil
                        self.saveItems()
                    }
                } catch is CancellationError {
                    Task { @MainActor [weak self] in
                        self?.releaseFinalizationTracking(for: id, reservedPath: finalDestinationURL.path)
                    }
                } catch {
                    try? FileManager.default.removeItem(at: stagingURL)
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.releaseFinalizationTracking(for: id, reservedPath: finalDestinationURL.path)
                        guard !token.isCancelled,
                              let idx = self.items.firstIndex(where: { $0.id == id }),
                              self.items[idx].state == .downloading else {
                            return
                        }
                        self.items[idx].state = .failed
                        self.items[idx].errorMessage = error.localizedDescription
                        self.saveItems()
                    }
                }
            }
        }

        if Thread.isMainThread {
            MainActor.assumeIsolated {
                runBlock()
            }
        } else {
            Task { @MainActor in
                runBlock()
            }
        }
    }

    nonisolated public func download(
        _ download: WKDownload,
        didFailWithError error: Error,
        resumeData: Data?
    ) {
        let runBlock = { @MainActor [weak self] in
            guard let self else { return }
            let key = ObjectIdentifier(download)
            guard let id = self.wkDownloadIDByObject.removeValue(forKey: key) else { return }
            self.cleanupTracking(for: id)
            self.releaseFinalizationTracking(for: id, preserveStagingURL: resumeData != nil)

            if let resumeData {
                self.resumeDataByID[id] = resumeData
            } else if let staleStagingURL = self.stagingURLsByID.removeValue(forKey: id) {
                try? FileManager.default.removeItem(at: staleStagingURL)
            }
            if let idx = self.items.firstIndex(where: { $0.id == id }) {
                if self.items[idx].state != .cancelled {
                    let nsError = error as NSError
                    if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                        self.items[idx].state = .cancelled
                    } else {
                        self.items[idx].state = .failed
                        self.items[idx].errorMessage = error.localizedDescription
                    }
                }
                self.saveItems()
            }
        }

        if Thread.isMainThread {
            MainActor.assumeIsolated {
                runBlock()
            }
        } else {
            Task { @MainActor in
                runBlock()
            }
        }
    }

    nonisolated public func download(
        _ download: WKDownload,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let runBlock = { @MainActor in
            if let credential = URLCredentialStorage.shared.defaultCredential(for: challenge.protectionSpace) {
                completionHandler(.useCredential, credential)
                return
            }
            completionHandler(.performDefaultHandling, nil)
        }

        if Thread.isMainThread {
            MainActor.assumeIsolated {
                runBlock()
            }
        } else {
            Task { @MainActor in
                runBlock()
            }
        }
    }

    nonisolated public func download(
        _ download: WKDownload,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        decisionHandler: @escaping (WKDownload.RedirectPolicy) -> Void
    ) {
        decisionHandler(.allow)
    }

    // MARK: - User Actions & Testable Entry Points

    @discardableResult
    public func recordDownloadItem(_ item: DownloadItem, openPopover: Bool = false) -> DownloadItem {
        insertOrUpdate(item)
        if openPopover {
            isShowingPopover = true
        }
        return item
    }

    public func cancelDownload(id: String) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].state = .cancelled
        items[idx].errorMessage = nil

        finalizationTokensByID.removeValue(forKey: id)?.cancel()
        if let reservedPath = finalDestinationURLsByID.removeValue(forKey: id)?.path {
            reservedDestinationPaths.remove(reservedPath)
        }
        isCustomDestinationByID.removeValue(forKey: id)
        originURLsByID.removeValue(forKey: id)

        if let wkDownload = activeWKDownloads.removeValue(forKey: id) {
            wkDownloadIDByObject.removeValue(forKey: ObjectIdentifier(wkDownload))
            wkDownload.cancel { [weak self] resumeData in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if let resumeData {
                        self.resumeDataByID[id] = resumeData
                    } else if let staleStagingURL = self.stagingURLsByID.removeValue(forKey: id) {
                        try? FileManager.default.removeItem(at: staleStagingURL)
                    }
                }
            }
        } else if let staleStagingURL = stagingURLsByID.removeValue(forKey: id) {
            try? FileManager.default.removeItem(at: staleStagingURL)
        }
        if let task = directTasks.removeValue(forKey: id) {
            directCoordinator.unregister(taskID: task.taskIdentifier)
            task.cancel()
        }
        cleanupTracking(for: id)
        saveItems()
    }

    public func retryDownload(id: String, in webView: WKWebView? = nil) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items[idx]
        let originURL = webView?.url

        if let resumeData = resumeDataByID.removeValue(forKey: id), let webView {
            let oldStagingURL = stagingURLsByID.removeValue(forKey: id)
            items.remove(at: idx)
            webView.resumeDownload(fromResumeData: resumeData) { [weak self] wkDownload in
                MainActor.assumeIsolated {
                    self?.handleWebKitDownload(
                        wkDownload,
                        fallbackURL: URL(string: item.sourceURL),
                        originURL: originURL
                    )
                    if let oldStagingURL {
                        try? FileManager.default.removeItem(at: oldStagingURL)
                    }
                }
            }
            return
        }

        if let oldStagingURL = stagingURLsByID.removeValue(forKey: id) {
            try? FileManager.default.removeItem(at: oldStagingURL)
        }

        guard let url = URL(string: item.sourceURL), !item.sourceURL.isEmpty else { return }
        if let webView {
            items.remove(at: idx)
            webView.startDownload(using: URLRequest(url: url)) { [weak self] wkDownload in
                MainActor.assumeIsolated {
                    self?.handleWebKitDownload(
                        wkDownload,
                        fallbackURL: url,
                        originURL: originURL
                    )
                }
            }
        } else {
            items.remove(at: idx)
            startDirectDownload(from: url, suggestedFilename: item.filename)
        }
    }

    public func startDirectDownload(from url: URL, suggestedFilename: String? = nil) {
        let id = UUID().uuidString
        let rawName = suggestedFilename ?? (url.lastPathComponent.isEmpty ? "download" : url.lastPathComponent)
        let targetDir = downloadsDirectoryProvider()
        try? FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
        let destinationURL = DownloadPolicy.uniqueDestinationURL(in: targetDir, suggestedFilename: rawName)

        let item = DownloadItem(
            id: id,
            sourceURL: url.absoluteString,
            filename: destinationURL.lastPathComponent,
            destinationPath: destinationURL.path,
            receivedBytes: 0,
            totalBytes: -1,
            state: .downloading
        )
        insertOrUpdate(item)
        if autoOpenPopoverOnNewDownload {
            isShowingPopover = true
        }

        let task = directSession.downloadTask(with: url)
        directCoordinator.register(
            taskID: task.taskIdentifier,
            id: id,
            destinationURL: destinationURL
        )
        directTasks[id] = task
        task.resume()
    }

    // MARK: - Direct URLSession Handling

    fileprivate func handleDirectDownloadProgress(
        id: String,
        receivedBytes: Int64,
        totalBytes: Int64
    ) {
        updateProgress(id: id, receivedBytes: receivedBytes, totalBytes: totalBytes)
    }

    fileprivate func handleDirectDownloadFinished(
        id: String,
        destinationURL: URL,
        fileSize: Int64,
        error: Error?
    ) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        if let error {
            items[idx].state = .failed
            items[idx].errorMessage = error.localizedDescription
        } else {
            items[idx].filename = destinationURL.lastPathComponent
            items[idx].destinationPath = destinationURL.path
            items[idx].receivedBytes = fileSize
            items[idx].totalBytes = fileSize
            items[idx].state = .completed
            items[idx].completedAt = Date().timeIntervalSince1970
            items[idx].errorMessage = nil
        }
        saveItems()
    }

    fileprivate func handleDirectDownloadCompleted(id: String, error: Error?) {
        directTasks.removeValue(forKey: id)
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        if let error {
            if items[idx].state != .completed {
                let nsError = error as NSError
                if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                    items[idx].state = .cancelled
                } else {
                    items[idx].state = .failed
                    items[idx].errorMessage = error.localizedDescription
                }
                saveItems()
            }
        }
    }

    public func removeDownload(id: String) {
        if let idx = items.firstIndex(where: { $0.id == id }), items[idx].state == .downloading {
            cancelDownload(id: id)
        }
        items.removeAll { $0.id == id }
        resumeDataByID.removeValue(forKey: id)
        cleanupTracking(for: id)
        releaseFinalizationTracking(for: id, preserveStagingURL: false)
        if items.isEmpty {
            isShowingPopover = false
        }
        saveItems()
    }

    /// Clears all non-active downloads (completed, failed, cancelled).
    /// When no active downloads remain, automatically closes the popover so the toolbar
    /// button hides on-demand, matching Safari's "清除" button behavior.
    public func clearCompletedDownloads() {
        let removedIDs = items.filter { $0.state != .downloading }.map(\.id)
        for id in removedIDs {
            resumeDataByID.removeValue(forKey: id)
            cleanupTracking(for: id)
            releaseFinalizationTracking(for: id, preserveStagingURL: false)
        }
        items.removeAll { $0.state != .downloading }
        if items.isEmpty {
            isShowingPopover = false
        }
        saveItems()
    }

    public func openDownloadedFile(_ item: DownloadItem) {
        guard !item.destinationPath.isEmpty,
              FileManager.default.fileExists(atPath: item.destinationPath) else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: item.destinationPath))
    }

    public func revealInFinder(_ item: DownloadItem) {
        guard !item.destinationPath.isEmpty else { return }
        let fileURL = URL(fileURLWithPath: item.destinationPath)
        if FileManager.default.fileExists(atPath: item.destinationPath) {
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
        } else {
            let parentURL = fileURL.deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: parentURL.path) {
                NSWorkspace.shared.open(parentURL)
            }
        }
    }

    public func icon(for item: DownloadItem) -> NSImage {
        if !item.destinationPath.isEmpty, FileManager.default.fileExists(atPath: item.destinationPath) {
            let icon = NSWorkspace.shared.icon(forFile: item.destinationPath)
            icon.size = NSSize(width: 32, height: 32)
            return icon
        }
        let ext = (item.filename as NSString).pathExtension
        if !ext.isEmpty, let utType = UTType(filenameExtension: ext) {
            let icon = NSWorkspace.shared.icon(for: utType)
            icon.size = NSSize(width: 32, height: 32)
            return icon
        }
        let fallback = NSWorkspace.shared.icon(for: .data)
        fallback.size = NSSize(width: 32, height: 32)
        return fallback
    }

    // MARK: - Helpers & Persistence

    private func insertOrUpdate(_ item: DownloadItem) {
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            items[idx] = item
        } else {
            items = [item] + Array(items.prefix(DownloadPolicy.maxStoredDownloads - 1))
        }
        saveItems()
    }

    private func cleanupTracking(for id: String) {
        activeWKDownloads.removeValue(forKey: id)
        customDestinationsByID.removeValue(forKey: id)
        if let obsList = progressObservations.removeValue(forKey: id) {
            obsList.forEach { $0.invalidate() }
        }
    }

    private func releaseFinalizationTracking(
        for id: String,
        reservedPath: String? = nil,
        preserveStagingURL: Bool = false
    ) {
        finalizationTokensByID.removeValue(forKey: id)
        isCustomDestinationByID.removeValue(forKey: id)
        originURLsByID.removeValue(forKey: id)
        if let trackedDest = finalDestinationURLsByID.removeValue(forKey: id) {
            reservedDestinationPaths.remove(trackedDest.path)
        }
        if let reservedPath {
            reservedDestinationPaths.remove(reservedPath)
        }
        if !preserveStagingURL, let staleStagingURL = stagingURLsByID.removeValue(forKey: id) {
            try? FileManager.default.removeItem(at: staleStagingURL)
        }
    }

    private func loadPersistedItems() -> [DownloadItem] {
        guard let storageFileURL,
              let data = try? Data(contentsOf: storageFileURL),
              let decoded = try? JSONDecoder().decode([DownloadItem].self, from: data) else {
            return []
        }
        // Any download that was still in `.downloading` when the app last quit was interrupted.
        return decoded.map { item in
            guard item.state == .downloading else { return item }
            var interrupted = item
            interrupted.state = .cancelled
            return interrupted
        }
    }

    private func saveItems() {
        guard let storageFileURL else { return }
        let snapshot = items
        ioQueue.async {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: storageFileURL, options: .atomic)
        }
    }
}

// MARK: - DirectDownloadCoordinator

private final class DirectDownloadCoordinator: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    struct Context {
        let id: String
        let destinationURL: URL
    }

    private let lock = NSLock()
    private var contexts: [Int: Context] = [:]
    private weak var owner: DownloadManager?

    init(owner: DownloadManager) {
        self.owner = owner
        super.init()
    }

    func register(taskID: Int, id: String, destinationURL: URL) {
        lock.withLock {
            contexts[taskID] = Context(id: id, destinationURL: destinationURL)
        }
    }

    func unregister(taskID: Int) {
        _ = lock.withLock {
            contexts.removeValue(forKey: taskID)
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let taskID = downloadTask.taskIdentifier
        guard let ctx = lock.withLock({ contexts[taskID] }) else { return }
        Task { @MainActor [weak owner] in
            owner?.handleDirectDownloadProgress(
                id: ctx.id,
                receivedBytes: totalBytesWritten,
                totalBytes: totalBytesExpectedToWrite
            )
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let taskID = downloadTask.taskIdentifier
        guard let ctx = lock.withLock({ contexts[taskID] }) else { return }

        // Materialize a fresh destination file immediately before didFinishDownloadingTo returns
        var moveError: Error?
        var fileSize: Int64 = 0
        do {
            fileSize = try DownloadFileFinalizer.materializeFile(
                from: location,
                to: ctx.destinationURL,
                removeSource: false
            )
            let sourceURL = downloadTask.currentRequest?.url ?? downloadTask.originalRequest?.url
            DownloadFileFinalizer.applyWebDownloadQuarantine(
                to: ctx.destinationURL,
                sourceURL: sourceURL,
                originURL: nil
            )
        } catch {
            moveError = error
        }

        Task { @MainActor [weak owner] in
            owner?.handleDirectDownloadFinished(
                id: ctx.id,
                destinationURL: ctx.destinationURL,
                fileSize: fileSize,
                error: moveError
            )
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        let taskID = task.taskIdentifier
        guard let ctx = lock.withLock({ contexts.removeValue(forKey: taskID) }) else { return }

        Task { @MainActor [weak owner] in
            owner?.handleDirectDownloadCompleted(
                id: ctx.id,
                error: error
            )
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if let credential = URLCredentialStorage.shared.defaultCredential(for: challenge.protectionSpace) {
            completionHandler(.useCredential, credential)
            return
        }
        completionHandler(.performDefaultHandling, nil)
    }
}
