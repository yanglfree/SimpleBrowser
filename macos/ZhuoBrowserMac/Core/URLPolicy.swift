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
        // Check for common domain patterns or localhost / IP
        if trimmed.hasPrefix("localhost") || trimmed.hasPrefix("127.0.0.1") {
            return true
        }
        let parts = trimmed.split(separator: ".")
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
}
