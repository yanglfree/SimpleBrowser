import Foundation

public enum MacAuthProvider: String, CaseIterable, Identifiable, Codable, Sendable {
    case emailOTP = "email_otp"
    case emailPassword = "email_password"
    case apple = "apple"
    case google = "google"

    public var id: String { rawValue }
}

public struct LinkedIdentityInfo: Identifiable, Codable, Equatable, Sendable {
    public let provider: String
    public let email: String?
    public let emailVerified: Bool

    public var id: String { provider }

    public var displayLabel: String {
        switch provider.lowercased() {
        case "apple": return "Apple 账号"
        case "google": return "Google 账号"
        case "huawei": return "华为账号"
        default: return "邮箱"
        }
    }
}

public struct CloudProEntitlement: Codable, Equatable, Sendable {
    public let active: Bool
    public let scope: String
    public let plan: String?
    public let productId: String
    public let expiresAt: Int64
    public let source: String
    public let verifiedAt: Int64
}

public struct RemoteDeviceTabEntry: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let url: String
    public let lastVisitedAt: Int64
}

public struct RemoteDeviceTabGroup: Identifiable, Codable, Equatable, Sendable {
    public let deviceId: String
    public let deviceName: String
    public let platform: String
    public let updatedAt: Int64
    public let tabs: [RemoteDeviceTabEntry]

    public var id: String { deviceId }
}

public enum RegionAuthPolicy {
    private static let mainlandTimezones: Set<String> = [
        "Asia/Shanghai",
        "Asia/Chongqing",
        "Asia/Harbin",
        "Asia/Urumqi"
    ]

    public static func isMainlandChinaRegion(
        regionCode: String? = Locale.current.region?.identifier,
        timeZoneIdentifier: String = TimeZone.current.identifier
    ) -> Bool {
        let trimmed = (regionCode ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if trimmed.count == 2, trimmed.allSatisfy({ $0.isLetter }) {
            return trimmed == "CN"
        }
        return mainlandTimezones.contains(timeZoneIdentifier)
    }

    public static func isGoogleSignInAvailable(
        regionCode: String? = Locale.current.region?.identifier,
        timeZoneIdentifier: String = TimeZone.current.identifier
    ) -> Bool {
        !isMainlandChinaRegion(regionCode: regionCode, timeZoneIdentifier: timeZoneIdentifier)
    }

    public static func availableProviders(
        regionCode: String? = Locale.current.region?.identifier,
        timeZoneIdentifier: String = TimeZone.current.identifier
    ) -> [MacAuthProvider] {
        var list: [MacAuthProvider] = [.emailOTP, .emailPassword, .apple]
        if isGoogleSignInAvailable(regionCode: regionCode, timeZoneIdentifier: timeZoneIdentifier) {
            list.append(.google)
        }
        return list
    }

    /// Sanitizes open tabs before cloud device-tab publication: drops private tabs,
    /// internal `zhuo://` / `browser://` pages, and duplicate URLs.
    public static func sanitizeDeviceTabs(_ tabs: [BrowserTab], maxCount: Int = 50) -> [[String: Any]] {
        var output: [[String: Any]] = []
        var seen = Set<String>()
        for tab in tabs {
            guard !tab.isPrivate else { continue }
            let trimmed = tab.url.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = trimmed.lowercased()
            if trimmed.isEmpty
                || lower == "about:blank"
                || lower.hasPrefix("zhuo://")
                || lower.hasPrefix("browser://")
                || lower.hasPrefix("javascript:")
                || lower.hasPrefix("data:") {
                continue
            }
            let comparable = lower.hasSuffix("/") && lower.count > 1 ? String(lower.dropLast()) : lower
            guard seen.insert(comparable).inserted else { continue }
            output.append([
                "id": tab.id,
                "title": tab.title.isEmpty ? trimmed : tab.title,
                "url": trimmed,
                "isPrivate": false,
                "lastVisitedAt": Int64(Date().timeIntervalSince1970 * 1000)
            ])
            if output.count >= maxCount { break }
        }
        return output
    }
}
