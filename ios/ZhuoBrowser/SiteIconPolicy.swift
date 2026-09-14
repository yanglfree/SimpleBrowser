import Foundation

struct SiteIconRequest: Equatable {
    let url: String
    let isPrivate: Bool
}

enum SiteIconPolicy {
    static let cacheTTL: TimeInterval = 14 * 24 * 60 * 60
    static let maximumIconBytes = 256 * 1_024
    static let maximumPageBytes = 512 * 1_024
    private static let maximumMetadataCandidates = 8

    static func targets(_ requests: [SiteIconRequest]) -> [SiteIconRequest] {
        var hosts = Set<String>()
        return requests.compactMap { request in
            let host = URLPolicy.rawHost(request.url)
            guard !request.isPrivate,
                !URLPolicy.isHomeURL(request.url),
                !host.isEmpty,
                hosts.insert(host).inserted
            else {
                return nil
            }
            return SiteIconRequest(url: request.url, isPrivate: false)
        }
    }

    static func cacheFileName(for host: String) -> String {
        let safe = host.lowercased().replacingOccurrences(
            of: "[^a-z0-9.-]",
            with: "_",
            options: .regularExpression
        )
        return safe.isEmpty ? "" : "\(safe).icon"
    }

    static func isCacheFresh(modifiedAt: Date, now: Date = Date()) -> Bool {
        let age = now.timeIntervalSince(modifiedAt)
        return age >= 0 && age < cacheTTL
    }

    static func candidates(
        pageURL rawPageURL: String,
        declaredURL rawDeclaredURL: String? = nil,
        html: String? = nil
    ) -> [URL] {
        guard let pageURL = webURL(rawPageURL) else { return [] }
        var values: [URL] = []
        if let html {
            values.append(contentsOf: metadataCandidates(html: html, pageURL: pageURL))
        }
        if let rawDeclaredURL, let declared = resolvedWebURL(rawDeclaredURL, relativeTo: pageURL) {
            values.append(declared)
        }
        for path in ["/apple-touch-icon.png", "/apple-touch-icon-precomposed.png", "/favicon.ico"] {
            if let fallback = resolvedWebURL(path, relativeTo: pageURL) {
                values.append(fallback)
            }
        }

        var seen = Set<String>()
        return values.filter { seen.insert($0.absoluteString).inserted }
    }

    static func metadataCandidates(html: String, pageURL: URL) -> [URL] {
        guard
            let linkExpression = try? NSRegularExpression(
                pattern: #"<link\b[^>]*>"#,
                options: [.caseInsensitive]
            )
        else { return [] }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        var values: [(url: URL, score: Int, order: Int)] = []
        var seen = Set<String>()
        for (order, match) in linkExpression.matches(in: html, range: range).enumerated() {
            guard let tagRange = Range(match.range, in: html) else { continue }
            let tag = String(html[tagRange])
            let relation = attribute("rel", in: tag).lowercased()
            let type = attribute("type", in: tag).lowercased()
            let supportedType =
                type.isEmpty
                || ["png", "icon", "jpeg", "jpg", "webp", "svg"].contains(where: type.contains)
            guard relation.contains("icon"), supportedType,
                let url = resolvedWebURL(attribute("href", in: tag), relativeTo: pageURL),
                seen.insert(url.absoluteString).inserted
            else {
                continue
            }
            let sizeScore = declaredSize(attribute("sizes", in: tag)) * 2
            let touchScore = relation.contains("apple-touch-icon") ? 1 : 0
            values.append((url, sizeScore + touchScore, order))
        }
        return
            values
            .sorted { $0.score == $1.score ? $0.order < $1.order : $0.score > $1.score }
            .prefix(maximumMetadataCandidates)
            .map(\.url)
    }

    private static func attribute(_ name: String, in tag: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        guard
            let expression = try? NSRegularExpression(
                pattern: #"\b"# + escaped + #"\s*=\s*(?:\"([^\"]*)\"|'([^']*)'|([^\s\"'=<>]+))"#,
                options: [.caseInsensitive]
            )
        else { return "" }
        let range = NSRange(tag.startIndex..<tag.endIndex, in: tag)
        guard let match = expression.firstMatch(in: tag, range: range) else { return "" }
        for index in 1..<match.numberOfRanges where match.range(at: index).location != NSNotFound {
            if let valueRange = Range(match.range(at: index), in: tag) {
                return String(tag[valueRange])
            }
        }
        return ""
    }

    private static func declaredSize(_ value: String) -> Int {
        guard let expression = try? NSRegularExpression(pattern: #"(\d+)x(\d+)"#, options: [.caseInsensitive]) else {
            return 0
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return expression.matches(in: value, range: range).reduce(0) { largest, match in
            guard match.numberOfRanges == 3,
                let widthRange = Range(match.range(at: 1), in: value),
                let heightRange = Range(match.range(at: 2), in: value),
                let width = Int(value[widthRange]),
                let height = Int(value[heightRange])
            else {
                return largest
            }
            return max(largest, min(width, height))
        }
    }

    private static func webURL(_ value: String) -> URL? {
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased(),
            scheme == "https" || scheme == "http",
            url.host?.isEmpty == false
        else {
            return nil
        }
        return url
    }

    private static func resolvedWebURL(_ value: String, relativeTo pageURL: URL) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
            let url = URL(string: trimmed, relativeTo: pageURL)?.absoluteURL,
            let scheme = url.scheme?.lowercased(),
            scheme == "https" || scheme == "http",
            url.host?.isEmpty == false
        else {
            return nil
        }
        return url
    }
}
