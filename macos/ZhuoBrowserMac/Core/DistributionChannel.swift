import Foundation

/// Identifies which distribution channel built and packaged the current macOS binary.
///
/// Apple's Mac App Store review guidelines (2.5.2) prohibit downloading or importing
/// arbitrary external executable extension packages/scripts at runtime, whereas the
/// notarized Developer ID DMG distributed on the official website permits them.
public enum DistributionChannel: String, CaseIterable, Sendable {
    case appStore = "appstore"
    case directDMG = "dmg"

    /// Unit-test override so tests can verify both Mac App Store and Direct DMG behavior.
    public static var overrideForTesting: DistributionChannel? = nil

    /// Resolves the active distribution channel for the running process.
    public static var current: DistributionChannel {
        if let overrideForTesting {
            return overrideForTesting
        }
        if RuntimeEnvironment.isRunningUnitTests {
            return .directDMG
        }
        if let rawValue = Bundle.main.object(forInfoDictionaryKey: "ZhuoDistributionChannel") as? String {
            let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if normalized == "appstore" || normalized == "mas" {
                return .appStore
            }
            if normalized == "dmg" || normalized == "direct" {
                return .directDMG
            }
        }
        if let receiptURL = Bundle.main.appStoreReceiptURL,
           receiptURL.lastPathComponent == "receipt",
           FileManager.default.fileExists(atPath: receiptURL.path) {
            return .appStore
        }
        return .appStore
    }

    /// Whether loading unpacked Chrome extensions, `.crx`/`.zip`/`.user.js` packages,
    /// and Developer Mode hot-reload tools is allowed in this build.
    public var allowsExternalExtensionPackages: Bool {
        self == .directDMG
    }

    public var displayName: String {
        switch self {
        case .appStore:
            return "Mac App Store 官方版"
        case .directDMG:
            return "官网公证独立分发版 (DMG)"
        }
    }

    public var channelSummary: String {
        switch self {
        case .appStore:
            return "已内置 5 大精选扩展工具并采用系统沙盒机制；如需导入外部 .crx 扩展或启用开发者模式，请前往官网获取公证独立分发版 (DMG)。"
        case .directDMG:
            return "Developer ID 签名并经 Apple 公证，完整开放外部 .crx / .zip / .user.js 扩展安装与开发者调试模式。"
        }
    }
}
