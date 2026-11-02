import AppKit
import Foundation
import UniformTypeIdentifiers
import WebKit

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
    private let autoOpenPopoverOnNewDownload: Bool

    private var activeWKDownloads: [String: WKDownload] = [:]
    private var wkDownloadIDByObject: [ObjectIdentifier: String] = [:]
    private var progressObservations: [String: [NSKeyValueObservation]] = [:]
    private var resumeDataByID: [String: Data] = [:]
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
        autoOpenPopoverOnNewDownload: Bool = !RuntimeEnvironment.isRunningUnitTests
    ) {
        self.storageFileURL = storageFileURL
        self.downloadsDirectoryProvider = downloadsDirectoryProvider
        self.autoOpenPopoverOnNewDownload = autoOpenPopoverOnNewDownload
        super.init()
        self.items = loadPersistedItems()
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

    public func handleWebKitDownload(_ download: WKDownload, fallbackURL: URL? = nil) {
        let id = UUID().uuidString
        let requestURL = download.originalRequest?.url ?? fallbackURL
        let rawFilename = requestURL?.lastPathComponent.isEmpty == false
            ? (requestURL?.lastPathComponent ?? "正在准备下载…")
            : "正在准备下载…"
        let initialName = DownloadPolicy.sanitizeFilename(rawFilename, fallback: "正在准备下载…")

        let newItem = DownloadItem(
            id: id,
            sourceURL: requestURL?.absoluteString ?? "",
            filename: initialName,
            destinationPath: "",
            receivedBytes: 0,
            totalBytes: -1,
            state: .downloading
        )

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
            let targetDir = self.downloadsDirectoryProvider()
            try? FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)

            let destinationURL = DownloadPolicy.uniqueDestinationURL(
                in: targetDir,
                suggestedFilename: suggestedFilename
            )

            // Remove any stale or zero-byte placeholder at destination to prevent WebKit write collisions
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try? FileManager.default.removeItem(at: destinationURL)
            }

            if let id = self.wkDownloadIDByObject[key],
               let idx = self.items.firstIndex(where: { $0.id == id }) {
                self.items[idx].filename = destinationURL.lastPathComponent
                self.items[idx].destinationPath = destinationURL.path
                if let urlString = response.url?.absoluteString, !urlString.isEmpty, self.items[idx].sourceURL.isEmpty {
                    self.items[idx].sourceURL = urlString
                }
                let expected = response.expectedContentLength
                if expected > 0 {
                    self.items[idx].totalBytes = expected
                }
                self.saveItems()
            }

            completionHandler(destinationURL)
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

            if let resumeData {
                self.resumeDataByID[id] = resumeData
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

        if let wkDownload = activeWKDownloads.removeValue(forKey: id) {
            wkDownloadIDByObject.removeValue(forKey: ObjectIdentifier(wkDownload))
            wkDownload.cancel { [weak self] resumeData in
                guard let resumeData else { return }
                MainActor.assumeIsolated {
                    self?.resumeDataByID[id] = resumeData
                }
            }
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

        if let resumeData = resumeDataByID.removeValue(forKey: id), let webView {
            items.remove(at: idx)
            webView.resumeDownload(fromResumeData: resumeData) { [weak self] wkDownload in
                MainActor.assumeIsolated {
                    self?.handleWebKitDownload(wkDownload, fallbackURL: URL(string: item.sourceURL))
                }
            }
            return
        }

        guard let url = URL(string: item.sourceURL), !item.sourceURL.isEmpty else { return }
        if let webView {
            items.remove(at: idx)
            webView.startDownload(using: URLRequest(url: url)) { [weak self] wkDownload in
                MainActor.assumeIsolated {
                    self?.handleWebKitDownload(wkDownload, fallbackURL: url)
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
        if let obsList = progressObservations.removeValue(forKey: id) {
            obsList.forEach { $0.invalidate() }
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

        // Must move the file immediately before didFinishDownloadingTo returns
        var moveError: Error?
        do {
            try? FileManager.default.removeItem(at: ctx.destinationURL)
            try FileManager.default.moveItem(at: location, to: ctx.destinationURL)
        } catch {
            moveError = error
        }

        let fileSize = ((try? FileManager.default.attributesOfItem(atPath: ctx.destinationURL.path)[.size]) as? NSNumber)?.int64Value ?? 0

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
