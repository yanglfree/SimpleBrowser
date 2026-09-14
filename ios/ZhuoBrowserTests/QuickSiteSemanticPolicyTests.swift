import XCTest
@testable import ZhuoBrowser

final class QuickSiteSemanticPolicyTests: XCTestCase {
    func testMatchesDownloadIntentByTitleAndURL() {
        XCTAssertEqual(
            QuickSiteSemanticPolicy.theme(title: "下载页", url: "https://example.com"),
            QuickSiteSemanticTheme(systemImageName: "arrow.down.to.line", backgroundHex: "#1D4ED8")
        )
        XCTAssertEqual(
            QuickSiteSemanticPolicy.theme(title: "Custom Tool", url: "browser://downloads")?.systemImageName,
            "arrow.down.to.line"
        )
    }

    func testMatchesHistoryBookmarksAndSettingsIntents() {
        XCTAssertEqual(themeName(title: "历史记录"), "clock")
        XCTAssertEqual(themeName(title: "我的书签"), "bookmark")
        XCTAssertEqual(themeName(title: "系统设置"), "gearshape")
    }

    func testMatchesReaderSearchHomeAndPrivacyIntents() {
        XCTAssertEqual(themeName(title: "科技博客"), "text.alignleft")
        XCTAssertEqual(themeName(title: "全网搜索"), "magnifyingglass")
        XCTAssertEqual(themeName(title: "导航首页"), "house")
        XCTAssertEqual(themeName(title: "无痕模式"), "eyeglasses")
    }

    func testMatchesShareIntent() {
        XCTAssertEqual(themeName(title: "分享社区"), "square.and.arrow.up")
    }

    func testUsesHarmonySemanticColors() {
        let expectedColors = [
            "下载": "#1D4ED8",
            "历史": "#EA580C",
            "书签": "#D97706",
            "设置": "#475569",
            "阅读": "#059669",
            "搜索": "#0284C7",
            "首页": "#0D9488",
            "隐私": "#334155",
            "分享": "#7C3AED"
        ]

        for (title, expectedColor) in expectedColors {
            XCTAssertEqual(
                QuickSiteSemanticPolicy.theme(title: title, url: "https://example.com")?.backgroundHex,
                expectedColor
            )
        }
    }

    func testKeepsHarmonyPriorityWhenMultipleIntentsMatch() {
        XCTAssertEqual(themeName(title: "下载历史"), "arrow.down.to.line")
        XCTAssertEqual(themeName(title: "收藏设置"), "bookmark")
    }

    func testReturnsNilForOrdinarySites() {
        XCTAssertNil(QuickSiteSemanticPolicy.theme(title: "知乎", url: "https://www.zhihu.com"))
        XCTAssertNil(QuickSiteSemanticPolicy.theme(title: "V2EX", url: "https://v2ex.com"))
        XCTAssertNil(QuickSiteSemanticPolicy.theme(title: "GitHub", url: "https://github.com"))
    }

    private func themeName(title: String) -> String? {
        QuickSiteSemanticPolicy.theme(title: title, url: "https://example.com")?.systemImageName
    }
}
