import XCTest
@testable import ZhuoBrowserMac

final class MemoryBudgetPolicyTests: XCTestCase {

    func testActiveTabIsAlwaysKeptAlive() {
        let now = Date()
        let tab1 = BrowserTab(id: "tab-1", url: "https://example.com/1", lastActiveTime: now.addingTimeInterval(-100))
        let tab2 = BrowserTab(id: "tab-2", url: "https://example.com/2", lastActiveTime: now.addingTimeInterval(-10))
        let tab3 = BrowserTab(id: "tab-3", url: "https://example.com/3", lastActiveTime: now.addingTimeInterval(-200))

        // Even though tab-1 has older lastActiveTime than tab-2, if it is active, it must stay alive
        let plan = MemoryBudgetPolicy.evaluate(tabs: [tab1, tab2, tab3], activeTabID: "tab-1", budget: 1)

        XCTAssertTrue(plan.tabsToKeepAlive.contains("tab-1"))
        XCTAssertEqual(plan.tabsToKeepAlive.count, 1)
        XCTAssertTrue(plan.tabsToHibernate.contains("tab-2"))
        XCTAssertTrue(plan.tabsToHibernate.contains("tab-3"))
    }

    func testBudgetPreservesMostRecentTabs() {
        let now = Date()
        let tab1 = BrowserTab(id: "tab-1", url: "https://example.com/1", lastActiveTime: now.addingTimeInterval(-10)) // active
        let tab2 = BrowserTab(id: "tab-2", url: "https://example.com/2", lastActiveTime: now.addingTimeInterval(-20)) // recent
        let tab3 = BrowserTab(id: "tab-3", url: "https://example.com/3", lastActiveTime: now.addingTimeInterval(-50)) // older
        let tab4 = BrowserTab(id: "tab-4", url: "https://example.com/4", lastActiveTime: now.addingTimeInterval(-100)) // oldest

        let plan = MemoryBudgetPolicy.evaluate(tabs: [tab1, tab2, tab3, tab4], activeTabID: "tab-1", budget: 2)

        XCTAssertEqual(plan.tabsToKeepAlive, Set(["tab-1", "tab-2"]))
        XCTAssertEqual(plan.tabsToHibernate, Set(["tab-3", "tab-4"]))
    }

    func testBudgetWithinLimitDoesNotHibernate() {
        let now = Date()
        let tab1 = BrowserTab(id: "tab-1", url: "https://example.com/1", lastActiveTime: now)
        let tab2 = BrowserTab(id: "tab-2", url: "https://example.com/2", lastActiveTime: now)

        let plan = MemoryBudgetPolicy.evaluate(tabs: [tab1, tab2], activeTabID: "tab-1", budget: 3)

        XCTAssertEqual(plan.tabsToKeepAlive, Set(["tab-1", "tab-2"]))
        XCTAssertTrue(plan.tabsToHibernate.isEmpty)
    }

    func testClampedBudgetEnforcesLimits() {
        let now = Date()
        let tabs = (1...10).map {
            BrowserTab(id: "tab-\($0)", url: "https://example.com/\($0)", lastActiveTime: now.addingTimeInterval(Double(-$0)))
        }

        // Budget requested 0 (should clamp to min 1)
        let minPlan = MemoryBudgetPolicy.evaluate(tabs: tabs, activeTabID: "tab-1", budget: 0)
        XCTAssertEqual(minPlan.tabsToKeepAlive.count, 1)

        // Budget requested 100 (should clamp to max 4)
        let maxPlan = MemoryBudgetPolicy.evaluate(tabs: tabs, activeTabID: "tab-1", budget: 100)
        XCTAssertEqual(maxPlan.tabsToKeepAlive.count, 4)
        XCTAssertEqual(maxPlan.tabsToHibernate.count, 6)
    }

    func testURLPolicyLooksLikeURLAndNormalization() {
        XCTAssertTrue(URLPolicy.looksLikeURL("apple.com"))
        XCTAssertTrue(URLPolicy.looksLikeURL("https://github.com"))
        XCTAssertTrue(URLPolicy.looksLikeURL("localhost:8080"))
        XCTAssertFalse(URLPolicy.looksLikeURL("how to save memory in browser"))

        XCTAssertEqual(URLPolicy.normalizeAddress("apple.com"), "https://apple.com")
        XCTAssertEqual(URLPolicy.normalizeAddress("zhuo://home"), "zhuo://home")
        XCTAssertEqual(URLPolicy.normalizeAddress(""), "zhuo://home")

        let searchResult = URLPolicy.normalizeAddress("swiftui tutorial", searchEngine: .bing)
        XCTAssertTrue(searchResult.contains("bing.com/search?q=swiftui%20tutorial"))
    }
}
