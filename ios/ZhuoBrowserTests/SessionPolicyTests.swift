import XCTest
@testable import ZhuoBrowser

final class SessionPolicyTests: XCTestCase {
    func testRecentTabsKeepActiveFirstWithinItsPrivacyMode() {
        var privateTab = makeTab(id: "private", visitedAt: 100)
        privateTab.isPrivate = true
        let tabs = [
            makeTab(id: "old", visitedAt: 10),
            makeTab(id: "active", visitedAt: 20),
            privateTab,
            makeTab(id: "recent", visitedAt: 90)
        ]

        XCTAssertEqual(
            SessionPolicy.recentTabs(tabs, activeTabID: "active").map(\.id),
            ["active", "recent", "old"]
        )
    }

    func testRecentTabsRespectLimitAndMissingActiveTab() {
        let tabs = (0..<8).map { makeTab(id: "tab-\($0)", visitedAt: TimeInterval($0)) }

        XCTAssertEqual(
            SessionPolicy.recentTabs(tabs, activeTabID: "tab-0", limit: 3).map(\.id),
            ["tab-0", "tab-7", "tab-6"]
        )
        XCTAssertTrue(SessionPolicy.recentTabs(tabs, activeTabID: "missing").isEmpty)
        XCTAssertTrue(SessionPolicy.recentTabs(tabs, activeTabID: "tab-0", limit: 0).isEmpty)
    }

    func testLiveTabsUseActiveThenMostRecentNonHomeTabs() {
        let tabs = [
            makeTab(id: "old", url: "https://old.example", visitedAt: 10),
            makeTab(id: "home", url: URLPolicy.homeURL, visitedAt: 50),
            makeTab(id: "recent", url: "https://recent.example", visitedAt: 40),
            makeTab(id: "active", url: "https://active.example", visitedAt: 20)
        ]

        XCTAssertEqual(
            SessionPolicy.liveTabIDs(tabs: tabs, activeTabID: "active", limit: 3),
            ["active", "recent", "old"]
        )
    }

    func testLiveTabsKeepBothRequiredSplitPanes() {
        let tabs = [
            makeTab(id: "primary", visitedAt: 1),
            makeTab(id: "secondary", visitedAt: 2),
            makeTab(id: "active", visitedAt: 3)
        ]

        XCTAssertEqual(
            SessionPolicy.liveTabIDs(
                tabs: tabs,
                activeTabID: "active",
                limit: 1,
                requiredTabIDs: ["primary", "secondary"]
            ),
            ["primary", "secondary", "active"]
        )
    }

    func testExpiredTabsArePartitionedByConfiguredAge() {
        let now: TimeInterval = 1_000_000
        let tabs = [
            makeTab(id: "fresh", visitedAt: now - 60),
            makeTab(id: "expired", visitedAt: now - (8 * 24 * 60 * 60))
        ]

        let partition = SessionPolicy.partitionExpiredTabs(tabs, expiry: .sevenDays, now: now)

        XCTAssertEqual(partition.active.map(\.id), ["fresh"])
        XCTAssertEqual(partition.expired.map(\.id), ["expired"])
        XCTAssertEqual(SessionPolicy.partitionExpiredTabs(tabs, expiry: .never, now: now).active.count, 2)
    }

    func testSoftLimitCleanupPrefersStaleHomeAndLoadingTabs() {
        var tabs = (0..<12).map { index in
            makeTab(id: "tab-\(index)", visitedAt: TimeInterval(index + 1))
        }
        tabs[4].url = URLPolicy.homeURL
        tabs[7].isLoading = true

        let ids = SessionPolicy.softLimitCleanupCandidates(tabs: tabs, activeTabID: "tab-0", limit: 12)

        XCTAssertEqual(ids, ["tab-4"])
        XCTAssertFalse(ids.contains("tab-0"))
    }

    func testClosingActiveTabSelectsItsNextNeighbour() {
        let tabs = [makeTab(id: "a"), makeTab(id: "b"), makeTab(id: "c")]

        XCTAssertEqual(SessionPolicy.selectedTabAfterClosing(tabs, closing: "b"), "c")
        XCTAssertEqual(SessionPolicy.selectedTabAfterClosing(tabs, closing: "c"), "b")
    }

    func testCloseOthersStaysInsidePrivacyGroup() {
        let normalA = makeTab(id: "normal-a")
        let normalB = makeTab(id: "normal-b")
        var privateA = makeTab(id: "private-a")
        privateA.isPrivate = true
        var privateB = makeTab(id: "private-b")
        privateB.isPrivate = true
        let tabs = [normalA, normalB, privateA, privateB]

        XCTAssertEqual(SessionPolicy.otherTabIDs(in: tabs, keeping: "normal-a"), ["normal-b"])
        XCTAssertEqual(SessionPolicy.otherTabIDs(in: tabs, keeping: "private-a"), ["private-b"])
        XCTAssertEqual(SessionPolicy.otherTabIDs(in: tabs, keeping: "missing"), [])
    }

    func testAdjacentTabSelectionWrapsInBothDirections() {
        let tabs = [makeTab(id: "a"), makeTab(id: "b"), makeTab(id: "c")]

        XCTAssertEqual(SessionPolicy.adjacentTabID(tabs, activeTabID: "c", direction: 1), "a")
        XCTAssertEqual(SessionPolicy.adjacentTabID(tabs, activeTabID: "a", direction: -1), "c")
    }

    func testReorderingStaysInsidePinAndPrivacyGroups() {
        var pinnedA = makeTab(id: "pinned-a")
        pinnedA.isPinned = true
        var pinnedB = makeTab(id: "pinned-b")
        pinnedB.isPinned = true
        let normalA = makeTab(id: "normal-a")
        let normalB = makeTab(id: "normal-b")
        var privateTab = makeTab(id: "private")
        privateTab.isPrivate = true
        let tabs = [pinnedA, pinnedB, normalA, normalB, privateTab]

        XCTAssertEqual(
            SessionPolicy.reorderedTabs(tabs, moving: "pinned-a", direction: 1)?.map(\.id),
            ["pinned-b", "pinned-a", "normal-a", "normal-b", "private"]
        )
        XCTAssertNil(SessionPolicy.reorderedTabs(tabs, moving: "pinned-b", direction: 1))
        XCTAssertEqual(
            SessionPolicy.reorderedTabs(tabs, moving: "normal-a", targetID: "private")?.map(\.id),
            ["pinned-a", "pinned-b", "normal-b", "normal-a", "private"]
        )
        XCTAssertNil(SessionPolicy.reorderedTabs(tabs, moving: "normal-b", targetID: "private"))
    }

    func testLegacyTabDecodesNavigationAndPinDefaults() throws {
        let data = #"{"id":"old","url":"https://example.com","title":"Example","isPrivate":false,"isLoading":false,"progress":0,"canGoBack":true,"lastVisitedAt":1,"isReader":false,"isDesktop":false}"#.data(using: .utf8)!

        let tab = try JSONDecoder().decode(BrowserTab.self, from: data)

        XCTAssertFalse(tab.canGoForward)
        XCTAssertFalse(tab.isPinned)
        XCTAssertEqual(tab.scrollY, 0)
        XCTAssertEqual(tab.readerScrollY, 0)
        XCTAssertEqual(tab.scrollSavedAt, 0)
        XCTAssertEqual(tab.readerScrollSavedAt, 0)
        XCTAssertEqual(tab.formDraft, "")
        XCTAssertEqual(tab.loadError, .none)
    }

    func testTabPageStateRoundTrips() throws {
        var tab = makeTab(id: "stateful")
        tab.scrollY = 320
        tab.readerScrollY = 640
        tab.scrollSavedAt = 1_000
        tab.readerScrollSavedAt = 2_000
        tab.formDraft = #"[{"key":"note","value":"draft"}]"#
        tab.loadError = .timeout

        let decoded = try JSONDecoder().decode(BrowserTab.self, from: JSONEncoder().encode(tab))

        XCTAssertEqual(decoded, tab)
    }

    func testWindowRequestCarriesAValidatedTabSnapshot() throws {
        var tab = makeTab(id: "window-tab", url: "https://example.com/article")
        tab.scrollY = 240
        tab.formDraft = #"[{"key":"note","value":"draft"}]"#

        let request = try XCTUnwrap(BrowserWindowRequest(sourceSessionID: "source", tab: tab))

        XCTAssertEqual(request.sourceSessionID, "source")
        XCTAssertEqual(request.sourceTabID, tab.id)
        XCTAssertEqual(request.tab, tab)
    }

    private func makeTab(
        id: String,
        url: String = "https://example.com",
        visitedAt: TimeInterval = 1
    ) -> BrowserTab {
        BrowserTab(
            id: id,
            url: url,
            title: id,
            isPrivate: false,
            isLoading: false,
            progress: 0,
            canGoBack: false,
            lastVisitedAt: visitedAt,
            isReader: false,
            isDesktop: false
        )
    }
}
