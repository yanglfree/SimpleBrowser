import XCTest
@testable import ZhuoBrowser

final class OmniboxShortcutPolicyTests: XCTestCase {
    func testSuffixAppendsAtCaret() {
        let result = apply("openai", selection: .init(start: 6, end: 6), label: ".com", kind: .suffix)
        XCTAssertEqual(result.text, "openai.com")
        XCTAssertEqual(result.selection, .init(start: 10, end: 10))
    }

    func testPrefixFollowsSchemeAndSupportsFullSelection() {
        let caretResult = apply(
            "https://example.com",
            selection: .init(start: 19, end: 19),
            label: "www.",
            kind: .prefix
        )
        let selectedResult = apply(
            "https://example.com",
            selection: .init(start: 0, end: 19),
            label: "www.",
            kind: .prefix
        )
        XCTAssertEqual(caretResult.text, "https://www.example.com")
        XCTAssertEqual(selectedResult.text, "https://www.example.com")
    }

    func testCurrentHostReplacesSelection() {
        let result = apply(
            "https://example.com/article",
            selection: .init(start: 0, end: 27),
            label: "example.com",
            kind: .currentHost
        )
        XCTAssertEqual(result.text, "example.com")
        XCTAssertEqual(result.selection, .init(start: 11, end: 11))
    }

    func testRepeatedSuffixAndPathAreIdempotent() {
        XCTAssertEqual(
            apply("openai.com", selection: .init(start: 10, end: 10), label: ".com", kind: .suffix).text,
            "openai.com"
        )
        XCTAssertEqual(
            apply("openai.com/", selection: .init(start: 11, end: 11), label: "/", kind: .path).text,
            "openai.com/"
        )
        XCTAssertEqual(
            apply("https://openai.com", selection: .init(start: 0, end: 18), label: "/", kind: .path).text,
            "https://openai.com/"
        )
    }

    func testShortcutCatalogMatchesHarmonyOrder() {
        let shortcuts = OmniboxShortcutPolicy.shortcuts(currentHost: " example.com ")
        XCTAssertEqual(
            shortcuts.map(\.label),
            ["example.com", ".com", ".cn", "www.", "/"]
        )
        XCTAssertEqual(
            shortcuts.map(\.accessibilityIdentifier),
            [
                "omni-shortcut-current-host",
                "omni-shortcut-com",
                "omni-shortcut-cn",
                "omni-shortcut-prefix",
                "omni-shortcut-path"
            ]
        )
        XCTAssertEqual(
            OmniboxShortcutPolicy.shortcuts(currentHost: "").map(\.label),
            [".com", ".cn", "www.", "/"]
        )
    }

    private func apply(
        _ text: String,
        selection: OmniboxSelection,
        label: String,
        kind: OmniboxShortcutKind
    ) -> OmniboxEditResult {
        OmniboxShortcutPolicy.apply(
            text: text,
            selection: selection,
            shortcut: OmniboxShortcut(label: label, value: label, kind: kind)
        )
    }
}
