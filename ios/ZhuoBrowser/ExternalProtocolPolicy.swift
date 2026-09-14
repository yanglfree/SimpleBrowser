import Foundation

enum ExternalProtocolCategory: String, Equatable {
    case appInstall
    case communication
    case navigation
    case payment
    case social
    case fileTransfer
    case custom

    var promptTitle: String {
        switch self {
        case .appInstall: return "打开安装服务？"
        case .payment: return "打开支付应用？"
        default: return "打开其他应用？"
        }
    }
}

struct ExternalProtocolRequest: Identifiable, Equatable {
    let url: String
    let scheme: String
    let category: ExternalProtocolCategory
    let sourceHost: String

    var id: String { url }

    var promptMessage: String {
        let source = sourceHost.isEmpty ? "当前页面" : sourceHost
        return "\(source) 想要打开 \(scheme)://。仅在你信任此页面时继续。"
    }
}

enum ExternalNavigationDecision: Equatable {
    case allow
    case blocked
    case confirm(ExternalProtocolRequest)
}

enum ExternalProtocolPolicy {
    private static let webSchemes: Set<String> = [
        "http", "https", "about", "data", "blob", "file", "resource", "browser"
    ]
    private static let blockedSchemes: Set<String> = [
        "javascript", "arkweb", "webkit", "chrome", "chrome-devtools", "devtools"
    ]
    private static let appInstallSchemes: Set<String> = [
        "store", "market", "appmarket", "intent", "hap", "itms-apps", "itms-services"
    ]
    private static let communicationSchemes: Set<String> = [
        "tel", "sms", "smsto", "mms", "mmsto", "mailto", "sip", "im"
    ]
    private static let navigationSchemes: Set<String> = [
        "geo", "map", "maps", "amap", "baidumap", "petalmaps"
    ]
    private static let paymentSchemes: Set<String> = [
        "alipay", "alipays", "weixin", "wechat", "wxp", "unionpay", "upwallet"
    ]
    private static let socialSchemes: Set<String> = [
        "mqq", "mqqapi", "qq", "sinaweibo", "weibo", "zhihu", "bilibili",
        "taobao", "openapp.jdmobile"
    ]
    private static let fileTransferSchemes: Set<String> = [
        "ftp", "ftps", "sftp", "magnet", "ed2k"
    ]

    static func scheme(for rawURL: String) -> String {
        let value = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = value.range(
            of: "^[a-z][a-z0-9+.-]*:",
            options: [.regularExpression, .caseInsensitive]
        ) else {
            return ""
        }
        return value[match].dropLast().lowercased()
    }

    static func decision(for rawURL: String, sourceURL: String) -> ExternalNavigationDecision {
        let value = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let scheme = scheme(for: value)
        if scheme.isEmpty || webSchemes.contains(scheme) {
            return .allow
        }
        if blockedSchemes.contains(scheme) {
            return .blocked
        }
        return .confirm(
            ExternalProtocolRequest(
                url: value,
                scheme: scheme,
                category: category(for: scheme),
                sourceHost: URLPolicy.displayHost(sourceURL).lowercased()
            )
        )
    }

    static func clipboardAddress(from text: String, engine: SearchEngine) -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, URLPolicy.looksLikeURL(value) else { return nil }
        let normalized = URLPolicy.normalizeAddress(value, engine: engine)
        guard ["http", "https"].contains(scheme(for: normalized)) else { return nil }
        return normalized
    }

    private static func category(for scheme: String) -> ExternalProtocolCategory {
        if appInstallSchemes.contains(scheme) { return .appInstall }
        if communicationSchemes.contains(scheme) { return .communication }
        if navigationSchemes.contains(scheme) { return .navigation }
        if paymentSchemes.contains(scheme) { return .payment }
        if socialSchemes.contains(scheme) { return .social }
        if fileTransferSchemes.contains(scheme) { return .fileTransfer }
        return .custom
    }
}
