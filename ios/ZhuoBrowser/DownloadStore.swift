import Foundation
import Network
import UserNotifications
import WebKit

enum DownloadStatus: String, Codable {
    case pending
    case downloading
    case paused
    case completed
    case failed
    case canceled
}

struct DownloadTask: Identifiable, Equatable, Codable {
    var id: String
    var fileName: String
    var url: String
    var status: DownloadStatus
    var error: String
    var path: String
    var progress: Double
    var receivedBytes: Int64
    var totalBytes: Int64
    var attempts: Int
    var resumeData: Data?

    enum CodingKeys: String, CodingKey {
        case id, fileName, url, status, error, path
        case progress, receivedBytes, totalBytes, attempts, resumeData
    }

    init(
        id: String,
        fileName: String,
        url: String,
        status: DownloadStatus,
        error: String,
        path: String,
        progress: Double = 0,
        receivedBytes: Int64 = 0,
        totalBytes: Int64 = -1,
        attempts: Int = 0,
        resumeData: Data? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.url = url
        self.status = status
        self.error = error
        self.path = path
        self.progress = progress
        self.receivedBytes = receivedBytes
        self.totalBytes = totalBytes
        self.attempts = attempts
        self.resumeData = resumeData
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        fileName = try container.decode(String.self, forKey: .fileName)
        url = try container.decode(String.self, forKey: .url)
        status = try container.decode(DownloadStatus.self, forKey: .status)
        error = try container.decodeIfPresent(String.self, forKey: .error) ?? ""
        path = try container.decodeIfPresent(String.self, forKey: .path) ?? ""
        progress = try container.decodeIfPresent(Double.self, forKey: .progress) ?? 0
        receivedBytes = try container.decodeIfPresent(Int64.self, forKey: .receivedBytes) ?? 0
        totalBytes = try container.decodeIfPresent(Int64.self, forKey: .totalBytes) ?? -1
        attempts = try container.decodeIfPresent(Int.self, forKey: .attempts) ?? 0
        resumeData = try container.decodeIfPresent(Data.self, forKey: .resumeData)
    }
}

struct DownloadPolicyRequest: Identifiable, Equatable {
    let taskID: String
    let fileName: String
    let reason: DownloadPolicyReason

    var id: String { taskID }
}

@MainActor
final class DownloadStore: NSObject, ObservableObject, WKDownloadDelegate {
    @Published private(set) var tasks: [DownloadTask] = []
    @Published var policyRequest: DownloadPolicyRequest?

    var onCompletion: ((DownloadTask) -> Void)?
    var onFailure: ((DownloadTask) -> Void)?

    private var active: [ObjectIdentifier: WKDownload] = [:]
    private var taskIDs: [ObjectIdentifier: String] = [:]
    private var webViews: [String: WKWebView] = [:]
    private var observations: [ObjectIdentifier: NSKeyValueObservation] = [:]
    private var expectedCancellations: Set<ObjectIdentifier> = []
    private var approvedTaskIDs: Set<String> = []
    private let defaultsKey = "download_tasks_v1"
    private let pathMonitor = NWPathMonitor()
    private let pathQueue = DispatchQueue(label: "com.youdroid.zhuobrowser.download-network")
    private var isWifiConnected = false
    private var maxConcurrent = 2
    private var largeFileThresholdMB = 50
    private var wifiOnly = false
    private var notificationsEnabled = false

    override init() {
        super.init()
        restore()
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                self.isWifiConnected = path.status == .satisfied && path.usesInterfaceType(.wifi)
                self.pump()
            }
        }
        pathMonitor.start(queue: pathQueue)
    }

    deinit {
        pathMonitor.cancel()
    }

    var downloadsDirectory: URL {
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    func configure(settings: BrowserSettings) {
        maxConcurrent = BrowserSettings.clampedDownloadConcurrency(settings.downloadConcurrency)
        largeFileThresholdMB = BrowserSettings.clampedLargeDownloadThresholdMB(settings.largeDownloadThresholdMB)
        wifiOnly = settings.wifiOnlyDownloads
        notificationsEnabled = settings.downloadNotificationsEnabled
        if wifiOnly && !isWifiConnected {
            tasks.filter { $0.status == .downloading }.forEach { suspend($0.id, as: .pending) }
        }
        pump()
    }

    func begin(_ download: WKDownload, sourceURL: String) {
        let id = UUID().uuidString
        webViews[id] = download.webView
        tasks.insert(
            DownloadTask(
                id: id,
                fileName: "下载中",
                url: sourceURL,
                status: .downloading,
                error: "",
                path: "",
                attempts: 1
            ),
            at: 0
        )
        attach(download, taskID: id)
        persist()
    }

    func fileURL(for task: DownloadTask) -> URL? {
        guard task.status == .completed, !task.path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: task.path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            reconcileMissingFile(task.id)
            return nil
        }
        return url
    }

    func pause(_ id: String) {
        guard task(id)?.status == .downloading else { return }
        suspend(id, as: .paused)
    }

    func resume(_ id: String) {
        guard let task = task(id), task.status == .paused else { return }
        mutate(id) {
            $0.status = .pending
            $0.error = ""
        }
        persist()
        pump()
    }

    func retry(_ id: String, using fallbackWebView: WKWebView?) {
        guard let task = task(id), task.status == .failed || task.status == .canceled else { return }
        if webViews[id] == nil {
            webViews[id] = fallbackWebView
        }
        mutate(id) {
            $0.status = .pending
            $0.error = ""
        }
        persist()
        pump()
    }

    func approvePolicy(_ id: String) {
        approvedTaskIDs.insert(id)
        policyRequest = nil
        mutate(id) {
            $0.status = .pending
            $0.error = ""
        }
        persist()
        pump()
    }

    func cancelPolicy(_ id: String) {
        policyRequest = nil
        cancel(id)
    }

    func cancel(_ id: String) {
        if task(id)?.status == .downloading {
            suspend(id, as: .canceled)
            return
        }
        mutate(id) {
            $0.status = .canceled
            $0.error = ""
        }
        approvedTaskIDs.remove(id)
        persist()
        pump()
    }

    func remove(_ id: String, deleteFile: Bool) {
        if task(id)?.status == .downloading, let download = activeDownload(for: id) {
            download.cancel(nil)
            forget(download)
        }
        if deleteFile, let path = task(id)?.path, !path.isEmpty {
            try? FileManager.default.removeItem(atPath: path)
        }
        tasks.removeAll { $0.id == id }
        webViews[id] = nil
        approvedTaskIDs.remove(id)
        persist()
        pump()
    }

    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping (URL?) -> Void
    ) {
        let name = sanitizedFileName(
            suggestedFilename.isEmpty ? (response.suggestedFilename ?? "download") : suggestedFilename
        )
        let id = taskID(for: download)
        let existingPath = id.flatMap { task($0)?.path }
        let destination = existingPath.flatMap { path -> URL? in
            guard !path.isEmpty, !FileManager.default.fileExists(atPath: path) else { return nil }
            return URL(fileURLWithPath: path)
        } ?? uniqueURL(name)
        let totalBytes = response.expectedContentLength
        if let id {
            mutate(id) { task in
                task.fileName = name
                task.path = destination.path
                task.totalBytes = totalBytes
                if task.url.isEmpty {
                    task.url = response.url?.absoluteString ?? ""
                }
            }
        }
        completionHandler(destination)
        guard let id else { return }
        if let reason = policyReason(for: id) {
            if let task = task(id) {
                policyRequest = DownloadPolicyRequest(taskID: id, fileName: task.fileName, reason: reason)
            }
            DispatchQueue.main.async { [weak self] in self?.suspend(id, as: .pending) }
        } else if downloadingCount > maxConcurrent {
            DispatchQueue.main.async { [weak self] in self?.suspend(id, as: .pending) }
        }
        persist()
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let id = taskID(for: download) else { return }
        mutate(id) { task in
            task.status = .completed
            task.error = ""
            task.progress = 1
            if task.totalBytes > 0 {
                task.receivedBytes = task.totalBytes
            }
            task.resumeData = nil
        }
        let completed = task(id)
        if policyRequest?.taskID == id {
            policyRequest = nil
        }
        forget(download)
        persist()
        if let completed {
            onCompletion?(completed)
            postCompletionNotification(completed)
        }
        pump()
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        let token = ObjectIdentifier(download)
        guard let id = taskIDs[token] else { return }
        if expectedCancellations.remove(token) != nil {
            if let resumeData {
                mutate(id) { $0.resumeData = resumeData }
            }
            return
        }
        mutate(id) { task in
            task.status = .failed
            task.error = error.localizedDescription
            task.resumeData = resumeData
        }
        let failed = task(id)
        forget(download)
        persist()
        if let failed { onFailure?(failed) }
        pump()
    }

    private var downloadingCount: Int {
        tasks.filter { $0.status == .downloading }.count
    }

    private func pump() {
        if let request = policyRequest, policyReason(for: request.taskID) == nil {
            policyRequest = nil
        }
        guard downloadingCount < maxConcurrent else { return }
        for pending in tasks where pending.status == .pending {
            guard downloadingCount < maxConcurrent else { break }
            if let reason = policyReason(for: pending.id) {
                if policyRequest == nil {
                    policyRequest = DownloadPolicyRequest(
                        taskID: pending.id,
                        fileName: pending.fileName,
                        reason: reason
                    )
                }
                continue
            }
            start(pending.id)
        }
    }

    private func start(_ id: String) {
        guard let task = task(id), let webView = webViews[id], let url = URL(string: task.url) else {
            mutate(id) {
                $0.status = .failed
                $0.error = "resume_unavailable"
            }
            persist()
            return
        }
        let resumeData = task.resumeData
        mutate(id) {
            $0.status = .downloading
            $0.error = ""
            $0.attempts += 1
        }
        if let resumeData {
            webView.resumeDownload(fromResumeData: resumeData) { [weak self] download in
                self?.attachStartedDownload(download, taskID: id)
            }
        } else {
            webView.startDownload(using: URLRequest(url: url)) { [weak self] download in
                self?.attachStartedDownload(download, taskID: id)
            }
        }
        persist()
    }

    private func attachStartedDownload(_ download: WKDownload, taskID: String) {
        guard task(taskID)?.status == .downloading else {
            download.cancel(nil)
            return
        }
        attach(download, taskID: taskID)
    }

    private func suspend(_ id: String, as status: DownloadStatus) {
        guard task(id)?.status == .downloading else { return }
        guard let download = activeDownload(for: id) else {
            mutate(id) { $0.status = status }
            persist()
            pump()
            return
        }
        let token = ObjectIdentifier(download)
        expectedCancellations.insert(token)
        download.cancel { [weak self] resumeData in
            guard let self else { return }
            self.mutate(id) { task in
                task.status = status
                task.resumeData = resumeData ?? task.resumeData
                task.error = status == .pending ? "queued" : ""
            }
            self.forget(download)
            self.persist()
            self.pump()
        }
    }

    private func policyReason(for id: String) -> DownloadPolicyReason? {
        guard let task = task(id) else { return nil }
        return DownloadPolicy.reason(
            wifiOnly: wifiOnly,
            isWifiConnected: isWifiConnected,
            isApproved: approvedTaskIDs.contains(id),
            totalBytes: task.totalBytes,
            largeFileThresholdMB: largeFileThresholdMB
        )
    }

    private func attach(_ download: WKDownload, taskID: String) {
        let token = ObjectIdentifier(download)
        active[token] = download
        taskIDs[token] = taskID
        webViews[taskID] = download.webView ?? webViews[taskID]
        download.delegate = self
        observations[token] = download.progress.observe(\.fractionCompleted, options: [.initial, .new]) {
            [weak self, weak download] progress, _ in
            Task { @MainActor in
                guard let self, let download, let id = self.taskID(for: download) else { return }
                self.mutate(id) { task in
                    task.progress = progress.fractionCompleted
                    task.receivedBytes = progress.completedUnitCount
                    if progress.totalUnitCount > 0 {
                        task.totalBytes = progress.totalUnitCount
                    }
                }
            }
        }
    }

    private func activeDownload(for id: String) -> WKDownload? {
        active.first { taskIDs[$0.key] == id }?.value
    }

    private func taskID(for download: WKDownload) -> String? {
        taskIDs[ObjectIdentifier(download)]
    }

    private func task(_ id: String) -> DownloadTask? {
        tasks.first { $0.id == id }
    }

    private func mutate(_ id: String, mutation: (inout DownloadTask) -> Void) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        mutation(&tasks[index])
    }

    private func forget(_ download: WKDownload) {
        let token = ObjectIdentifier(download)
        observations[token] = nil
        active[token] = nil
        taskIDs[token] = nil
        expectedCancellations.remove(token)
    }

    private func restore() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let stored = try? JSONDecoder().decode([DownloadTask].self, from: data) else { return }
        tasks = stored.map { task in
            var copy = task
            let restored = DownloadPolicy.restoredStatus(
                copy.status,
                path: copy.path,
                fileExists: FileManager.default.fileExists(atPath:)
            )
            if restored.status != copy.status {
                copy.status = restored.status
                copy.error = restored.error
            }
            return copy
        }
        persist()
    }

    private func reconcileMissingFile(_ id: String) {
        mutate(id) {
            $0.status = .failed
            $0.error = "missing"
        }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(tasks) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    private func postCompletionNotification(_ task: DownloadTask) {
        guard notificationsEnabled else { return }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                return
            }
            let content = UNMutableNotificationContent()
            content.title = task.fileName
            content.body = "下载完成"
            let request = UNNotificationRequest(identifier: task.id, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }
    }

    private func sanitizedFileName(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "\\/:*?\"<>|").union(.controlCharacters)
        let cleaned = name.components(separatedBy: invalid).joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty || cleaned.allSatisfy { $0 == "." } ? "download" : cleaned
    }

    private func uniqueURL(_ name: String) -> URL {
        let directory = downloadsDirectory
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = directory.appendingPathComponent(name)
        var index = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            let suffix = ext.isEmpty ? "\(base) (\(index))" : "\(base) (\(index)).\(ext)"
            candidate = directory.appendingPathComponent(suffix)
            index += 1
        }
        return candidate
    }
}
