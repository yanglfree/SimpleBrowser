import Foundation

enum AuthProviderKind: String, CaseIterable, Identifiable, Codable {
    case emailOTP = "email_otp"
    case emailPassword = "email_password"
    case apple = "apple"
    case google = "google"

    var id: String { rawValue }
}

struct CloudUserProfile: Codable, Equatable, Identifiable {
    let id: String
    let email: String
    let displayName: String
    let avatarUrl: String?
}

struct LinkedIdentityRecord: Codable, Equatable, Identifiable {
    let provider: String
    let email: String?
    let emailVerified: Bool

    var id: String { provider }

    var displayLabel: String {
        switch provider.lowercased() {
        case "apple": return "Apple 账号"
        case "google": return "Google 账号"
        case "huawei": return "华为账号"
        default: return "邮箱"
        }
    }
}

struct RemoteDeviceTabEntry: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    let url: String
    let lastVisitedAt: Int64
}

struct RemoteDeviceTabGroup: Codable, Equatable, Identifiable {
    let deviceId: String
    let deviceName: String
    let platform: String
    let updatedAt: Int64
    let tabs: [RemoteDeviceTabEntry]

    var id: String { deviceId }
}

struct ArticleTombstone: Codable, Equatable, Identifiable {
    let id: String
    let canonicalUrl: String?
    let deletedAt: TimeInterval
}

enum RegionAuthPolicy {
    private static let mainlandTimezones: Set<String> = [
        "Asia/Shanghai",
        "Asia/Chongqing",
        "Asia/Harbin",
        "Asia/Urumqi"
    ]

    static func isMainlandChinaRegion(
        regionCode: String? = Locale.current.region?.identifier,
        timeZoneIdentifier: String = TimeZone.current.identifier
    ) -> Bool {
        let trimmed = (regionCode ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if trimmed.count == 2, trimmed.allSatisfy({ $0.isLetter }) {
            return trimmed == "CN"
        }
        return mainlandTimezones.contains(timeZoneIdentifier)
    }

    static func isGoogleSignInAvailable(
        regionCode: String? = Locale.current.region?.identifier,
        timeZoneIdentifier: String = TimeZone.current.identifier
    ) -> Bool {
        !isMainlandChinaRegion(regionCode: regionCode, timeZoneIdentifier: timeZoneIdentifier)
    }

    static func availableProviders(
        regionCode: String? = Locale.current.region?.identifier,
        timeZoneIdentifier: String = TimeZone.current.identifier
    ) -> [AuthProviderKind] {
        var list: [AuthProviderKind] = [.emailOTP, .emailPassword, .apple]
        if isGoogleSignInAvailable(regionCode: regionCode, timeZoneIdentifier: timeZoneIdentifier) {
            list.append(.google)
        }
        return list
    }

    static func sanitizeDeviceTabs(_ tabs: [BrowserTab], maxCount: Int = 50) -> [[String: Any]] {
        var output: [[String: Any]] = []
        var seen = Set<String>()
        for tab in tabs {
            guard !tab.isPrivate else { continue }
            let trimmed = tab.url.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = trimmed.lowercased()
            if trimmed.isEmpty
                || URLPolicy.isHomeURL(trimmed)
                || lower == "about:blank"
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
