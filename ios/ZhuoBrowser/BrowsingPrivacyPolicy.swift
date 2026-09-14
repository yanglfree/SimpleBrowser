import Foundation

enum BrowsingDataRange: Int, CaseIterable, Identifiable {
    case all = 0
    case today = 1
    case sevenDays = 7
    case thirtyDays = 30

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .all: return "全部时间"
        case .today: return "今天"
        case .sevenDays: return "过去 7 天"
        case .thirtyDays: return "过去 30 天"
        }
    }
}

struct BrowsingDataSelection: Equatable {
    var history = true
    var cookies = true
    var cache = true
    var permissions = true
    var range: BrowsingDataRange = .all

    var hasSelection: Bool {
        history || cookies || cache || permissions
    }
}

enum BrowsingPrivacyPolicy {
    static func cutoff(
        for range: BrowsingDataRange,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Date {
        switch range {
        case .all:
            return .distantPast
        case .today:
            return calendar.startOfDay(for: now)
        case .sevenDays, .thirtyDays:
            return now.addingTimeInterval(-TimeInterval(range.rawValue * 24 * 60 * 60))
        }
    }

    static func recordDisplayName(_ displayName: String, matches host: String) -> Bool {
        let record = displayName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedHost = host.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !record.isEmpty, !normalizedHost.isEmpty else { return false }
        return normalizedHost == record || normalizedHost.hasSuffix(".\(record)")
    }
}

enum SiteSecurityState: String, Codable {
    case secure
    case insecure
    case certificateError
    case unknown
}

struct SiteSecurityWarning: Identifiable {
    let id = UUID()
    let host: String
}

enum SiteSecurityPolicy {
    static let messageHandlerName = "zhuoSecurity"

    static func state(for rawURL: String, hasOnlySecureContent: Bool = true) -> SiteSecurityState {
        guard let scheme = URL(string: rawURL)?.scheme?.lowercased() else { return .unknown }
        if scheme == "https" {
            return hasOnlySecureContent ? .secure : .insecure
        }
        if scheme == "http" {
            return .insecure
        }
        return .unknown
    }

    static func provisionalState(for rawURL: String) -> SiteSecurityState {
        URL(string: rawURL)?.scheme?.lowercased() == "http" ? .insecure : .unknown
    }

    static func shouldWarnForPasswordFocus(on rawURL: String) -> Bool {
        URL(string: rawURL)?.scheme?.lowercased() == "http"
    }

    static func isCertificateError(_ error: Error) -> Bool {
        let error = error as NSError
        guard error.domain == NSURLErrorDomain else { return false }
        let code = error.code
        return [
            NSURLErrorServerCertificateHasBadDate,
            NSURLErrorServerCertificateUntrusted,
            NSURLErrorServerCertificateHasUnknownRoot,
            NSURLErrorServerCertificateNotYetValid,
            NSURLErrorClientCertificateRejected,
            NSURLErrorClientCertificateRequired
        ].contains(code)
    }
}
