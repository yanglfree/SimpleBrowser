import Foundation

@MainActor
final class ArticleStore: ObservableObject {
    @Published private(set) var articles: [SavedArticle] = []
    @Published private(set) var capturingURLs: Set<String> = []

    private let rootDirectory: URL
    private let manifestURL: URL
    private let session: URLSession

    init(rootDirectory: URL? = nil, session: URLSession = .shared) {
        let base = rootDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Articles", isDirectory: true)
        self.rootDirectory = base
        self.manifestURL = base.appendingPathComponent("manifest.json")
        self.session = session
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        restore()
    }

    func articleDirectory(_ id: String) -> URL {
        let component = safeID(id)
        return rootDirectory.appendingPathComponent(component.isEmpty ? "_invalid" : component, isDirectory: true)
    }

    func htmlURL(for article: SavedArticle) -> URL? {
        let url = articleDirectory(article.id).appendingPathComponent("article.html")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func exportURL(for article: SavedArticle, format: ArticleExportFormat) throws -> URL {
        let source = articleDirectory(article.id).appendingPathComponent(format.fileName)
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let title = sanitizedFileName(article.title.isEmpty ? "Article" : article.title)
        let finalURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(title).\(format.fileExtension)")
        try? FileManager.default.removeItem(at: finalURL)
        var content = try String(contentsOf: source, encoding: .utf8)
        let imagesDirectory = articleDirectory(article.id).appendingPathComponent("images", isDirectory: true)
        let images = (try? FileManager.default.contentsOfDirectory(at: imagesDirectory, includingPropertiesForKeys: nil)) ?? []
        for image in images {
            guard let data = try? Data(contentsOf: image), data.count <= ArticlePolicy.maximumImageBytes else { continue }
            let encoded = "data:\(mimeType(for: image.pathExtension));base64,\(data.base64EncodedString())"
            content = content.replacingOccurrences(of: "images/\(image.lastPathComponent)", with: encoded)
        }
        try Data(content.utf8).write(to: finalURL, options: .atomic)
        return finalURL
    }

    @discardableResult
    func save(_ snapshot: ArticleCaptureSnapshot) async throws -> SavedArticle {
        let key = snapshot.canonicalUrl.isEmpty ? snapshot.sourceUrl : snapshot.canonicalUrl
        guard !capturingURLs.contains(key), !capturingURLs.contains(snapshot.sourceUrl) else {
            throw ArticleStoreError.captureInProgress
        }
        capturingURLs.insert(key)
        capturingURLs.insert(snapshot.sourceUrl)
        defer {
            capturingURLs.remove(key)
            capturingURLs.remove(snapshot.sourceUrl)
        }

        let existing = articles.first { $0.canonicalUrl == key || $0.sourceUrl == snapshot.sourceUrl }
        let id = existing?.id ?? UUID().uuidString
        let directory = articleDirectory(id)
        let staging = rootDirectory.appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging.appendingPathComponent("images", isDirectory: true), withIntermediateDirectories: true)
        do {
            let imageResult = await downloadImages(snapshot.images, to: staging.appendingPathComponent("images", isDirectory: true))
            let html = Self.documentHTML(title: snapshot.title, author: snapshot.author, body: snapshot.html)
            try Data(html.utf8).write(to: staging.appendingPathComponent("article.html"), options: .atomic)
            try Data(snapshot.markdown.utf8).write(to: staging.appendingPathComponent("article.md"), options: .atomic)
            try Data(snapshot.text.utf8).write(to: staging.appendingPathComponent("article.txt"), options: .atomic)

            try replaceDirectory(directory, with: staging)
            let now = Date().timeIntervalSince1970
            let quality: ArticleQuality = imageResult.failed == 0 && snapshot.readerMetrics.result == "complete" ? .complete : .partial
            let article = SavedArticle(
                id: id,
                sourceUrl: snapshot.sourceUrl,
                canonicalUrl: key,
                title: snapshot.title.trimmingCharacters(in: .whitespacesAndNewlines),
                author: snapshot.author.trimmingCharacters(in: .whitespacesAndNewlines),
                excerpt: String(snapshot.text.prefix(220)),
                searchText: snapshot.text,
                createdAt: existing?.createdAt ?? now,
                updatedAt: now,
                readingPosition: existing?.readingPosition ?? 0,
                tags: existing?.tags ?? [],
                topics: existing?.topics ?? [],
                notes: existing?.notes ?? [],
                highlights: existing?.highlights ?? [],
                archived: existing?.archived ?? false,
                quality: quality,
                savedImageCount: imageResult.saved,
                failedImageCount: imageResult.failed
            )
            upsert(article)
            return article
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
    }

    func updateMetadata(_ id: String, tags: [String], topics: [String], note: String) {
        mutate(id) { article in
            article.tags = ArticlePolicy.normalizedLabels(tags)
            article.topics = ArticlePolicy.normalizedLabels(topics)
            let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
            let now = Date().timeIntervalSince1970
            if trimmed.isEmpty {
                article.notes = []
            } else if article.notes.isEmpty {
                article.notes = [ArticleNote(id: UUID().uuidString, text: trimmed, createdAt: now, updatedAt: now)]
            } else {
                article.notes[0].text = trimmed
                article.notes[0].updatedAt = now
            }
            article.updatedAt = now
        }
    }

    func addHighlight(_ id: String, selection: ArticleHighlightSelection) {
        let quote = selection.quote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !quote.isEmpty else { return }
        mutate(id) { article in
            guard !article.highlights.contains(where: { $0.quote == quote && $0.prefix == selection.prefix }) else { return }
            article.highlights.append(ArticleHighlight(
                id: UUID().uuidString,
                quote: String(quote.prefix(500)),
                prefix: String(selection.prefix.suffix(80)),
                suffix: String(selection.suffix.prefix(80)),
                createdAt: Date().timeIntervalSince1970
            ))
            article.updatedAt = Date().timeIntervalSince1970
        }
    }

    func removeHighlight(_ articleID: String, highlightID: String) {
        mutate(articleID) { article in
            article.highlights.removeAll { $0.id == highlightID }
            article.updatedAt = Date().timeIntervalSince1970
        }
    }

    func updateReadingPosition(_ id: String, position: Double) {
        guard let index = articles.firstIndex(where: { $0.id == id }) else { return }
        let clamped = min(max(position, 0), 1)
        guard abs(articles[index].readingPosition - clamped) >= 0.01 else { return }
        articles[index].readingPosition = clamped
        persist()
    }

    func setArchived(_ id: String, archived: Bool) {
        mutate(id) { article in
            article.archived = archived
            article.updatedAt = Date().timeIntervalSince1970
        }
    }

    func remove(_ id: String) {
        articles.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: articleDirectory(id))
        persist()
    }

    private func upsert(_ article: SavedArticle) {
        articles.removeAll { $0.id == article.id }
        articles.insert(article, at: 0)
        persist()
    }

    private func mutate(_ id: String, body: (inout SavedArticle) -> Void) {
        guard let index = articles.firstIndex(where: { $0.id == id }) else { return }
        body(&articles[index])
        persist()
    }

    private func restore() {
        guard let data = try? Data(contentsOf: manifestURL),
              let decoded = try? JSONDecoder().decode([SavedArticle].self, from: data) else {
            return
        }
        articles = decoded.filter { htmlURL(for: $0) != nil }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(articles) else { return }
        try? data.write(to: manifestURL, options: .atomic)
    }

    private func downloadImages(_ images: [ArticleImageAsset], to directory: URL) async -> (saved: Int, failed: Int) {
        var saved = 0
        var failed = 0
        var totalBytes = 0
        for image in images.prefix(ArticlePolicy.maximumImages) {
            guard let url = URL(string: image.url), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
                failed += 1
                continue
            }
            do {
                let (data, response) = try await session.data(from: url)
                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode),
                      data.count <= ArticlePolicy.maximumImageBytes,
                      totalBytes + data.count <= ArticlePolicy.maximumTotalImageBytes else {
                    failed += 1
                    continue
                }
                let target = directory.appendingPathComponent(sanitizedFileName(image.fileName))
                try data.write(to: target, options: .atomic)
                totalBytes += data.count
                saved += 1
            } catch {
                failed += 1
            }
        }
        failed += max(0, images.count - ArticlePolicy.maximumImages)
        return (saved, failed)
    }

    private func safeID(_ id: String) -> String {
        id.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }

    private func sanitizedFileName(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:\0")
        let clean = value.components(separatedBy: invalid).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String((clean.isEmpty ? "Article" : clean).prefix(100))
    }

    private func replaceDirectory(_ directory: URL, with staging: URL) throws {
        guard FileManager.default.fileExists(atPath: directory.path) else {
            try FileManager.default.moveItem(at: staging, to: directory)
            return
        }
        let backup = rootDirectory.appendingPathComponent(".backup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.moveItem(at: directory, to: backup)
        do {
            try FileManager.default.moveItem(at: staging, to: directory)
            try? FileManager.default.removeItem(at: backup)
        } catch {
            try? FileManager.default.moveItem(at: backup, to: directory)
            throw error
        }
    }

    private func mimeType(for pathExtension: String) -> String {
        switch pathExtension.lowercased() {
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "svg": return "image/svg+xml"
        case "avif": return "image/avif"
        default: return "image/jpeg"
        }
    }

    private static func documentHTML(title: String, author: String, body: String) -> String {
        let escapedTitle = escapeHTML(title)
        let escapedAuthor = escapeHTML(author)
        let bodyContainsHeading = body.range(of: #"<h1(?:\s|>)"#, options: [.regularExpression, .caseInsensitive]) != nil
        let heading = bodyContainsHeading ? "" : "<h1>\(escapedTitle)</h1>"
        let byline = escapedAuthor.isEmpty || bodyContainsHeading ? "" : "<p class=\"byline\">\(escapedAuthor)</p>"
        return """
        <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src file: data:; style-src 'unsafe-inline'">
        <style>:root{color-scheme:light dark}body{max-width:760px;margin:0 auto;padding:28px 22px 80px;font:18px/1.75 -apple-system,BlinkMacSystemFont,sans-serif;color:#242522;background:#faf9f7}h1{font-size:2em;line-height:1.2}.byline{color:#777;font-size:.85em}img{max-width:100%;height:auto;border-radius:10px}pre{overflow:auto;padding:12px;background:#eee}mark[data-zhuo]{background:#ffe783}@media(prefers-color-scheme:dark){body{color:#eee;background:#171816}pre{background:#292b27}mark[data-zhuo]{color:#222}}</style>
        </head><body>\(heading)\(byline)<main>\(body)</main></body></html>
        """
    }

    private static func escapeHTML(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

enum ArticleStoreError: LocalizedError {
    case captureInProgress

    var errorDescription: String? { "文章正在保存" }
}

enum ArticleExportFormat: String, CaseIterable, Identifiable {
    case markdown = "Markdown"
    case html = "HTML"

    var id: String { rawValue }
    var fileName: String { self == .markdown ? "article.md" : "article.html" }
    var fileExtension: String { self == .markdown ? "md" : "html" }
}
