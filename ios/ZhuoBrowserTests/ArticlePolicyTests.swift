import XCTest
@testable import ZhuoBrowser

final class ArticlePolicyTests: XCTestCase {
    func testBundledCaptureScriptIsAvailable() {
        let script = WebKernel.loadScript(named: "article-capture")

        XCTAssertNotNil(script)
        XCTAssertTrue(script?.contains("__zhuoReaderExtract") == true)
    }

    func testCaptureRequiresWebURLAndReadableBody() {
        XCTAssertTrue(ArticlePolicy.validate(snapshot(text: String(repeating: "body ", count: 12))))
        XCTAssertFalse(ArticlePolicy.validate(snapshot(url: "file:///tmp/article", text: String(repeating: "body ", count: 12))))
        XCTAssertFalse(ArticlePolicy.validate(snapshot(text: "too short")))
    }

    func testLegacyArticleDefaultsOptionalCollectionsAndQuality() throws {
        let data = #"{"id":"a","sourceUrl":"https://example.com","title":"Title","createdAt":1}"#.data(using: .utf8)!

        let article = try JSONDecoder().decode(SavedArticle.self, from: data)

        XCTAssertEqual(article.canonicalUrl, article.sourceUrl)
        XCTAssertEqual(article.quality, .complete)
        XCTAssertEqual(article.tags, [])
        XCTAssertEqual(article.notes, [])
        XCTAssertEqual(article.highlights, [])
    }

    func testSearchIncludesBodyNotesLabelsAndArchiveScope() {
        var article = savedArticle(searchText: "offline body")
        article.notes = [ArticleNote(id: "n", text: "private memo", createdAt: 1, updatedAt: 1)]
        article.tags = ["Research"]
        article.topics = ["Swift"]

        XCTAssertEqual(ArticlePolicy.filtered([article], query: "offline", archived: false).map(\.id), [article.id])
        XCTAssertEqual(ArticlePolicy.filtered([article], query: "memo", archived: false).map(\.id), [article.id])
        XCTAssertEqual(ArticlePolicy.filtered([article], query: "swift", archived: false).map(\.id), [article.id])
        XCTAssertTrue(ArticlePolicy.filtered([article], query: "offline", archived: true).isEmpty)
    }

    func testLabelsTrimDeduplicateAndBoundLength() {
        let labels = ArticlePolicy.normalizedLabels([" Swift ", "swift", "", String(repeating: "a", count: 60)])

        XCTAssertEqual(labels.count, 2)
        XCTAssertEqual(labels[0], "Swift")
        XCTAssertEqual(labels[1].count, 40)
    }

    func testHighlightRelocationUsesSurroundingContext() {
        let text = "First shared quote ending. Second shared quote target."
        let highlight = ArticleHighlight(
            id: "h",
            quote: "shared quote",
            prefix: "Second ",
            suffix: " target",
            createdAt: 1
        )

        let range = ArticlePolicy.relocatedRange(for: highlight, in: text)

        XCTAssertEqual(range.map { String(text[$0]) }, "shared quote")
        XCTAssertEqual(range.map { String(text[..<$0.lowerBound]) }, "First shared quote ending. Second ")
    }

    @MainActor
    func testStorePersistsContentAndCreatesPortableExport() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("article-store-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ArticleStore(rootDirectory: root)

        let article = try await store.save(snapshot(text: String(repeating: "portable body ", count: 8)))
        let restored = ArticleStore(rootDirectory: root)
        let export = try restored.exportURL(for: article, format: .markdown)

        XCTAssertEqual(restored.articles.map(\.id), [article.id])
        XCTAssertNotNil(restored.htmlURL(for: article))
        XCTAssertTrue(try String(contentsOf: export, encoding: .utf8).contains("portable body"))
    }

    @MainActor
    func testSaveFailurePersistsDurableRecordAndRestoresWithoutHtml() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("article-store-failure-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ArticleStore(rootDirectory: root)

        let failedArticle = try await store.saveFailure(
            url: "https://example.com/stalled-article",
            title: "Stalled Page",
            failure: .stalled,
            message: "Extraction timed out after 8s"
        )

        XCTAssertEqual(failedArticle.quality, .failed)
        XCTAssertEqual(failedArticle.failure, .stalled)
        XCTAssertEqual(failedArticle.failureMessage, "Extraction timed out after 8s")
        XCTAssertNil(store.htmlURL(for: failedArticle))

        // Verify restore keeps this record even though article.html is absent!
        let restored = ArticleStore(rootDirectory: root)
        XCTAssertEqual(restored.articles.count, 1)
        XCTAssertEqual(restored.articles.first?.id, failedArticle.id)
        XCTAssertEqual(restored.articles.first?.failure, .stalled)
        XCTAssertTrue(restored.articles.first?.isFailed == true)
    }

    @MainActor
    func testRestorePreservesArticlesWhenHtmlIsMissing() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("article-store-missing-html-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ArticleStore(rootDirectory: root)

        let article = try await store.save(snapshot(text: String(repeating: "resilient body ", count: 8)))
        XCTAssertEqual(store.articles.count, 1)

        // Remove the article.html file on disk to simulate external deletion or corruption
        let htmlPath = store.articleDirectory(article.id).appendingPathComponent("article.html")
        try FileManager.default.removeItem(at: htmlPath)

        // Previous flawed implementation dropped the article; the new implementation must preserve it!
        let restored = ArticleStore(rootDirectory: root)
        XCTAssertEqual(restored.articles.count, 1)
        XCTAssertEqual(restored.articles.first?.id, article.id)
        XCTAssertFalse(restored.hasContent(for: article))
    }

    func testImageSafetyAndBudgetValidation() {
        let validAsset = ArticleImageAsset(index: 0, url: "https://example.com/photo.png", fileName: "image-0.png")
        let invalidScheme = ArticleImageAsset(index: 1, url: "file:///local/photo.jpg", fileName: "image-1.jpg")
        let invalidExtension = ArticleImageAsset(index: 2, url: "https://example.com/script.js", fileName: "image-2.js")
        let unsafeName = ArticleImageAsset(index: 3, url: "https://example.com/photo.png", fileName: "image-3.exe")

        XCTAssertTrue(ArticleStore.isPersistableArticleImage(validAsset))
        XCTAssertFalse(ArticleStore.isPersistableArticleImage(invalidScheme))
        XCTAssertFalse(ArticleStore.isPersistableArticleImage(invalidExtension))
        XCTAssertFalse(ArticleStore.isPersistableArticleImage(unsafeName))
        XCTAssertEqual(ArticlePolicy.maximumImages, 30)
        XCTAssertEqual(ArticlePolicy.maximumImageBytes, 5 * 1024 * 1024)
        XCTAssertEqual(ArticlePolicy.maximumTotalImageBytes, 20 * 1024 * 1024)
        XCTAssertEqual(ArticlePolicy.imageTimeBudgetSeconds, 15.0)
    }

    private func snapshot(url: String = "https://example.com/article", text: String) -> ArticleCaptureSnapshot {
        ArticleCaptureSnapshot(
            title: "Title",
            author: "Author",
            canonicalUrl: url,
            sourceUrl: url,
            html: "<article><p>\(text)</p></article>",
            text: text,
            markdown: text,
            images: [],
            readerMetrics: ArticleReaderMetrics(
                result: "complete",
                strategy: "article",
                candidateChars: text.count,
                outputChars: text.count,
                retainedRatio: 1,
                paragraphCount: 1,
                imageCount: 0,
                durationMs: 1
            )
        )
    }

    private func savedArticle(searchText: String) -> SavedArticle {
        SavedArticle(
            id: "article-1",
            sourceUrl: "https://example.com",
            canonicalUrl: "https://example.com",
            title: "Example",
            author: "Author",
            excerpt: "Excerpt",
            searchText: searchText,
            createdAt: 1,
            updatedAt: 2,
            quality: .complete
        )
    }

    func testMultiDimensionalFilteringByScopeTagAndTopic() {
        var a1 = savedArticle(searchText: "article one")
        a1.id = "a1"
        a1.tags = ["Tech", "News"]
        a1.topics = ["Apple"]
        a1.archived = false

        var a2 = savedArticle(searchText: "article two")
        a2.id = "a2"
        a2.tags = ["News"]
        a2.topics = ["OpenAI"]
        a2.archived = true

        var a3 = savedArticle(searchText: "failed article")
        a3.id = "a3"
        a3.quality = .failed
        a3.failure = .stalled
        a3.failureMessage = "Timeout"

        let list = [a1, a2, a3]

        // Scopes
        XCTAssertEqual(ArticlePolicy.filtered(list, query: "", scope: .all).map(\.id), ["a1", "a2", "a3"])
        XCTAssertEqual(ArticlePolicy.filtered(list, query: "", scope: .active).map(\.id), ["a1"])
        XCTAssertEqual(ArticlePolicy.filtered(list, query: "", scope: .archived).map(\.id), ["a2"])
        XCTAssertEqual(ArticlePolicy.filtered(list, query: "", scope: .failed).map(\.id), ["a3"])

        // Tag filter
        XCTAssertEqual(ArticlePolicy.filtered(list, query: "", scope: .all, tag: "Tech").map(\.id), ["a1"])
        XCTAssertEqual(ArticlePolicy.filtered(list, query: "", scope: .all, tag: "News").map(\.id), ["a1", "a2"])
        XCTAssertEqual(ArticlePolicy.filtered(list, query: "", scope: .active, tag: "News").map(\.id), ["a1"])

        // Topic filter
        XCTAssertEqual(ArticlePolicy.filtered(list, query: "", scope: .all, topic: "Apple").map(\.id), ["a1"])
        XCTAssertEqual(ArticlePolicy.filtered(list, query: "", scope: .all, topic: "OpenAI").map(\.id), ["a2"])
        XCTAssertTrue(ArticlePolicy.filtered(list, query: "", scope: .active, topic: "OpenAI").isEmpty)
    }

    func testAllTagsAndTopicsExtraction() {
        var a1 = savedArticle(searchText: "one")
        a1.id = "a1"
        a1.tags = ["Zebra", "Apple"]
        a1.topics = ["Science"]

        var a2 = savedArticle(searchText: "two")
        a2.id = "a2"
        a2.tags = ["Apple", "Banana"]
        a2.topics = ["Art", "Science"]

        let articles = [a1, a2]
        XCTAssertEqual(articles.allTags, ["Apple", "Banana", "Zebra"])
        XCTAssertEqual(articles.allTopics, ["Art", "Science"])
    }

    func testCaptureErrorFailureKindAndDisplayNames() {
        XCTAssertEqual(ArticleCaptureError.scriptMissing.failureKind, .extractionUnavailable)
        XCTAssertEqual(ArticleCaptureError.extractionFailed.failureKind, .extractionUnavailable)
        XCTAssertEqual(ArticleCaptureError.unreadable.failureKind, .captureInvalid)
        XCTAssertEqual(ArticleCaptureError.timedOut.failureKind, .stalled)

        for failure in ArticleSaveFailure.allCases {
            XCTAssertFalse(failure.displayName.isEmpty)
        }
    }
}
