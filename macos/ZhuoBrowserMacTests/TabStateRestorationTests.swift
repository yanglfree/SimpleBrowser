import XCTest
@testable import ZhuoBrowserMac

final class TabStateRestorationTests: XCTestCase {

    // MARK: - Interaction state codec

    func testInteractionStateRoundTripsThroughDiskFormat() {
        let payload = Data([0xDE, 0xAD, 0xBE, 0xEF, 0x01, 0x02])
        guard let blob = InteractionStateCodec.encode(payload) else {
            return XCTFail("Encodable interaction state should produce a blob")
        }
        XCTAssertGreaterThan(blob.count, payload.count, "Marker byte must be prepended")

        guard let decoded = InteractionStateCodec.decode(blob) as? Data else {
            return XCTFail("Decoded state must be the original payload")
        }
        XCTAssertEqual(decoded, payload)
    }

    func testInteractionStateCodecRejectsUnusableValues() {
        XCTAssertNil(InteractionStateCodec.encode(nil))
        XCTAssertNil(InteractionStateCodec.encode("not-a-data-archive"))
        XCTAssertNil(InteractionStateCodec.encode(Data()))
        XCTAssertNil(InteractionStateCodec.decode(Data()))
        XCTAssertNil(InteractionStateCodec.decode(Data([0x02, 0x00])))
    }

    // MARK: - Restore policy

    private func snapshot(age: TimeInterval) -> TabStateSnapshot {
        TabStateSnapshot(
            url: "https://example.com/article",
            title: "Article",
            scrollPositionY: 1240,
            canGoBack: true,
            canGoForward: false,
            capturedAt: Date().addingTimeInterval(-age),
            interactionState: Data([0x01, 0x02, 0x03])
        )
    }

    func testLiveWebViewAlwaysWinsOverSnapshotRestore() {
        let strategy = TabRestorePolicy.decide(hasLiveWebView: true, snapshot: snapshot(age: 3600))
        XCTAssertEqual(strategy, .reuseLiveWebView)
        XCTAssertFalse(strategy.restoresFromSnapshot)
    }

    func testMissingSnapshotFallsBackToReload() {
        XCTAssertEqual(TabRestorePolicy.decide(hasLiveWebView: false, snapshot: nil), .reload)

        let stateless = TabStateSnapshot(
            url: "https://example.com",
            title: "",
            scrollPositionY: 0,
            canGoBack: false,
            canGoForward: false,
            interactionState: nil
        )
        XCTAssertEqual(TabRestorePolicy.decide(hasLiveWebView: false, snapshot: stateless), .reload)
    }

    func testFreshSnapshotRestoresInstantlyWithoutNetwork() {
        XCTAssertEqual(TabRestorePolicy.decide(hasLiveWebView: false, snapshot: snapshot(age: 5)), .restoreState)
    }

    func testAgingSnapshotRestoresButIsFlaggedStale() {
        let age = TabRestorePolicy.staleInterval + 60
        XCTAssertEqual(TabRestorePolicy.decide(hasLiveWebView: false, snapshot: snapshot(age: age)), .restoreStateMarkedStale)
    }

    func testExpiredSnapshotRestoresThenSmoothlyRefreshes() {
        let age = TabRestorePolicy.expirationInterval + 60
        let strategy = TabRestorePolicy.decide(hasLiveWebView: false, snapshot: snapshot(age: age))
        XCTAssertEqual(strategy, .restoreStateThenRefresh)
        XCTAssertTrue(strategy.restoresFromSnapshot)
    }

    func testSnapshotScrollPositionCanBeUpdatedWithoutLosingState() {
        let original = snapshot(age: 1)
        let updated = original.withScrollPosition(88)
        XCTAssertEqual(updated.scrollPositionY, 88)
        XCTAssertEqual(updated.interactionState, original.interactionState)
        XCTAssertEqual(updated.url, original.url)
    }

    func testSnapshotAgeIsNeverNegative() {
        let future = TabStateSnapshot(
            url: "https://example.com",
            title: "",
            scrollPositionY: 0,
            canGoBack: false,
            canGoForward: false,
            capturedAt: Date().addingTimeInterval(120),
            interactionState: Data([0x01])
        )
        XCTAssertEqual(future.age(), 0)
    }

    // MARK: - Budget under pressure

    func testMemoryPressureShrinksTheLivePool() {
        XCTAssertEqual(MemoryBudgetPolicy.effectiveBudget(requested: 8, pressure: .nominal), 8)
        XCTAssertEqual(
            MemoryBudgetPolicy.effectiveBudget(requested: 8, pressure: .warning),
            MemoryBudgetPolicy.warningBudget
        )
        XCTAssertEqual(
            MemoryBudgetPolicy.effectiveBudget(requested: 8, pressure: .critical),
            MemoryBudgetPolicy.criticalBudget
        )
        // Pressure can never push the pool above the user preference.
        XCTAssertEqual(MemoryBudgetPolicy.effectiveBudget(requested: 1, pressure: .warning), 1)
    }

    func testHomeTabsDoNotConsumeLiveSlots() {
        let now = Date()
        let home = BrowserTab(url: "zhuo://home", lastActiveTime: now)
        let siteA = BrowserTab(url: "https://a.example.com", lastActiveTime: now.addingTimeInterval(-10))
        let siteB = BrowserTab(url: "https://b.example.com", lastActiveTime: now.addingTimeInterval(-20))

        let plan = MemoryBudgetPolicy.evaluate(
            tabs: [home, siteA, siteB],
            activeTabID: home.id,
            budget: 2
        )

        XCTAssertTrue(plan.tabsToKeepAlive.contains(siteA.id))
        XCTAssertTrue(plan.tabsToKeepAlive.contains(siteB.id))
    }

    func testActiveTabIsNeverScheduledForHibernation() {
        let now = Date()
        let tabs = (1...6).map {
            BrowserTab(id: "tab-\($0)", url: "https://example.com/\($0)", lastActiveTime: now.addingTimeInterval(Double(-$0)))
        }
        let plan = MemoryBudgetPolicy.evaluate(tabs: tabs, activeTabID: "tab-6", budget: 1, pressure: .critical)
        XCTAssertTrue(plan.tabsToKeepAlive.contains("tab-6"))
        XCTAssertFalse(plan.tabsToHibernate.contains("tab-6"))
    }

    // MARK: - Store

    func testStoreKeepsSnapshotsInMemoryWhenPersistenceIsDisabled() {
        let store = TabStateStore(isPersistenceEnabled: false)
        let state = snapshot(age: 0)

        XCTAssertNil(store.snapshot(for: "tab-1"))
        store.store(state, for: "tab-1")
        XCTAssertEqual(store.cachedSnapshotCount, 1)
        XCTAssertEqual(store.snapshot(for: "tab-1")?.interactionState, state.interactionState)

        store.removeSnapshot(for: "tab-1")
        XCTAssertNil(store.snapshot(for: "tab-1"))
        XCTAssertEqual(store.cachedSnapshotCount, 0)
    }

    func testStoreRejectsSnapshotsWithoutRestorableState() {
        let store = TabStateStore(isPersistenceEnabled: false)
        let stateless = TabStateSnapshot(
            url: "https://example.com",
            title: "",
            scrollPositionY: 0,
            canGoBack: false,
            canGoForward: false,
            interactionState: nil
        )
        store.store(stateless, for: "tab-1")
        XCTAssertEqual(store.cachedSnapshotCount, 0)
    }

    // MARK: - Session behaviour

    func testResidentModeKeepsEveryTabAliveRegardlessOfBudget() {
        let now = Date()
        let home = BrowserTab(url: "zhuo://home", lastActiveTime: now)
        let sites = (1...6).map {
            BrowserTab(id: "site-\($0)", url: "https://example.com/\($0)", lastActiveTime: now.addingTimeInterval(Double(-$0)))
        }

        let plan = MemoryBudgetPolicy.evaluate(
            tabs: [home] + sites,
            activeTabID: home.id,
            budget: 1,
            pressure: .nominal,
            hibernationEnabled: false
        )

        XCTAssertTrue(plan.tabsToHibernate.isEmpty, "Resident mode must never freeze a background page")
        for site in sites {
            XCTAssertTrue(plan.tabsToKeepAlive.contains(site.id))
        }
    }

    func testOnlyCriticalPressureEvictsInResidentMode() {
        let now = Date()
        let tabs = (1...4).map {
            BrowserTab(id: "tab-\($0)", url: "https://example.com/\($0)", lastActiveTime: now.addingTimeInterval(Double(-$0)))
        }

        let warningPlan = MemoryBudgetPolicy.evaluate(
            tabs: tabs, activeTabID: "tab-1", budget: 1, pressure: .warning, hibernationEnabled: false
        )
        XCTAssertTrue(warningPlan.tabsToHibernate.isEmpty, "A warning must not cost the user a page reload")

        let criticalPlan = MemoryBudgetPolicy.evaluate(
            tabs: tabs, activeTabID: "tab-1", budget: 1, pressure: .critical, hibernationEnabled: false
        )
        XCTAssertFalse(criticalPlan.tabsToHibernate.contains("tab-1"))
        XCTAssertEqual(criticalPlan.effectiveBudget, MemoryBudgetPolicy.criticalBudget)
    }

    @MainActor
    func testResidentSessionSwitchesManyTabsWithoutRebuildingAny() {
        let session = BrowserSession(stateStore: TabStateStore(isPersistenceEnabled: false))
        session.settings.tabHibernationEnabled = false
        session.settings.liveWebViewBudget = 1

        session.navigate(to: "https://example.com/one")
        var ids: [String] = [session.activeTabID!]
        for index in 2...6 {
            let tab = session.createTab(url: "https://example.com/\(index)", select: true)
            ids.append(tab.id)
        }

        XCTAssertEqual(session.activeLiveControllersCount, ids.count, "Every tab must stay resident")

        for id in ids.reversed() {
            session.selectTab(id: id)
        }
        for id in ids {
            session.selectTab(id: id)
        }

        XCTAssertEqual(session.pageRebuildCount, 0, "Switching must never rebuild a resident page")
        XCTAssertEqual(session.frozenTabCount, 0)
        XCTAssertEqual(session.liveReuseCount, ids.count * 2)
    }

    @MainActor
    func testSwitchingBetweenResidentTabsReusesTheSameWebView() {
        let session = BrowserSession(stateStore: TabStateStore(isPersistenceEnabled: false))
        session.settings.tabHibernationEnabled = false
        session.settings.liveWebViewBudget = 4

        session.navigate(to: "https://example.com/one")
        let firstID = session.activeTabID!
        guard let firstController = session.activeController else {
            return XCTFail("Active tab should own a live controller")
        }

        let secondTab = session.createTab(url: "https://example.com/two", select: true)
        guard let secondController = session.activeController else {
            return XCTFail("Second tab should own a live controller")
        }
        XCTAssertFalse(secondController === firstController)

        // Switch back: the very same WebView object must come back (no reload at all).
        session.selectTab(id: firstID)
        XCTAssertTrue(session.activeController === firstController)
        XCTAssertEqual(session.activeTab?.isHibernated, false)
        XCTAssertFalse(session.activeTab?.isSnapshotStale ?? true)

        session.selectTab(id: secondTab.id)
        XCTAssertTrue(session.activeController === secondController)
    }

    @MainActor
    func testTabBeyondBudgetIsFrozenAndRestoredWithoutLosingIdentity() {
        let session = BrowserSession(stateStore: TabStateStore(isPersistenceEnabled: false))
        session.settings.tabHibernationEnabled = true
        session.settings.liveWebViewBudget = 1

        session.navigate(to: "https://example.com/one")
        let firstID = session.activeTabID!

        let secondTab = session.createTab(url: "https://example.com/two", select: true)
        XCTAssertEqual(session.activeLiveControllersCount, 1)
        XCTAssertEqual(session.tab(for: firstID)?.isHibernated, true)

        // Wait for the asynchronous freeze to actually release the WebView.
        let deadline = Date().addingTimeInterval(3)
        while session.controller(for: firstID) != nil && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        XCTAssertNil(session.controller(for: firstID), "Frozen tab must release its WebView")

        session.selectTab(id: firstID)
        XCTAssertEqual(session.activeTabID, firstID)
        XCTAssertEqual(session.activeTab?.isHibernated, false)
        XCTAssertEqual(session.activeController?.tabID, firstID)
        XCTAssertEqual(session.activeLiveControllersCount, 1)

        session.closeTab(id: secondTab.id)
        XCTAssertEqual(session.tabs.count, 1)
    }

    @MainActor
    func testClosingTabDropsItsSnapshotAndController() {
        let store = TabStateStore(isPersistenceEnabled: false)
        let session = BrowserSession(stateStore: store)

        session.navigate(to: "https://example.com/closeme")
        let id = session.activeTabID!
        XCTAssertNotNil(session.controller(for: id))

        session.closeTab(id: id)
        XCTAssertNil(session.controller(for: id))
        XCTAssertNil(store.snapshot(for: id))
        XCTAssertEqual(session.tabs.count, 1)
    }

    @MainActor
    func testHomeNavigationReleasesControllerButKeepsSingleTab() {
        let session = BrowserSession(stateStore: TabStateStore(isPersistenceEnabled: false))
        session.navigate(to: "https://example.com/one")
        XCTAssertNotNil(session.activeController)

        session.navigate(to: "zhuo://home")
        XCTAssertNil(session.activeController)
        XCTAssertEqual(session.activeTab?.isHome, true)
        XCTAssertEqual(session.tabs.count, 1)
    }

    func testSnapshotUsabilityRejectsURLMismatchAndStalePreLoginCapture() {
        let loginTime = Date()
        let postLoginTab = BrowserTab(
            id: "tab-xhs",
            url: "https://creator.xiaohongshu.com/publish/publish?source=official",
            title: "小红书创作服务平台",
            lastActiveTime: loginTime
        )

        let preLoginRedirectSnapshot = TabStateSnapshot(
            url: "https://creator.xiaohongshu.com/login?source=official&redirectReason=401",
            title: "小红书创作服务平台",
            scrollPositionY: 0,
            canGoBack: false,
            canGoForward: false,
            capturedAt: loginTime,
            interactionState: Data([0x01, 0x02])
        )
        XCTAssertFalse(
            BrowserSession.isSnapshotUsable(preLoginRedirectSnapshot, for: postLoginTab),
            "A snapshot from /login must never overwrite a post-login /publish tab"
        )

        let olderSameURLSnapshot = TabStateSnapshot(
            url: "https://channels.weixin.qq.com/platform/post/list",
            title: "视频号助手",
            scrollPositionY: 0,
            canGoBack: false,
            canGoForward: false,
            capturedAt: loginTime.addingTimeInterval(-600),
            interactionState: Data([0x01, 0x02])
        )
        let channelsTab = BrowserTab(
            id: "tab-channels",
            url: "https://channels.weixin.qq.com/platform/post/list",
            title: "视频号助手",
            lastActiveTime: loginTime
        )
        XCTAssertFalse(
            BrowserSession.isSnapshotUsable(olderSameURLSnapshot, for: channelsTab),
            "A snapshot captured before the tab's latest login/navigation must be rejected"
        )

        let freshMatchingSnapshot = TabStateSnapshot(
            url: "https://channels.weixin.qq.com/platform/post/list",
            title: "视频号助手",
            scrollPositionY: 120,
            canGoBack: true,
            canGoForward: false,
            capturedAt: loginTime,
            interactionState: Data([0x01, 0x02])
        )
        XCTAssertTrue(BrowserSession.isSnapshotUsable(freshMatchingSnapshot, for: channelsTab))
    }
}
