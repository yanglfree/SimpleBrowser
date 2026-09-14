import XCTest
@testable import ZhuoBrowser

final class BookmarkTransferTests: XCTestCase {
    func testParsesNetscapeBookmarksWithTagsAndSafeSchemes() throws {
        let html = """
        <DL><p>
          <DT><A HREF="https://example.com?a=1&amp;b=2" TAGS="work, reference,work"><b>Example</b> &amp; Docs</A>
          <DT><A HREF="javascript:alert(1)">Unsafe</A>
          <DT><A HREF="https://example.com?a=1&amp;b=2">Duplicate</A>
        </DL><p>
        """

        let items = try BookmarkTransfer.parse(Data(html.utf8), now: 100)

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].url, "https://example.com?a=1&b=2")
        XCTAssertEqual(items[0].title, "Example & Docs")
        XCTAssertEqual(items[0].tags, ["work", "reference"])
        XCTAssertTrue(items[0].isRead)
    }

    func testExportEscapesValuesAndRoundTrips() throws {
        let source = SavedItem(
            id: "saved-1",
            title: "A < B & C",
            url: "https://example.com/?a=1&b=2",
            createdAt: 1,
            updatedAt: 2,
            tags: ["work", "docs"]
        )

        let html = BookmarkTransfer.export([source])
        let restored = try BookmarkTransfer.parse(Data(html.utf8), now: 10)

        XCTAssertTrue(html.contains("A &lt; B &amp; C"))
        XCTAssertEqual(restored.first?.title, source.title)
        XCTAssertEqual(restored.first?.url, source.url)
        XCTAssertEqual(restored.first?.tags, source.tags)
    }

    func testRejectsOversizedAndInvalidUTF8Files() {
        XCTAssertThrowsError(
            try BookmarkTransfer.parse(Data(count: BookmarkTransfer.maximumImportBytes + 1))
        )
        XCTAssertThrowsError(try BookmarkTransfer.parse(Data([0xFF, 0xFE])))
    }
}
