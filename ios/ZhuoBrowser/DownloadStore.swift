import Foundation
import WebKit

enum DownloadStatus: String, Codable {
    case downloading
    case completed
    case failed
}

struct DownloadTask: Identifiable, Equatable, Codable {
    var id: String
    var fileName: String
    var url: String
    var status: DownloadStatus
    var error: String
    var path: String
}

final class DownloadStore: NSObject, ObservableObject, WKDownloadDelegate {
    @Published var tasks: [DownloadTask] = []

    private var active: [ObjectIdentifier: WKDownload] = [:]
    private var taskIDs: [ObjectIdentifier: String] = [:]
    private let defaultsKey = "download_tasks_v1"

    override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let stored = try? JSONDecoder().decode([DownloadTask].self, from: data) {
            tasks = stored.map { task in
                var copy = task
                if copy.status == .downloading {
                    copy.status = .failed
                    copy.error = "interrupted"
                }
                if copy.status == .completed && (copy.path.isEmpty || !FileManager.default.fileExists(atPath: copy.path)) {
                    copy.status = .failed
                    copy.error = "missing"
                }
                return copy
            }
        }
    }

    var downloadsDirectory: URL {
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    func begin(_ download: WKDownload, sourceURL: String) {
        let id = UUID().uuidString
        let token = ObjectIdentifier(download)
        active[token] = download
        taskIDs[token] = id
        download.delegate = self
        let task = DownloadTask(
            id: id,
            fileName: "下载中",
            url: sourceURL,
            status: .downloading,
            error: "",
            path: ""
        )
        tasks.insert(task, at: 0)
        persist()
    }

    func fileURL(for task: DownloadTask) -> URL? {
        guard task.status == .completed, !task.path.isEmpty else {
            return nil
        }
        let url = URL(fileURLWithPath: task.path)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping (URL?) -> Void
    ) {
        let name = sanitizedFileName(suggestedFilename.isEmpty ? (response.suggestedFilename ?? "download") : suggestedFilename)
        let destination = uniqueURL(name)
        update(download) { task in
            task.fileName = name
            task.path = destination.path
            if task.url.isEmpty {
                task.url = response.url?.absoluteString ?? ""
            }
        }
        completionHandler(destination)
    }

    func downloadDidFinish(_ download: WKDownload) {
        update(download) { task in
            task.status = .completed
            task.error = ""
        }
        forget(download)
        persist()
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        update(download) { task in
            task.status = .failed
            task.error = error.localizedDescription
        }
        forget(download)
        persist()
    }

    private func update(_ download: WKDownload, mutate: (inout DownloadTask) -> Void) {
        let token = ObjectIdentifier(download)
        guard let id = taskIDs[token], let index = tasks.firstIndex(where: { $0.id == id }) else {
            return
        }
        mutate(&tasks[index])
    }

    private func forget(_ download: WKDownload) {
        let token = ObjectIdentifier(download)
        active[token] = nil
        taskIDs[token] = nil
    }

    private func persist() {
        let stored = tasks.filter { $0.status != .downloading }
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    private func sanitizedFileName(_ name: String) -> String {
        let cleaned = name.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "download" : cleaned
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
