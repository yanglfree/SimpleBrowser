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
        XCTAssertTrue(URLPolicy.looksLikeURL("192.168.1.1"))
        XCTAssertTrue(URLPolicy.looksLikeURL("192.168.1.1:3000"))
        XCTAssertFalse(URLPolicy.looksLikeURL("how to save memory in browser"))
        XCTAssertFalse(URLPolicy.looksLikeURL("苹果发布会"))

        XCTAssertEqual(URLPolicy.normalizeAddress("apple.com"), "https://apple.com")
        XCTAssertEqual(URLPolicy.normalizeAddress("192.168.1.1:8000"), "https://192.168.1.1:8000")
        XCTAssertEqual(URLPolicy.normalizeAddress("zhuo://home"), "zhuo://home")
        XCTAssertEqual(URLPolicy.normalizeAddress(""), "zhuo://home")

        let searchResult = URLPolicy.normalizeAddress("swiftui tutorial", searchEngine: .bing)
        XCTAssertTrue(searchResult.contains("bing.com/search?q=swiftui%20tutorial"))

        XCTAssertEqual(URLPolicy.displayAddress(for: "https://www.baidu.com/s?wd=test"), "www.baidu.com/s")
        XCTAssertEqual(URLPolicy.displayAddress(for: "zhuo://home"), "")
    }

    @MainActor
    func testBrowserSessionNavigationAndControllerPublishing() {
        let session = BrowserSession()
        XCTAssertEqual(session.tabs.count, 1)
        XCTAssertTrue(session.activeTab?.isHome == true)
        XCTAssertNil(session.activeController)

        // Navigate to website
        session.navigate(to: "https://example.com")
        XCTAssertTrue(session.activeTab?.url.hasPrefix("https://example.com") == true)
        XCTAssertFalse(session.activeTab?.isHome ?? true)
        XCTAssertNotNil(session.activeController)
        XCTAssertEqual(session.activeController?.tabID, session.activeTabID)

        // Navigate back to home
        session.navigate(to: "zhuo://home")
        XCTAssertTrue(session.activeTab?.isHome == true)
        XCTAssertNil(session.activeController)
    }

    @MainActor
    func testTabCreationAndMemoryEvictionInSession() {
        let session = BrowserSession()
        session.settings.liveWebViewBudget = 2

        // Tab 1 (active)
        session.navigate(to: "https://example.com/1")
        let tab1ID = session.activeTabID!
        XCTAssertNotNil(session.activeController)

        // Tab 2 (active)
        let tab2 = session.createTab(url: "https://example.com/2", select: true)
        session.navigate(to: "https://example.com/2")
        XCTAssertEqual(session.activeLiveControllersCount, 2)

        // Tab 3 (active): exceeds budget 2, so tab 1 should be evicted (hibernated)
        let tab3 = session.createTab(url: "https://example.com/3", select: true)
        session.navigate(to: "https://example.com/3")
        XCTAssertEqual(session.activeLiveControllersCount, 2)

        let tab1 = session.tab(for: tab1ID)
        XCTAssertTrue(tab1?.isHibernated == true)

        // Switch back to tab 1: should unhibernate and restore controller
        session.selectTab(id: tab1ID)
        XCTAssertEqual(session.activeTabID, tab1ID)
        XCTAssertNotNil(session.activeController)
        XCTAssertEqual(session.activeTab?.isHibernated, false)
    }
}
