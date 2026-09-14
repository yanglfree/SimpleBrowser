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
}
