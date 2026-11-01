import Foundation

/// Classification of an Omnibox autocomplete suggestion.
public enum OmniboxSuggestionKind: Int, Equatable, Sendable {
    /// Domain / host suggestion extracted from browsing history or bookmarks (Priority 1).
    case host = 0
    /// Full URL suggestion from browsing history (Priority 2).
    case history = 1
    /// Full URL suggestion from saved bookmarks / favorites (Priority 2).
    case bookmark = 2
    /// Fallback search query suggestion for the active search engine (Priority 3).
    case search = 3
}

/// Indicates which user library data source(s) produced a suggestion.
public enum OmniboxSuggestionSource: Equatable, Sendable {
    case history
    case bookmark
    case historyAndBookmark
    case searchEngine

    public var badgeLabel: String {
        switch self {
        case .historyAndBookmark:
            return "收藏与历史"
        case .bookmark:
            return "收藏夹"
        case .history:
            return "历史记录"
        case .searchEngine:
            return "搜索"
        }
    }
}

/// A single ranked autocomplete candidate for the macOS Omnibox and Start Page search bar.
public struct OmniboxSuggestion: Identifiable, Equatable, Sendable {
    public let id: String
    public let kind: OmniboxSuggestionKind
    public let source: OmniboxSuggestionSource
    /// Primary title displayed in the suggestion row (host string for `.host`, page title for full links).
    public let title: String
    /// Secondary label displayed in the suggestion row (site title for `.host`, full URL for full links).
    public let subtitle: String
    /// Navigable destination URL when this suggestion is committed.
    public let url: String
    /// Text placed into the address bar when selecting or tab-completing this suggestion.
    public let completionText: String
    /// Clean lowercased host for favicon lookup in `BrowserSession.siteIcons`.
    public let host: String
    /// Optional bundled favorite icon asset name (e.g. `fav_google`).
    public let iconName: String?

    public init(
        id: String,
        kind: OmniboxSuggestionKind,
        source: OmniboxSuggestionSource,
        title: String,
        subtitle: String,
        url: String,
        completionText: String,
        host: String,
        iconName: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.source = source
        self.title = title
        self.subtitle = subtitle
        self.url = url
        self.completionText = completionText
        self.host = host
        self.iconName = iconName
    }
}

/// Pure policy engine for macOS URL autocomplete & suggestion ranking.
///
/// Priority order:
/// 1. **Host suggestions** (`kind == .host`) extracted from browsing history and bookmarks/favorites.
/// 2. **Full link suggestions** (`kind == .history` / `.bookmark`) from browsing history and bookmarks/favorites.
/// 3. **Search suggestion** (`kind == .search`) fallback for the active search engine.
public enum OmniboxSuggestionPolicy {
    public static let defaultMaxSuggestions = 8
    public static let maxHostReserveWhenFullLinksExist = 5

    private struct AggregatedHostCandidate {
        var authority: String
        var rawHost: String
        var bareHost: String
        var scheme: String
        var rootTitle: String
        var fallbackTitle: String
        var iconName: String?
        var isFromHistory: Bool
        var isFromBookmark: Bool
        var visitCount: Int
        var latestTimestamp: TimeInterval

        var source: OmniboxSuggestionSource {
            if isFromHistory && isFromBookmark { return .historyAndBookmark }
            if isFromBookmark { return .bookmark }
            return .history
        }

        var canonicalURL: String {
            "\(scheme)://\(authority)"
        }

        var displaySubtitle: String {
            if !rootTitle.isEmpty && rootTitle.lowercased() != authority && rootTitle.lowercased() != bareHost {
                return rootTitle
            }
            if !fallbackTitle.isEmpty && fallbackTitle.lowercased() != authority && fallbackTitle.lowercased() != bareHost {
                return fallbackTitle
            }
            return ""
        }
    }

    private struct AggregatedFullLinkCandidate {
        var id: String
        var normalizedKey: String
        var url: String
        var title: String
        var rawHost: String
        var bareHost: String
        var isRootHostURL: Bool
        var iconName: String?
        var isFromHistory: Bool
        var isFromBookmark: Bool
        var visitCount: Int
        var latestTimestamp: TimeInterval

        var kind: OmniboxSuggestionKind {
            isFromBookmark ? .bookmark : .history
        }

        var source: OmniboxSuggestionSource {
            if isFromHistory && isFromBookmark { return .historyAndBookmark }
            if isFromBookmark { return .bookmark }
            return .history
        }
    }

    /// Generates ranked suggestions prioritizing matching Hosts from History & Bookmarks first,
    /// followed by matching Full Links from History & Bookmarks, and an optional search fallback.
    public static func suggestions(
        for query: String,
        history: [HistoryEntry],
        bookmarks: [BookmarkEntry],
        searchEngine: SearchEngine = .bing,
        includeSearchSuggestion: Bool = true,
        maxCount: Int = defaultMaxSuggestions
    ) -> [OmniboxSuggestion] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, maxCount > 0 else { return [] }

        let rawNeedle = trimmed.lowercased()
        let explicitScheme = extractExplicitScheme(from: trimmed)
        let hostNeedle = stripScheme(rawNeedle)
        let strippedWWW = stripWWW(hostNeedle)
        let bareNeedle = strippedWWW.isEmpty ? hostNeedle : strippedWWW
        let queryHasPath = hostNeedle.contains("/")

        guard !bareNeedle.isEmpty else { return [] }

        // 1. Aggregate unique hosts and unique full links from History + Bookmarks
        let (hostCandidates, fullLinkCandidates) = aggregateCandidates(history: history, bookmarks: bookmarks)

        // 2. Tier 1: Match & rank Host candidates (unless the user has already typed a '/' path separator)
        var matchedHosts: [(candidate: AggregatedHostCandidate, score: Int)] = []
        if !queryHasPath {
            for candidate in hostCandidates {
                if let score = scoreHostCandidate(
                    candidate,
                    rawNeedle: rawNeedle,
                    hostNeedle: hostNeedle,
                    bareNeedle: bareNeedle
                ) {
                    matchedHosts.append((candidate, score))
                }
            }

            matchedHosts.sort { lhs, rhs in
                if lhs.score != rhs.score {
                    return lhs.score > rhs.score
                }
                if lhs.candidate.bareHost.count != rhs.candidate.bareHost.count {
                    return lhs.candidate.bareHost.count < rhs.candidate.bareHost.count
                }
                if lhs.candidate.latestTimestamp != rhs.candidate.latestTimestamp {
                    return lhs.candidate.latestTimestamp > rhs.candidate.latestTimestamp
                }
                return lhs.candidate.bareHost < rhs.candidate.bareHost
            }
        }

        // 3. Tier 2: Match & rank Full Link candidates
        var matchedFullLinks: [(candidate: AggregatedFullLinkCandidate, score: Int)] = []
        for candidate in fullLinkCandidates {
            if let score = scoreFullLinkCandidate(
                candidate,
                rawNeedle: rawNeedle,
                hostNeedle: hostNeedle,
                bareNeedle: bareNeedle,
                queryHasPath: queryHasPath
            ) {
                matchedFullLinks.append((candidate, score))
            }
        }

        matchedFullLinks.sort { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }
            if lhs.candidate.latestTimestamp != rhs.candidate.latestTimestamp {
                return lhs.candidate.latestTimestamp > rhs.candidate.latestTimestamp
            }
            if lhs.candidate.url.count != rhs.candidate.url.count {
                return lhs.candidate.url.count < rhs.candidate.url.count
            }
            return lhs.candidate.url < rhs.candidate.url
        }

        // 4. Deduplicate bare root links that will already be represented by selected Tier 1 hosts,
        //    and allocate slots so Hosts strictly precede Full Links while leaving room for Full Links.
        let nonRootFullLinksCount = matchedFullLinks.filter { !$0.candidate.isRootHostURL }.count
        let hostQuota: Int
        if nonRootFullLinksCount == 0 {
            hostQuota = maxCount
        } else {
            let reservedForFullLinks = min(nonRootFullLinksCount, max(1, maxCount - maxHostReserveWhenFullLinksExist))
            hostQuota = max(1, maxCount - reservedForFullLinks)
        }

        let selectedHosts = Array(matchedHosts.prefix(hostQuota))
        var emittedCanonicalURLs = Set<String>()
        var emittedHosts = Set<String>()
        var results: [OmniboxSuggestion] = []

        for item in selectedHosts {
            let hostCandidate = item.candidate
            let canonical = LibraryPolicy.normalizeComparableURL(hostCandidate.canonicalURL)
            emittedCanonicalURLs.insert(canonical)
            emittedHosts.insert(hostCandidate.rawHost)
            emittedHosts.insert(hostCandidate.bareHost)

            let completionText = preferredHostCompletionText(
                for: hostCandidate,
                query: trimmed,
                explicitScheme: explicitScheme,
                hostNeedle: hostNeedle,
                bareNeedle: bareNeedle
            )

            results.append(
                OmniboxSuggestion(
                    id: "host-\(hostCandidate.authority)",
                    kind: .host,
                    source: hostCandidate.source,
                    title: hostCandidate.authority,
                    subtitle: hostCandidate.displaySubtitle,
                    url: hostCandidate.canonicalURL,
                    completionText: completionText,
                    host: hostCandidate.rawHost,
                    iconName: hostCandidate.iconName
                )
            )
        }

        // 5. Append Tier 2 Full Links (skipping bare root URLs whose host was already emitted in Tier 1)
        for item in matchedFullLinks where results.count < maxCount {
            let link = item.candidate
            if link.isRootHostURL && (emittedCanonicalURLs.contains(link.normalizedKey)
                || emittedHosts.contains(link.rawHost)
                || emittedHosts.contains(link.bareHost)) {
                continue
            }
            guard !emittedCanonicalURLs.contains(link.normalizedKey) else {
                continue
            }
            emittedCanonicalURLs.insert(link.normalizedKey)

            let completionText = preferredFullLinkCompletionText(
                for: link.url,
                query: trimmed,
                explicitScheme: explicitScheme,
                hostNeedle: hostNeedle,
                bareNeedle: bareNeedle
            )
            let displayTitle = !link.title.isEmpty ? link.title : link.url

            results.append(
                OmniboxSuggestion(
                    id: "link-\(link.id)",
                    kind: link.kind,
                    source: link.source,
                    title: displayTitle,
                    subtitle: link.url,
                    url: link.url,
                    completionText: completionText,
                    host: link.rawHost,
                    iconName: link.iconName
                )
            )
        }

        // 6. Optional Tier 3 Search fallback
        if includeSearchSuggestion,
           let searchURL = searchEngine.searchURL(for: trimmed)?.absoluteString {
            if results.count >= maxCount && !results.isEmpty {
                // Keep all URL suggestions if already full, or append search if space permits
            } else {
                results.append(
                    OmniboxSuggestion(
                        id: "search-\(rawNeedle)",
                        kind: .search,
                        source: .searchEngine,
                        title: trimmed,
                        subtitle: "使用 \(searchEngine.rawValue) 搜索",
                        url: searchURL,
                        completionText: trimmed,
                        host: ""
                    )
                )
            }
        }

        return results
    }

    /// Computes the inline autocomplete string for the current user input.
    ///
    /// - Prioritizes completing the top matching **Host** when the user has not typed a `/` path separator yet.
    /// - Completes the top matching **Full Link** when the user has typed `/` (e.g. `github.com/`) or when only full links match.
    /// - Returns the full string (preserving the user's exact typed prefix casing + completed suffix), or `nil` if no prefix completion applies.
    public static func inlineCompletion(
        for query: String,
        history: [HistoryEntry],
        bookmarks: [BookmarkEntry]
    ) -> String? {
        let candidates = suggestions(
            for: query,
            history: history,
            bookmarks: bookmarks,
            includeSearchSuggestion: false,
            maxCount: defaultMaxSuggestions
        )
        return inlineCompletion(for: query, suggestions: candidates)
    }

    /// Computes the inline autocomplete string from an existing ranked suggestion list.
    public static func inlineCompletion(
        for query: String,
        suggestions: [OmniboxSuggestion]
    ) -> String? {
        guard !query.isEmpty,
              query == query.trimmingCharacters(in: .whitespacesAndNewlines),
              !query.contains(" ") else {
            return nil
        }

        let lowerQuery = query.lowercased()
        let hostNeedle = stripScheme(lowerQuery)
        let queryHasPath = hostNeedle.contains("/")
        let hasHostCandidate = suggestions.contains { $0.kind == .host }

        for suggestion in suggestions where suggestion.kind != .search {
            if !queryHasPath && hasHostCandidate && suggestion.kind != .host {
                // When typing a host (before '/'), do not jump past a matched host to append a deep path.
                continue
            }

            let candidateForms = completionForms(for: suggestion)
            for form in candidateForms {
                let lowerForm = form.lowercased()
                if lowerForm.hasPrefix(lowerQuery) && form.count > query.count {
                    let suffixStart = form.index(form.startIndex, offsetBy: query.count)
                    return query + form[suffixStart...]
                }
            }

            if !queryHasPath && suggestion.kind == .host {
                // If the user has already typed the entire top host (e.g. "github.com"), stop here
                // so pressing Return navigates to the host rather than a random subpage.
                for form in candidateForms where form.lowercased() == lowerQuery {
                    return nil
                }
            }
        }

        return nil
    }

    // MARK: - Candidate Aggregation

    private static func aggregateCandidates(
        history: [HistoryEntry],
        bookmarks: [BookmarkEntry]
    ) -> (hosts: [AggregatedHostCandidate], fullLinks: [AggregatedFullLinkCandidate]) {
        var hostsByBareHost: [String: AggregatedHostCandidate] = [:]
        var linksByNormalizedURL: [String: AggregatedFullLinkCandidate] = [:]

        func ingest(
            id: String,
            rawURL: String,
            title: String,
            iconName: String?,
            isHistory: Bool,
            isBookmark: Bool,
            visitCount: Int,
            timestamp: TimeInterval
        ) {
            let trimmedURL = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedURL.isEmpty, !URLPolicy.isHomeURL(trimmedURL) else { return }

            let rawHost = URLPolicy.rawHost(trimmedURL)
            guard !rawHost.isEmpty else { return }

            let authority = extractAuthority(from: trimmedURL) ?? rawHost
            let bareHost = stripWWW(authority)
            let scheme = extractExplicitScheme(from: trimmedURL) ?? "https"
            let isRoot = isRootHostURL(trimmedURL)
            let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let meaningfulTitle = (cleanTitle.lowercased() != trimmedURL.lowercased()
                && cleanTitle.lowercased() != rawHost
                && cleanTitle.lowercased() != bareHost) ? cleanTitle : ""

            // Update or insert Host candidate
            if var existingHost = hostsByBareHost[bareHost] {
                // Prefer the shorter or root-bookmarked authority (e.g. keep www. if root bookmark uses it, or bare if visited)
                if isRoot && isBookmark {
                    existingHost.authority = authority
                    existingHost.rawHost = rawHost
                    existingHost.scheme = scheme
                }
                if isRoot && !meaningfulTitle.isEmpty && (existingHost.rootTitle.isEmpty || isBookmark) {
                    existingHost.rootTitle = meaningfulTitle
                } else if existingHost.fallbackTitle.isEmpty && !meaningfulTitle.isEmpty {
                    existingHost.fallbackTitle = meaningfulTitle
                }
                if isRoot, let iconName, !iconName.isEmpty, existingHost.iconName == nil {
                    existingHost.iconName = iconName
                }
                existingHost.isFromHistory = existingHost.isFromHistory || isHistory
                existingHost.isFromBookmark = existingHost.isFromBookmark || isBookmark
                existingHost.visitCount += visitCount
                existingHost.latestTimestamp = max(existingHost.latestTimestamp, timestamp)
                hostsByBareHost[bareHost] = existingHost
            } else {
                hostsByBareHost[bareHost] = AggregatedHostCandidate(
                    authority: authority,
                    rawHost: rawHost,
                    bareHost: bareHost,
                    scheme: scheme,
                    rootTitle: isRoot ? meaningfulTitle : "",
                    fallbackTitle: meaningfulTitle,
                    iconName: isRoot && !(iconName ?? "").isEmpty ? iconName : nil,
                    isFromHistory: isHistory,
                    isFromBookmark: isBookmark,
                    visitCount: visitCount,
                    latestTimestamp: timestamp
                )
            }

            // Update or insert Full Link candidate
            let normalizedKey = LibraryPolicy.normalizeComparableURL(trimmedURL)
            guard !normalizedKey.isEmpty else { return }

            if var existingLink = linksByNormalizedURL[normalizedKey] {
                if !meaningfulTitle.isEmpty && (existingLink.title.isEmpty || isBookmark) {
                    existingLink.title = meaningfulTitle
                }
                if let iconName, !iconName.isEmpty, existingLink.iconName == nil {
                    existingLink.iconName = iconName
                }
                existingLink.isFromHistory = existingLink.isFromHistory || isHistory
                existingLink.isFromBookmark = existingLink.isFromBookmark || isBookmark
                existingLink.visitCount += visitCount
                existingLink.latestTimestamp = max(existingLink.latestTimestamp, timestamp)
                linksByNormalizedURL[normalizedKey] = existingLink
            } else {
                linksByNormalizedURL[normalizedKey] = AggregatedFullLinkCandidate(
                    id: id,
                    normalizedKey: normalizedKey,
                    url: trimmedURL,
                    title: meaningfulTitle.isEmpty ? (isRoot ? authority : cleanTitle) : meaningfulTitle,
                    rawHost: rawHost,
                    bareHost: bareHost,
                    isRootHostURL: isRoot,
                    iconName: (iconName?.isEmpty == false) ? iconName : nil,
                    isFromHistory: isHistory,
                    isFromBookmark: isBookmark,
                    visitCount: visitCount,
                    latestTimestamp: timestamp
                )
            }
        }

        for entry in history {
            ingest(
                id: entry.id,
                rawURL: entry.url,
                title: entry.title,
                iconName: nil,
                isHistory: true,
                isBookmark: false,
                visitCount: max(1, entry.visitCount),
                timestamp: entry.visitedAt
            )
        }

        for bookmark in bookmarks {
            ingest(
                id: bookmark.id,
                rawURL: bookmark.url,
                title: bookmark.displayTitle,
                iconName: bookmark.iconName,
                isHistory: false,
                isBookmark: true,
                visitCount: 1,
                timestamp: bookmark.updatedAt
            )
        }

        return (Array(hostsByBareHost.values), Array(linksByNormalizedURL.values))
    }

    // MARK: - Scoring

    private static func scoreHostCandidate(
        _ candidate: AggregatedHostCandidate,
        rawNeedle: String,
        hostNeedle: String,
        bareNeedle: String
    ) -> Int? {
        let authority = candidate.authority.lowercased()
        let bareHost = candidate.bareHost.lowercased()

        var matchScore = 0
        if authority == hostNeedle {
            matchScore = 10_200
        } else if bareHost == bareNeedle {
            matchScore = 10_000
        } else if authority.hasPrefix(hostNeedle) {
            matchScore = 8_200
        } else if bareHost.hasPrefix(bareNeedle) {
            matchScore = 8_000
        } else if hasDotSegmentPrefix(bareHost, prefix: bareNeedle) {
            matchScore = 6_000
        } else if bareHost.contains(bareNeedle) || authority.contains(hostNeedle) {
            matchScore = 4_000
        } else if !candidate.rootTitle.isEmpty && candidate.rootTitle.lowercased().hasPrefix(rawNeedle) {
            matchScore = 3_200
        } else if !candidate.rootTitle.isEmpty && candidate.rootTitle.lowercased().contains(rawNeedle) {
            matchScore = 2_400
        } else {
            return nil
        }

        let historyBonus = candidate.isFromHistory ? (80 + min(candidate.visitCount * 15, 150)) : 0
        let bookmarkBonus = candidate.isFromBookmark ? 90 : 0
        return matchScore + historyBonus + bookmarkBonus
    }

    private static func scoreFullLinkCandidate(
        _ candidate: AggregatedFullLinkCandidate,
        rawNeedle: String,
        hostNeedle: String,
        bareNeedle: String,
        queryHasPath: Bool
    ) -> Int? {
        if queryHasPath && candidate.isRootHostURL {
            return nil
        }
        let lowerURL = candidate.url.lowercased()
        let noSchemeURL = stripScheme(lowerURL)
        let bareURL = stripWWW(noSchemeURL)
        let lowerTitle = candidate.title.lowercased()

        var matchScore = 0
        if bareURL == bareNeedle || noSchemeURL == hostNeedle || lowerURL == rawNeedle {
            matchScore = 9_000
        } else if bareURL.hasPrefix(bareNeedle) || noSchemeURL.hasPrefix(hostNeedle) || lowerURL.hasPrefix(rawNeedle) {
            matchScore = 7_500
        } else if !queryHasPath && (candidate.bareHost.hasPrefix(bareNeedle) || candidate.rawHost.hasPrefix(hostNeedle)) {
            matchScore = 6_200
        } else if !queryHasPath && hasDotSegmentPrefix(candidate.bareHost, prefix: bareNeedle) {
            matchScore = 5_200
        } else if bareURL.contains(bareNeedle) || noSchemeURL.contains(hostNeedle) {
            matchScore = 4_200
        } else if !lowerTitle.isEmpty && lowerTitle.hasPrefix(rawNeedle) {
            matchScore = 3_500
        } else if !lowerTitle.isEmpty && lowerTitle.contains(rawNeedle) {
            matchScore = 2_500
        } else {
            return nil
        }

        let historyBonus = candidate.isFromHistory ? (60 + min(candidate.visitCount * 12, 120)) : 0
        let bookmarkBonus = candidate.isFromBookmark ? 75 : 0
        return matchScore + historyBonus + bookmarkBonus
    }

    // MARK: - Formatting & URL Parsing Helpers

    private static func completionForms(for suggestion: OmniboxSuggestion) -> [String] {
        switch suggestion.kind {
        case .host:
            let authority = suggestion.title
            let bare = stripWWW(authority)
            let scheme = extractExplicitScheme(from: suggestion.url) ?? "https"
            var forms: [String] = []
            if bare != authority {
                forms.append(bare)
                forms.append(authority)
            } else {
                forms.append(authority)
                forms.append("www.\(bare)")
            }
            forms.append(suggestion.url)
            if bare != authority {
                forms.append("\(scheme)://\(bare)")
            } else {
                forms.append("\(scheme)://www.\(bare)")
            }
            return forms

        case .history, .bookmark:
            let noScheme = stripScheme(suggestion.url)
            let bare = stripWWW(noScheme)
            var forms: [String] = []
            if bare != noScheme {
                forms.append(bare)
                forms.append(noScheme)
            } else {
                forms.append(noScheme)
            }
            forms.append(suggestion.url)
            if bare != noScheme {
                let scheme = extractExplicitScheme(from: suggestion.url) ?? "https"
                forms.append("\(scheme)://\(bare)")
            }
            return forms

        case .search:
            return []
        }
    }

    private static func preferredHostCompletionText(
        for candidate: AggregatedHostCandidate,
        query: String,
        explicitScheme: String?,
        hostNeedle: String,
        bareNeedle: String
    ) -> String {
        if let explicitScheme {
            if hostNeedle.hasPrefix("www.") {
                return "\(explicitScheme)://\(candidate.authority)"
            }
            if candidate.bareHost.hasPrefix(bareNeedle) && !candidate.authority.hasPrefix(hostNeedle) {
                return "\(explicitScheme)://\(candidate.bareHost)"
            }
            return "\(explicitScheme)://\(candidate.authority)"
        }
        if hostNeedle.hasPrefix("www.") {
            return candidate.authority
        }
        if candidate.bareHost.hasPrefix(bareNeedle) && !candidate.authority.hasPrefix(hostNeedle) {
            return candidate.bareHost
        }
        return candidate.authority
    }

    private static func preferredFullLinkCompletionText(
        for url: String,
        query: String,
        explicitScheme: String?,
        hostNeedle: String,
        bareNeedle: String
    ) -> String {
        if explicitScheme != nil {
            return url
        }
        let noScheme = stripScheme(url)
        let bare = stripWWW(noScheme)
        if !hostNeedle.hasPrefix("www."), bare.lowercased().hasPrefix(bareNeedle), !noScheme.lowercased().hasPrefix(hostNeedle) {
            return bare
        }
        return noScheme
    }

    private static func hasDotSegmentPrefix(_ host: String, prefix: String) -> Bool {
        let segments = host.split(separator: ".")
        guard segments.count > 1 else { return false }
        for segment in segments.dropFirst() {
            if segment.lowercased().hasPrefix(prefix) {
                return true
            }
        }
        return false
    }

    /// Checks whether the URL points to the root of a host (no non-empty path, query, or fragment).
    public static func isRootHostURL(_ urlString: String) -> Bool {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed) else {
            let noScheme = stripScheme(trimmed)
            let strippedSlash = noScheme.hasSuffix("/") ? String(noScheme.dropLast()) : noScheme
            return !strippedSlash.contains("/") && !strippedSlash.contains("?") && !strippedSlash.contains("#")
        }
        let path = components.path
        let hasNonRootPath = !path.isEmpty && path != "/"
        let hasQuery = !(components.query ?? "").isEmpty
        let hasFragment = !(components.fragment ?? "").isEmpty
        return !hasNonRootPath && !hasQuery && !hasFragment
    }

    private static func extractExplicitScheme(from text: String) -> String? {
        let lower = text.lowercased()
        if lower.hasPrefix("https://") { return "https" }
        if lower.hasPrefix("http://") { return "http" }
        return nil
    }

    private static func extractAuthority(from urlString: String) -> String? {
        let noScheme = stripScheme(urlString)
        guard !noScheme.isEmpty else { return nil }
        let endIdx = noScheme.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) ?? noScheme.endIndex
        let authority = String(noScheme[..<endIdx]).lowercased()
        return authority.isEmpty ? nil : authority
    }

    public static func stripScheme(_ text: String) -> String {
        let lower = text.lowercased()
        if lower.hasPrefix("https://") {
            return String(text.dropFirst(8))
        }
        if lower.hasPrefix("http://") {
            return String(text.dropFirst(7))
        }
        return text
    }

    public static func stripWWW(_ text: String) -> String {
        if text.lowercased().hasPrefix("www.") {
            return String(text.dropFirst(4))
        }
        return text
    }
}
