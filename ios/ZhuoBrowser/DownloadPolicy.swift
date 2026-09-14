import Foundation

enum DownloadPolicyReason: String, Codable, Identifiable {
    case wifiRequired
    case largeFile

    var id: String { rawValue }
}

enum DownloadPolicy {
    static func reason(
        wifiOnly: Bool,
        isWifiConnected: Bool,
        isApproved: Bool,
        totalBytes: Int64,
        largeFileThresholdMB: Int
    ) -> DownloadPolicyReason? {
        if wifiOnly && !isWifiConnected {
            return .wifiRequired
        }
        if isWifiConnected || isApproved || totalBytes <= 0 {
            return nil
        }
        let threshold = Int64(BrowserSettings.clampedLargeDownloadThresholdMB(largeFileThresholdMB))
            * 1_024 * 1_024
        return totalBytes >= threshold ? .largeFile : nil
    }

    static func restoredStatus(
        _ status: DownloadStatus,
        path: String,
        fileExists: (String) -> Bool
    ) -> (status: DownloadStatus, error: String) {
        if status == .completed && (path.isEmpty || !fileExists(path)) {
            return (.failed, "missing")
        }
        if status == .pending || status == .downloading || status == .paused {
            return (.failed, "interrupted")
        }
        return (status, "")
    }
}
