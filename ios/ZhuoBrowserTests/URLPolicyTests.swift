import XCTest
@testable import ZhuoBrowser

final class URLPolicyTests: XCTestCase {
    func testCustomSearchTemplateReplacesFirstPlaceholder() {
        XCTAssertEqual(
            URLPolicy.normalizeAddress(
                "slow is fast",
                engine: .bing,
                customTemplate: "https://search.example/?q=%s&mirror=%s"
            ),
            "https://search.example/?q=slow%20is%20fast&mirror=%s"
        )
    }

    func testSearchPrefixBypassesCustomTemplate() {
        XCTAssertEqual(
            URLPolicy.searchURL(
                "g browser architecture",
                engine: .bing,
                customTemplate: "https://search.example/?q=%s"
            ),
            "https://www.google.com/search?q=browser%20architecture"
        )
    }

    func testInvalidTemplateFallsBackToSelectedEngine() {
        XCTAssertEqual(
            URLPolicy.searchURL(
                "privacy browser",
                engine: .duckDuckGo,
                customTemplate: "https://invalid.example/search"
            ),
            "https://duckduckgo.com/?q=privacy%20browser"
        )
    }
}
