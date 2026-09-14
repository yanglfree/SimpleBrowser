import XCTest
@testable import ZhuoBrowser

final class SiteIconPolicyTests: XCTestCase {
    func testTargetsSkipPrivateAndHomeThenDeduplicateHosts() {
        let targets = SiteIconPolicy.targets([
            SiteIconRequest(url: URLPolicy.homeURL, isPrivate: false),
            SiteIconRequest(url: "https://example.com/one", isPrivate: true),
            SiteIconRequest(url: "https://example.com/one", isPrivate: false),
            SiteIconRequest(url: "https://example.com/two", isPrivate: false),
            SiteIconRequest(url: "https://swift.org", isPrivate: false),
        ])

        XCTAssertEqual(targets.map(\.url), ["https://example.com/one", "https://swift.org"])
        XCTAssertTrue(targets.allSatisfy { !$0.isPrivate })
    }

    func testCandidatesPreferLargestMetadataArtworkThenDeclaredAndFallbacks() {
        let html = """
            <link rel="icon" sizes="32x32" href="/small.png">
            <link rel="apple-touch-icon" sizes="180x180" href="assets/touch.png">
            """
        let candidates = SiteIconPolicy.candidates(
            pageURL: "https://example.com/news/story",
            declaredURL: "//cdn.example.com/page.png",
            html: html
        ).map(\.absoluteString)

        XCTAssertEqual(candidates.first, "https://example.com/news/assets/touch.png")
        XCTAssertEqual(candidates[1], "https://example.com/small.png")
        XCTAssertEqual(candidates[2], "https://cdn.example.com/page.png")
        XCTAssertTrue(candidates.contains("https://example.com/apple-touch-icon.png"))
        XCTAssertTrue(candidates.contains("https://example.com/favicon.ico"))
    }

    func testMetadataRejectsUnsupportedAndNonWebCandidates() {
        let html = """
            <link rel="icon" type="text/plain" href="/not-image.txt">
            <link rel="icon" href="data:image/png;base64,AAAA">
            <link rel="icon" href="javascript:alert(1)">
            <link rel="icon" type="image/png" href="/safe.png">
            """
        let pageURL = URL(string: "https://example.com/path")!

        XCTAssertEqual(
            SiteIconPolicy.metadataCandidates(html: html, pageURL: pageURL).map(\.absoluteString),
            ["https://example.com/safe.png"]
        )
    }

    func testCacheFileNameAndFreshnessAreBounded() {
        XCTAssertEqual(SiteIconPolicy.cacheFileName(for: "WWW.Example.COM"), "www.example.com.icon")
        XCTAssertEqual(SiteIconPolicy.cacheFileName(for: "bad/host"), "bad_host.icon")
        let now = Date(timeIntervalSince1970: 2_000_000)
        XCTAssertTrue(SiteIconPolicy.isCacheFresh(modifiedAt: now.addingTimeInterval(-60), now: now))
        XCTAssertFalse(
            SiteIconPolicy.isCacheFresh(modifiedAt: now.addingTimeInterval(-SiteIconPolicy.cacheTTL), now: now)
        )
        XCTAssertFalse(SiteIconPolicy.isCacheFresh(modifiedAt: now.addingTimeInterval(60), now: now))
    }
}
