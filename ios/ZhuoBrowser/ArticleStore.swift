import Foundation

@MainActor
final class ArticleStore: ObservableObject {
    @Published private(set) var articles: [SavedArticle] = []
    @Published private(set) var capturingURLs: Set<String> = []

    var allTags: [String] { articles.allTags }
    var allTopics: [String] { articles.allTopics }

    private let rootDirectory: URL
    private let manifestURL: URL
    private let ephemeralSession: URLSession
    private var mutationTail: Task<Void, Never>?

    init(rootDirectory: URL? = nil, session: URLSession? = nil) {
        let base = rootDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Articles", isDirectory: true)
        self.rootDirectory = base
        self.manifestURL = base.appendingPathComponent("manifest.json")
        if let session {
            self.ephemeralSession = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.httpCookieAcceptPolicy = .never
            config.httpShouldSetCookies = false
            config.urlCredentialStorage = nil
            config.timeoutIntervalForRequest = 5.0
            config.timeoutIntervalForResource = 5.0
            config.httpAdditionalHeaders = ["Accept": "image/*"]
            self.ephemeralSession = URLSession(configuration: config)
        }
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

    func hasContent(for article: SavedArticle) -> Bool {
        htmlURL(for: article) != nil
    }

    func isReadable(_ article: SavedArticle) -> Bool {
        !article.isFailed && htmlURL(for: article) != nil
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

        return try await withMutation {
            let existing = self.articles.first { $0.canonicalUrl == key || $0.sourceUrl == snapshot.sourceUrl }
            let id = existing?.id ?? UUID().uuidString
            let directory = self.articleDirectory(id)
            let staging = self.rootDirectory.appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
            let stagingImages = staging.appendingPathComponent("images", isDirectory: true)
            try FileManager.default.createDirectory(at: stagingImages, withIntermediateDirectories: true)

            do {
                let imageResult = await self.downloadImages(snapshot.images, to: stagingImages)
                let html = Self.documentHTML(title: snapshot.title, author: snapshot.author, body: snapshot.html)
                try Data(html.utf8).write(to: staging.appendingPathComponent("article.html"), options: .atomic)
                try Data(snapshot.markdown.utf8).write(to: staging.appendingPathComponent("article.md"), options: .atomic)
                try Data(snapshot.text.utf8).write(to: staging.appendingPathComponent("article.txt"), options: .atomic)

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
                    failedImageCount: imageResult.failed,
                    failure: .none,
                    failureMessage: ""
                )

                let backup = self.rootDirectory.appendingPathComponent(".backup-\(UUID().uuidString)", isDirectory: true)
                let directoryExists = FileManager.default.fileExists(atPath: directory.path)
                if directoryExists {
                    try FileManager.default.moveItem(at: directory, to: backup)
                }

                do {
                    try FileManager.default.moveItem(at: staging, to: directory)
                } catch {
                    if directoryExists {
                        try? FileManager.default.moveItem(at: backup, to: directory)
                    }
                    throw error
                }

                let previousArticles = self.articles
                self.upsertInMemory(article)

                do {
                    try self.persistManifest()
                    if directoryExists {
                        try? FileManager.default.removeItem(at: backup)
                    }
                    return article
                } catch {
                    self.articles = previousArticles
                    try? FileManager.default.removeItem(at: directory)
                    if directoryExists {
                        try? FileManager.default.moveItem(at: backup, to: directory)
                    }
                    throw error
                }
            } catch {
                try? FileManager.default.removeItem(at: staging)
                throw error
            }
        }
    }

    @discardableResult
    func saveFailure(
        id: String? = nil,
        url: String,
        title: String? = nil,
        failure: ArticleSaveFailure,
        message: String
    ) async throws -> SavedArticle {
        try await withMutation {
            let key = url
            let existing = self.articles.first { $0.canonicalUrl == key || $0.sourceUrl == key || (id != nil && $0.id == id) }
            let recordID = existing?.id ?? id ?? UUID().uuidString
            let now = Date().timeIntervalSince1970
            let resolvedTitle: String
            if let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                resolvedTitle = title
            } else if let existingTitle = existing?.title, !existingTitle.isEmpty {
                resolvedTitle = existingTitle
            } else {
                resolvedTitle = URLPolicy.displayHost(url)
            }

            let article = SavedArticle(
                id: recordID,
                sourceUrl: existing?.sourceUrl ?? url,
                canonicalUrl: existing?.canonicalUrl ?? url,
                title: resolvedTitle,
                author: existing?.author ?? "",
                excerpt: existing?.excerpt ?? "",
                searchText: existing?.searchText ?? "",
                createdAt: existing?.createdAt ?? now,
                updatedAt: now,
                readingPosition: existing?.readingPosition ?? 0,
                tags: existing?.tags ?? [],
                topics: existing?.topics ?? [],
                notes: existing?.notes ?? [],
                highlights: existing?.highlights ?? [],
                archived: existing?.archived ?? false,
                quality: .failed,
                savedImageCount: 0,
                failedImageCount: 0,
                failure: failure,
                failureMessage: message
            )

            let previousArticles = self.articles
            self.upsertInMemory(article)
            do {
                try self.persistManifest()
                return article
            } catch {
                self.articles = previousArticles
                throw error
            }
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
        try? persistManifest()
    }

    func setArchived(_ id: String, archived: Bool) {
        mutate(id) { article in
            article.archived = archived
            article.updatedAt = Date().timeIntervalSince1970
        }
    }

    func remove(_ id: String) {
        Task { [weak self] in
            try? await self?.delete(id)
        }
    }

    func delete(_ id: String) async throws {
        try await withMutation {
            guard let index = self.articles.firstIndex(where: { $0.id == id }) else { return }
            let directory = self.articleDirectory(id)
            let trash = self.rootDirectory.appendingPathComponent(".trash-\(UUID().uuidString)", isDirectory: true)
            let dirExists = FileManager.default.fileExists(atPath: directory.path)
            if dirExists {
                try? FileManager.default.moveItem(at: directory, to: trash)
            }
            let previousArticles = self.articles
            self.articles.remove(at: index)
            do {
                try self.persistManifest()
                if dirExists {
                    try? FileManager.default.removeItem(at: trash)
                }
            } catch {
                self.articles = previousArticles
                if dirExists {
                    try? FileManager.default.moveItem(at: trash, to: directory)
                }
                throw error
            }
        }
    }

    private func withMutation<T>(_ operation: @escaping () async throws -> T) async throws -> T {
        let previous = mutationTail
        let currentTask = Task { () throws -> T in
            _ = await previous?.result
            return try await operation()
        }
        mutationTail = Task {
            _ = await currentTask.result
        }
        return try await currentTask.value
    }

    private func upsertInMemory(_ article: SavedArticle) {
        articles.removeAll { $0.id == article.id }
        articles.insert(article, at: 0)
    }

    private func mutate(_ id: String, body: (inout SavedArticle) -> Void) {
        guard let index = articles.firstIndex(where: { $0.id == id }) else { return }
        let previous = articles
        body(&articles[index])
        do {
            try persistManifest()
        } catch {
            articles = previous
        }
    }

    private func restore() {
        guard FileManager.default.fileExists(atPath: manifestURL.path),
              let data = try? Data(contentsOf: manifestURL),
              let decoded = try? JSONDecoder().decode([SavedArticle].self, from: data) else {
            return
        }
        articles = decoded
    }

    func persistManifest() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(articles)
        try data.write(to: manifestURL, options: .atomic)
    }

    nonisolated static func isPersistableArticleImage(_ asset: ArticleImageAsset) -> Bool {
        guard let url = URL(string: asset.url),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else {
            return false
        }
        let clean = asset.fileName.lowercased()
        let extensions = ["jpg", "jpeg", "png", "gif", "webp", "avif", "svg"]
        guard let ext = clean.components(separatedBy: ".").last,
              extensions.contains(ext) else {
            return false
        }
        return true
    }

    private func downloadImages(_ images: [ArticleImageAsset], to directory: URL) async -> (saved: Int, failed: Int) {
        var saved = 0
        var failed = 0
        var totalBytes = 0
        let startTime = Date()
        let deadline = startTime.addingTimeInterval(ArticlePolicy.imageTimeBudgetSeconds)

        for image in images.prefix(ArticlePolicy.maximumImages) {
            guard Self.isPersistableArticleImage(image) else {
                failed += 1
                continue
            }
            guard Date() < deadline, totalBytes < ArticlePolicy.maximumTotalImageBytes else {
                failed += 1
                continue
            }
            guard let url = URL(string: image.url) else {
                failed += 1
                continue
            }

            var request = URLRequest(url: url)
            let remaining = max(1.0, deadline.timeIntervalSinceNow)
            request.timeoutInterval = min(5.0, remaining)
            request.setValue("image/*", forHTTPHeaderField: "Accept")

            do {
                let (asyncBytes, response) = try await ephemeralSession.bytes(for: request)
                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode) else {
                    failed += 1
                    continue
                }

                if http.expectedContentLength > Int64(ArticlePolicy.maximumImageBytes) ||
                    (http.expectedContentLength > 0 && Int64(totalBytes) + http.expectedContentLength > Int64(ArticlePolicy.maximumTotalImageBytes)) {
                    failed += 1
                    continue
                }

                var data = Data()
                var exceeded = false

                for try await byte in asyncBytes {
                    if data.count >= ArticlePolicy.maximumImageBytes || totalBytes + data.count >= ArticlePolicy.maximumTotalImageBytes {
                        exceeded = true
                        break
                    }
                    data.append(byte)
                }

                guard !exceeded, !data.isEmpty else {
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
    case persistenceFailed(String)
    case transactionFailed

    var errorDescription: String? {
        switch self {
        case .captureInProgress:
            return "文章正在保存"
        case .persistenceFailed(let message):
            return "存储失败: \(message)"
        case .transactionFailed:
            return "文章存储事务失败"
        }
    }
}

enum ArticleExportFormat: String, CaseIterable, Identifiable {
    case markdown = "Markdown"
    case html = "HTML"

    var id: String { rawValue }
    var fileName: String { self == .markdown ? "article.md" : "article.html" }
    var fileExtension: String { self == .markdown ? "md" : "html" }
}
