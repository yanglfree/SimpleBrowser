import Foundation
import UniformTypeIdentifiers

public enum DownloadState: String, Codable, Equatable, Sendable {
    case downloading
    case completed
    case failed
    case cancelled
}

public struct DownloadItem: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public var sourceURL: String
    public var filename: String
    public var destinationPath: String
    public var receivedBytes: Int64
    public var totalBytes: Int64
    public var state: DownloadState
    public var errorMessage: String?
    public var createdAt: TimeInterval
    public var completedAt: TimeInterval?

    public init(
        id: String = UUID().uuidString,
        sourceURL: String,
        filename: String,
        destinationPath: String,
        receivedBytes: Int64 = 0,
        totalBytes: Int64 = -1,
        state: DownloadState = .downloading,
        errorMessage: String? = nil,
        createdAt: TimeInterval = Date().timeIntervalSince1970,
        completedAt: TimeInterval? = nil
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.filename = filename
        self.destinationPath = destinationPath
        self.receivedBytes = receivedBytes
        self.totalBytes = totalBytes
        self.state = state
        self.errorMessage = errorMessage
        self.createdAt = createdAt
        self.completedAt = completedAt
    }

    public var progress: Double? {
        guard totalBytes > 0 else { return nil }
        return min(1.0, max(0.0, Double(receivedBytes) / Double(totalBytes)))
    }

    public var fileExistsOnDisk: Bool {
        guard !destinationPath.isEmpty else { return false }
        return FileManager.default.fileExists(atPath: destinationPath)
    }

    public var statusText: String {
        switch state {
        case .downloading:
            if totalBytes > 0 {
                return "\(DownloadPolicy.formatByteCount(receivedBytes)) / \(DownloadPolicy.formatByteCount(totalBytes))"
            } else if receivedBytes > 0 {
                return DownloadPolicy.formatByteCount(receivedBytes)
            } else {
                return "正在下载…"
            }
        case .completed:
            let bytes = max(receivedBytes, totalBytes)
            if bytes > 0 {
                return DownloadPolicy.formatByteCount(bytes)
            }
            return "已完成"
        case .cancelled:
            return "已取消"
        case .failed:
            if let errorMessage, !errorMessage.isEmpty {
                return "下载失败 — \(errorMessage)"
            }
            return "下载失败"
        }
    }
}

public enum DownloadPolicy {
    public static let maxStoredDownloads = 200

    /// Determines whether the top-right toolbar Downloads button should be visible.
    /// Follows Safari/mainstream browser behavior: hidden when there are no download records
    /// and the popover is not explicitly open; shown automatically as soon as a download starts
    /// or While un-cleared download items remain.
    public static func shouldShowToolbarButton(
        items: [DownloadItem],
        isPopoverPresented: Bool
    ) -> Bool {
        !items.isEmpty || isPopoverPresented
    }

    /// Sanitizes an untrusted suggested filename so it can never traverse directories or
    /// produce an empty/hidden file name in the user's Downloads folder.
    public static func sanitizeFilename(_ raw: String, fallback: String = "download") -> String {
        let trimmed = raw
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "\0", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let cleaned = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return cleaned.isEmpty ? fallback : cleaned
    }

    /// Resolves a collision-free file URL inside `directory` using macOS Finder/Safari
    /// numbering conventions (`name.ext`, `name (1).ext`, `name (2).ext`, ...).
    public static func uniqueDestinationURL(
        in directory: URL,
        suggestedFilename: String,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> URL {
        let safeName = sanitizeFilename(suggestedFilename)
        let initialURL = directory.appendingPathComponent(safeName, isDirectory: false)
        if !fileExists(initialURL.path) {
            return initialURL
        }

        let nsName = safeName as NSString
        let ext = nsName.pathExtension
        let base = ext.isEmpty ? safeName : nsName.deletingPathExtension

        var counter = 1
        while counter < 10_000 {
            let candidateName = ext.isEmpty
                ? "\(base) (\(counter))"
                : "\(base) (\(counter)).\(ext)"
            let candidateURL = directory.appendingPathComponent(candidateName, isDirectory: false)
            if !fileExists(candidateURL.path) {
                return candidateURL
            }
            counter += 1
        }

        let uuidSuffix = UUID().uuidString.prefix(6)
        let fallbackName = ext.isEmpty ? "\(base)-\(uuidSuffix)" : "\(base)-\(uuidSuffix).\(ext)"
        return directory.appendingPathComponent(fallbackName, isDirectory: false)
    }

    /// Checks whether an HTTP response explicitly requests attachment download semantics
    /// or carries a binary/archive/certificate MIME type that should be downloaded rather
    /// than rendered as plain text.
    public static func shouldDownloadResponse(
        _ response: URLResponse?,
        canShowMIMEType: Bool
    ) -> Bool {
        if !canShowMIMEType {
            return true
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            return false
        }
        if let disposition = httpResponse.value(forHTTPHeaderField: "Content-Disposition")?
            .lowercased(),
           disposition.contains("attachment") {
            return true
        }
        if let mime = response?.mimeType?.lowercased() {
            let forcedDownloadMIMEs: Set<String> = [
                "application/octet-stream",
                "application/x-apple-diskimage",
                "application/x-pkcs7-certificates",
                "application/pkcs7-mime",
                "application/x-x509-ca-cert",
                "application/zip",
                "application/x-rar-compressed",
                "application/x-7z-compressed",
                "application/x-tar",
                "application/gzip"
            ]
            if forcedDownloadMIMEs.contains(mime) {
                return true
            }
        }
        return false
    }

    /// Formats byte counts to match Safari's concise representation (`4 KB`, `129 KB`, `2.4 MB`).
    public static func formatByteCount(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "0 KB" }
        if bytes < 1024 {
            return "1 KB"
        }
        let kb = Double(bytes) / 1024.0
        if kb < 1024.0 {
            return "\(Int(kb.rounded())) KB"
        }
        let mb = kb / 1024.0
        if mb < 1024.0 {
            return String(format: mb >= 100 ? "%.0f MB" : "%.1f MB", mb)
        }
        let gb = mb / 1024.0
        return String(format: "%.2f GB", gb)
    }
}
