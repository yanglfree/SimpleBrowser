import Foundation

enum SearchEngine: Int, Codable {
    case bing = 0
    case baidu = 1
    case google = 2
    case duckDuckGo = 3
}

enum URLPolicy {
    static let homeURL = "browser://home"

    private static let searchEndpoints = [
        "https://www.bing.com/search?q=",
        "https://m.baidu.com/s?word=",
        "https://www.google.com/search?q=",
        "https://duckduckgo.com/?q="
    ]

    static func isHomeURL(_ url: String) -> Bool {
        url.isEmpty || url == homeURL
    }

    static func looksLikeURL(_ input: String) -> Bool {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty || value.range(of: "\\s", options: .regularExpression) != nil {
            return false
        }
        if hasExplicitScheme(value) {
            return true
        }
        return isAddressHost(addressHost(value))
    }

    static func normalizeAddress(_ input: String, engine: SearchEngine = .bing) -> String {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty {
            return homeURL
        }
        let normalized = normalizeURLInput(value)
        if !normalized.isEmpty {
            return normalized
        }
        return searchURL(value, engine: engine)
    }

    static func desktopURL(for url: String) -> String {
        guard let match = url.range(of: "^(https?)://([^/?#]+)(.*)$", options: [.regularExpression, .caseInsensitive]) else {
            return url
        }
        let full = String(url[match])
        guard let schemeEnd = full.range(of: "://") else {
            return url
        }
        let rest = full[schemeEnd.upperBound...]
        let hostEnd = rest.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) ?? rest.endIndex
        let host = String(rest[..<hostEnd]).split(separator: ":").first.map(String.init)?.lowercased() ?? ""
        if host != "m.weibo.cn" {
            return url
        }
        return "https://weibo.com" + String(rest[hostEnd...])
    }

    static func displayHost(_ url: String) -> String {
        if isHomeURL(url) {
            return ""
        }
        let host = hostOf(url) ?? url
        let withoutPort = host.split(separator: ":").first.map(String.init) ?? host
        if withoutPort.hasPrefix("www.") {
            return String(withoutPort.dropFirst(4))
        }
        if withoutPort.hasPrefix("m.") {
            return String(withoutPort.dropFirst(2))
        }
        return withoutPort
    }

    static func rawHost(_ url: String) -> String {
        guard let host = hostOf(url) else {
            return ""
        }
        return (host.split(separator: ":").first.map(String.init) ?? host).lowercased()
    }

    private static func searchEndpoint(_ engine: SearchEngine) -> String {
        let index = engine.rawValue
        if index >= 0 && index < searchEndpoints.count {
            return searchEndpoints[index]
        }
        return searchEndpoints[0]
    }

    static func searchURL(_ query: String, engine: SearchEngine) -> String {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = value.split { $0.isWhitespace }.map(String.init)
        var resolved = engine
        var terms = value
        if parts.count > 1 {
            switch parts[0].lowercased() {
            case "g":
                resolved = .google
                terms = String(value.dropFirst(parts[0].count)).trimmingCharacters(in: .whitespaces)
            case "b":
                resolved = .baidu
                terms = String(value.dropFirst(parts[0].count)).trimmingCharacters(in: .whitespaces)
            case "ddg":
                resolved = .duckDuckGo
                terms = String(value.dropFirst(parts[0].count)).trimmingCharacters(in: .whitespaces)
            case "bing":
                resolved = .bing
                terms = String(value.dropFirst(parts[0].count)).trimmingCharacters(in: .whitespaces)
            default:
                break
            }
        }
        return searchEndpoint(resolved) + encodeURIComponent(terms)
    }

    private static func normalizeURLInput(_ input: String) -> String {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if !looksLikeURL(value) {
            return ""
        }
        if hasExplicitScheme(value) {
            return value
        }
        let host = addressHost(value).lowercased()
        let localOrIP = host == "localhost" || host.hasPrefix("[") || validIPv4(host)
        return "\(localOrIP ? "http" : "https")://\(value)"
    }

    private static func hasExplicitScheme(_ value: String) -> Bool {
        value.range(of: "^[a-z][a-z0-9+.-]*://", options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func validPort(_ value: String) -> Bool {
        guard value.range(of: "^\\d+$", options: .regularExpression) != nil,
              let port = Int(value) else {
            return false
        }
        return port > 0 && port <= 65535
    }

    private static func validIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 4 else {
            return false
        }
        return parts.allSatisfy { part in
            guard part.range(of: "^\\d{1,3}$", options: .regularExpression) != nil,
                  let octet = Int(part) else {
                return false
            }
            return octet >= 0 && octet <= 255
        }
    }

    private static func validDomain(_ host: String) -> Bool {
        if host.count > 253 || host.hasPrefix(".") || host.hasSuffix(".") {
            return false
        }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        if labels.count < 2 {
            return false
        }
        return labels.allSatisfy { label in
            !label.isEmpty && label.count <= 63 && !label.hasPrefix("-") && !label.hasSuffix("-")
                && label.range(of: "^[^\\s/:?#.]+$", options: .regularExpression) != nil
        }
    }

    private static func addressHost(_ value: String) -> String {
        let boundary = value.range(of: "[/?#]", options: .regularExpression)?.lowerBound
        let authority = boundary.map { String(value[..<$0]) } ?? value
        if authority.hasPrefix("[") {
            guard let close = authority.firstIndex(of: "]") else {
                return ""
            }
            let host = String(authority[...close])
            if host.count <= 2 {
                return ""
            }
            let suffix = String(authority[authority.index(after: close)...])
            if suffix.isEmpty || (suffix.hasPrefix(":") && validPort(String(suffix.dropFirst()))) {
                return host
            }
            return ""
        }
        if let first = authority.firstIndex(of: ":") {
            let last = authority.lastIndex(of: ":") ?? first
            if first != last || !validPort(String(authority[authority.index(after: last)...])) {
                return ""
            }
            return String(authority[..<last])
        }
        return authority
    }

    private static func isAddressHost(_ host: String) -> Bool {
        if host.lowercased() == "localhost" {
            return true
        }
        if host.hasPrefix("[") && host.hasSuffix("]") {
            return host.dropFirst().dropLast().contains(":")
        }
        let numericDotted = host.range(of: "^\\d+(\\.\\d+){3}$", options: .regularExpression) != nil
        return numericDotted ? validIPv4(host) : validDomain(host)
    }

    private static func hostOf(_ url: String) -> String? {
        guard let match = url.range(of: "^[a-z][a-z0-9+.-]*://([^/?#]+)", options: [.regularExpression, .caseInsensitive]) else {
            return nil
        }
        let matched = String(url[match])
        guard let schemeEnd = matched.range(of: "://") else {
            return nil
        }
        return String(matched[schemeEnd.upperBound...])
    }

    private static func encodeURIComponent(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.!~*'()")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
