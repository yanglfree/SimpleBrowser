import XCTest
@testable import ZhuoBrowser

final class QuickSiteSourcePolicyTests: XCTestCase {
    func testFavoritesPreserveOrderAndUseHostForUntitledEntries() {
        let savedItems = [
            SavedItem(
                id: "first",
                title: "Example",
                url: "https://example.com/article",
                createdAt: 1,
                updatedAt: 2
            ),
            SavedItem(
                id: "second",
                title: "",
                url: "https://www.swift.org/blog/",
                createdAt: 2,
                updatedAt: 3
            )
        ]

        let entries = QuickSiteSourcePolicy.entries(
            for: .favorites,
            savedItems: savedItems,
            history: []
        )

        XCTAssertEqual(entries.map(\.id), ["favorite-first", "favorite-second"])
        XCTAssertEqual(entries.map(\.displayTitle), ["Example", "swift.org"])
    }

    func testHistoryCandidatesAreBoundedToHarmonyLimit() {
        let history = (0..<35).map { index in
            HistoryEntry(
                id: "\(index)",
                title: "Page \(index)",
                url: "https://example.com/\(index)",
                visitedAt: Double(index),
                visitCount: 1
            )
        }

        let entries = QuickSiteSourcePolicy.entries(
            for: .history,
            savedItems: [],
            history: history
        )

        XCTAssertEqual(entries.count, 30)
        XCTAssertEqual(entries.first?.id, "history-0")
        XCTAssertEqual(entries.last?.id, "history-29")
        XCTAssertTrue(
            QuickSiteSourcePolicy.entries(for: .custom, savedItems: [], history: history).isEmpty
        )
    }
}
