import XCTest
@testable import ZhuoBrowser

final class QuickSitePolicyTests: XCTestCase {
    func testNormalizesValidSiteAndRejectsDuplicateHost() {
        let first = QuickSitePolicy.normalized(title: "Example", url: "example.com", in: [])
        XCTAssertEqual(first?.url, "https://example.com")
        XCTAssertEqual(first?.badge, "E")

        let duplicate = QuickSitePolicy.normalized(title: "Again", url: "https://example.com/path", in: [first!])
        XCTAssertNil(duplicate)
    }

    func testRejectsSearchPhraseAndEmptyTitle() {
        XCTAssertNil(QuickSitePolicy.normalized(title: "Search", url: "two words", in: []))
        XCTAssertNil(QuickSitePolicy.normalized(title: "  ", url: "example.com", in: []))
    }

    func testMovePreservesAllSitesInExpectedOrder() {
        let sites = Array(QuickSite.defaults.prefix(4))
        let moved = QuickSitePolicy.move(sites, from: IndexSet(integer: 0), to: 3)

        XCTAssertEqual(moved.map(\.id), [sites[1].id, sites[2].id, sites[0].id, sites[3].id])
    }

    func testNewSiteIsVisibleWithinDefaultHomeLimit() {
        let site = QuickSite(id: "new", title: "New", url: "https://new.example", badge: "N", colorIndex: 0)
        let updated = QuickSitePolicy.upsert(QuickSite.defaults, site: site)

        XCTAssertEqual(updated.first?.id, "new")
        XCTAssertTrue(updated.prefix(6).contains(where: { $0.id == "new" }))
    }
}
