import Foundation

public struct URLPolicy {
    /// Determines whether the input text looks like a valid URL or should be treated as a search query.
    public static func looksLikeURL(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return false }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") || trimmed.hasPrefix("zhuo://") {
            return true
        }
        if trimmed.contains(" ") {
            return false
        }
        // Check for localhost or IP with optional port
        if trimmed.hasPrefix("localhost") || trimmed.hasPrefix("127.0.0.1") {
            return true
        }
        let hostPart = trimmed.split(separator: ":").first ?? ""
        let ipSegments = hostPart.split(separator: ".")
        if ipSegments.count == 4 && ipSegments.allSatisfy({ Int($0) != nil }) {
            return true
        }
        let parts = hostPart.split(separator: ".")
        if parts.count >= 2, let lastPart = parts.last {
            let tld = lastPart.split(separator: "/").first ?? lastPart
            if tld.count >= 2 && tld.allSatisfy({ $0.isLetter }) {
                return true
            }
        }
        return false
    }

    /// Normalizes user omnibox input into a valid navigable URL string.
    public static func normalizeAddress(_ text: String, searchEngine: SearchEngine = .bing) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "zhuo://home"
        }
        if trimmed == "zhuo://home" {
            return trimmed
        }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return trimmed
        }
        if looksLikeURL(trimmed) {
            return "https://" + trimmed
        }
        // Otherwise treat as search query
        if let searchURL = searchEngine.searchURL(for: trimmed) {
            return searchURL.absoluteString
        }
        return "https://www.bing.com/search?q=" + (trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed)
    }

    /// Clean display string for Omnibox (e.g. show domain when not editing)
    public static func displayAddress(for urlString: String) -> String {
        if urlString.isEmpty || urlString == "zhuo://home" {
            return ""
        }
        guard let url = URL(string: urlString) else {
            return urlString
        }
        if let host = url.host {
            return host + (url.path == "/" ? "" : url.path)
        }
        return urlString
    }

    /// Extracts the clean host for a URL string, lowercased and stripped of port/scheme,
    /// without compiling a regular expression on hot render paths.
    public static func rawHost(_ url: String) -> String {
        if isHomeURL(url) {
            return ""
        }
        guard let schemeEnd = url.range(of: "://") else {
            return (URL(string: url)?.host ?? "").lowercased()
        }
        let scheme = url[..<schemeEnd.lowerBound]
        guard let firstChar = scheme.unicodeScalars.first,
              (firstChar.value >= 65 && firstChar.value <= 90) || (firstChar.value >= 97 && firstChar.value <= 122) else {
            return (URL(string: url)?.host ?? "").lowercased()
        }
        let afterScheme = url[schemeEnd.upperBound...]
        let authorityEnd = afterScheme.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) ?? afterScheme.endIndex
        let authority = afterScheme[..<authorityEnd]
        if authority.isEmpty {
            return ""
        }
        let hostSlice: Substring
        if let colonIndex = authority.firstIndex(of: ":") {
            hostSlice = authority[..<colonIndex]
        } else {
            hostSlice = authority
        }
        return hostSlice.lowercased()
    }

    /// Checks if the url is an empty/new tab or internal home url
    public static func isHomeURL(_ url: String) -> Bool {
        url.isEmpty || url == "zhuo://home"
    }

    /// Returns true when the host is loopback, localhost, mDNS `.local`, or a raw IPv4/IPv6 literal
    /// that commonly runs plain HTTP in local development.
    public static func isLocalOrIPHost(_ host: String) -> Bool {
        let lower = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lower.isEmpty { return false }
        if lower == "localhost"
            || lower == "127.0.0.1"
            || lower == "0.0.0.0"
            || lower == "::1"
            || lower == "[::1]"
            || lower.hasSuffix(".local") {
            return true
        }
        if lower.hasPrefix("[") && lower.hasSuffix("]") {
            return true
        }
        let segments = lower.split(separator: ".", omittingEmptySubsequences: false)
        if segments.count == 4 && segments.allSatisfy({ seg in
            guard let value = Int(seg) else { return false }
            return value >= 0 && value <= 255
        }) {
            return true
        }
        return false
    }

    /// Upgrades an `http://` URL string to `https://` when its host is a public domain
    /// (not `localhost`, loopback, `.local`, or a raw IP literal).
    public static func upgradeToHTTPSIfPublicHost(_ urlString: String) -> String {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("http://") else { return trimmed }
        let host = rawHost(trimmed)
        guard !host.isEmpty, !isLocalOrIPHost(host) else { return trimmed }
        return "https://" + trimmed.dropFirst(7)
    }
}
