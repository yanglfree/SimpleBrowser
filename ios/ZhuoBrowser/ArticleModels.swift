import Foundation

struct ArticleImageAsset: Codable, Equatable {
    var index: Int
    var url: String
    var fileName: String
}

struct ArticleReaderMetrics: Codable, Equatable {
    var result: String
    var strategy: String
    var candidateChars: Int
    var outputChars: Int
    var retainedRatio: Double
    var paragraphCount: Int
    var imageCount: Int
    var durationMs: Int
}

struct ArticleCaptureSnapshot: Codable, Equatable {
    var title: String
    var author: String
    var canonicalUrl: String
    var sourceUrl: String
    var html: String
    var text: String
    var markdown: String
    var images: [ArticleImageAsset]
    var readerMetrics: ArticleReaderMetrics
}

enum ArticleQuality: String, Codable, CaseIterable {
    case complete
    case partial
    case failed
}

struct ArticleNote: Identifiable, Codable, Equatable {
    var id: String
    var text: String
    var createdAt: TimeInterval
    var updatedAt: TimeInterval
}

struct ArticleHighlight: Identifiable, Codable, Equatable {
    var id: String
    var quote: String
    var prefix: String
    var suffix: String
    var createdAt: TimeInterval
}

struct SavedArticle: Identifiable, Codable, Equatable {
    var id: String
    var sourceUrl: String
    var canonicalUrl: String
    var title: String
    var author: String
    var excerpt: String
    var searchText: String
    var createdAt: TimeInterval
    var updatedAt: TimeInterval
    var readingPosition: Double
    var tags: [String]
    var topics: [String]
    var notes: [ArticleNote]
    var highlights: [ArticleHighlight]
    var archived: Bool
    var quality: ArticleQuality
    var savedImageCount: Int
    var failedImageCount: Int

    enum CodingKeys: String, CodingKey {
        case id, sourceUrl, canonicalUrl, title, author, excerpt, searchText
        case createdAt, updatedAt, readingPosition, tags, topics, notes, highlights
        case archived, quality, savedImageCount, failedImageCount
    }

    init(
        id: String,
        sourceUrl: String,
        canonicalUrl: String,
        title: String,
        author: String,
        excerpt: String,
        searchText: String,
        createdAt: TimeInterval,
        updatedAt: TimeInterval,
        readingPosition: Double = 0,
        tags: [String] = [],
        topics: [String] = [],
        notes: [ArticleNote] = [],
        highlights: [ArticleHighlight] = [],
        archived: Bool = false,
        quality: ArticleQuality,
        savedImageCount: Int = 0,
        failedImageCount: Int = 0
    ) {
        self.id = id
        self.sourceUrl = sourceUrl
        self.canonicalUrl = canonicalUrl
        self.title = title
        self.author = author
        self.excerpt = excerpt
        self.searchText = searchText
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.readingPosition = readingPosition
        self.tags = tags
        self.topics = topics
        self.notes = notes
        self.highlights = highlights
        self.archived = archived
        self.quality = quality
        self.savedImageCount = savedImageCount
        self.failedImageCount = failedImageCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        sourceUrl = try container.decode(String.self, forKey: .sourceUrl)
        canonicalUrl = try container.decodeIfPresent(String.self, forKey: .canonicalUrl) ?? sourceUrl
        title = try container.decode(String.self, forKey: .title)
        author = try container.decodeIfPresent(String.self, forKey: .author) ?? ""
        excerpt = try container.decodeIfPresent(String.self, forKey: .excerpt) ?? ""
        searchText = try container.decodeIfPresent(String.self, forKey: .searchText) ?? excerpt
        createdAt = try container.decode(TimeInterval.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(TimeInterval.self, forKey: .updatedAt) ?? createdAt
        readingPosition = try container.decodeIfPresent(Double.self, forKey: .readingPosition) ?? 0
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        topics = try container.decodeIfPresent([String].self, forKey: .topics) ?? []
        notes = try container.decodeIfPresent([ArticleNote].self, forKey: .notes) ?? []
        highlights = try container.decodeIfPresent([ArticleHighlight].self, forKey: .highlights) ?? []
        archived = try container.decodeIfPresent(Bool.self, forKey: .archived) ?? false
        quality = try container.decodeIfPresent(ArticleQuality.self, forKey: .quality) ?? .complete
        savedImageCount = try container.decodeIfPresent(Int.self, forKey: .savedImageCount) ?? 0
        failedImageCount = try container.decodeIfPresent(Int.self, forKey: .failedImageCount) ?? 0
    }
}

struct ArticleHighlightSelection: Equatable {
    var quote: String
    var prefix: String
    var suffix: String
}

enum ArticlePolicy {
    static let maximumImages = 30
    static let maximumImageBytes = 5 * 1_024 * 1_024
    static let maximumTotalImageBytes = 20 * 1_024 * 1_024

    static func validate(_ snapshot: ArticleCaptureSnapshot) -> Bool {
        guard let url = URL(string: snapshot.sourceUrl),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            return false
        }
        return snapshot.text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 40
            && !snapshot.html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func normalizedLabels(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.compactMap { value in
            let label = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty else { return nil }
            let key = label.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            guard seen.insert(key).inserted else { return nil }
            return String(label.prefix(40))
        }
        .prefix(20)
        .map { $0 }
    }

    static func filtered(_ articles: [SavedArticle], query: String, archived: Bool) -> [SavedArticle] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return articles.filter { article in
            guard article.archived == archived else { return false }
            guard !needle.isEmpty else { return true }
            let haystack = ([article.title, article.author, article.sourceUrl, article.searchText]
                + article.tags + article.topics + article.notes.map(\.text) + article.highlights.map(\.quote))
                .joined(separator: "\n")
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            return haystack.contains(needle)
        }
        .sorted { $0.updatedAt > $1.updatedAt }
    }

    static func relocatedRange(for highlight: ArticleHighlight, in text: String) -> Range<String.Index>? {
        let matches = text.ranges(of: highlight.quote)
        guard !matches.isEmpty else { return nil }
        return matches.max { left, right in
            contextScore(left, highlight: highlight, text: text) < contextScore(right, highlight: highlight, text: text)
        }
    }

    private static func contextScore(_ range: Range<String.Index>, highlight: ArticleHighlight, text: String) -> Int {
        let before = String(text[..<range.lowerBound].suffix(highlight.prefix.count))
        let after = String(text[range.upperBound...].prefix(highlight.suffix.count))
        return commonSuffix(before, highlight.prefix) + commonPrefix(after, highlight.suffix)
    }

    private static func commonPrefix(_ lhs: String, _ rhs: String) -> Int {
        zip(lhs, rhs).prefix { $0 == $1 }.count
    }

    private static func commonSuffix(_ lhs: String, _ rhs: String) -> Int {
        commonPrefix(String(lhs.reversed()), String(rhs.reversed()))
    }
}

private extension String {
    func ranges(of value: String) -> [Range<String.Index>] {
        guard !value.isEmpty else { return [] }
        var result: [Range<String.Index>] = []
        var start = startIndex
        while start < endIndex, let range = range(of: value, range: start..<endIndex) {
            result.append(range)
            start = range.upperBound
        }
        return result
    }
}
