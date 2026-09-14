import XCTest

@testable import ZhuoBrowser

final class SettingsSearchPolicyTests: XCTestCase {
    func testEmptyQueryShowsEverySection() {
        XCTAssertEqual(
            SettingsSearchPolicy.visibleSections(for: "   "),
            Set(SettingsSection.allCases)
        )
    }

    func testLabelsAndSemanticKeywordsFindTheirSections() {
        XCTAssertEqual(SettingsSearchPolicy.visibleSections(for: "网页最小字号"), [.appearance])
        XCTAssertEqual(SettingsSearchPolicy.visibleSections(for: "Wi-Fi"), [.downloads])
        XCTAssertEqual(SettingsSearchPolicy.visibleSections(for: "相机权限"), [.blocking])
        XCTAssertEqual(SettingsSearchPolicy.visibleSections(for: "遥测"), [.privacy])
    }

    func testMatchingIgnoresCaseAndWhitespace() {
        XCTAssertEqual(SettingsSearchPolicy.visibleSections(for: "duck duck go"), [.search])
        XCTAssertEqual(SettingsSearchPolicy.visibleSections(for: "  build  "), [.about])
    }

    func testChineseCompactQueryMatchesSeparatedKeywords() {
        XCTAssertEqual(SettingsSearchPolicy.visibleSections(for: "历史清除"), [.library, .privacy])
        XCTAssertEqual(SettingsSearchPolicy.visibleSections(for: "标签归档"), [.tabs])
    }

    func testUnknownQueryHasNoVisibleSection() {
        XCTAssertTrue(SettingsSearchPolicy.visibleSections(for: "quantum banana").isEmpty)
    }
}
