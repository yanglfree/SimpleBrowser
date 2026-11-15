import Foundation
import UIKit
import WebKit

extension BrowserSession {
    func presentTabOverview() {
        let tabID = activeTabID
        captureTabThumbnail(tabID: tabID) { [weak self] in
            guard let self, self.tab(tabID) != nil else { return }
            self.showsOverview = true
        }
    }

    func toggleTabOverview() {
        if showsOverview {
            showsOverview = false
        } else {
            presentTabOverview()
        }
    }

    @discardableResult
    func createTab(isPrivate: Bool, select: Bool = true) -> String? {
        guard tabs.count < SessionPolicy.maxTabCount else {
            return nil
        }
        if tabs.count >= settings.tabSoftLimit {
            showsTabSoftLimitPrompt = true
        }
        let tab = BrowserTab.home(isPrivate: isPrivate)
        tabs.append(tab)
        if select {
            selectTab(tab.id)
        }
        persist()
        return tab.id
    }

    func canOpenTabBeside(_ id: String) -> Bool {
        guard let activeTab, let target = tab(id) else { return false }
        return target.id != activeTab.id && target.isPrivate == activeTab.isPrivate
    }

    @discardableResult
    func openTabBeside(_ requestedID: String) -> Bool {
        guard let primary = activeTab,
              let target = tab(requestedID),
              target.id != primary.id,
              target.isPrivate == primary.isPrivate else { return false }
        paneState.beginSplit(primaryTabID: primary.id, secondaryTabID: target.id)
        ensureLive(primary.id)
        ensureLive(target.id)
        selectTab(target.id)
        return true
    }

    func focusPane(_ tabID: String) {
        guard paneState.contains(tabID) else { return }
        selectTab(tabID)
    }

    func closeSplit() {
        paneState.closeSplit(focusedTabID: activeTabID)
        trimLive()
    }

    func setSplitRatio(_ ratio: Double) {
        paneState.setPrimaryRatio(ratio)
    }

    func makeWindowRequest(for tabID: String) -> BrowserWindowRequest? {
        guard let current = tab(tabID) else { return nil }
        capturePageState(tabID)
        var snapshot = tab(tabID) ?? current
        snapshot.isLoading = false
        snapshot.progress = 0
        snapshot.canGoBack = false
        snapshot.canGoForward = false
        guard let request = BrowserWindowRequest(sourceSessionID: sessionID, tab: snapshot) else {
            return nil
        }
        pendingWindowTransferIDs.insert(request.id)
        return request
    }

    func completeWindowTransfer(_ notification: Notification) {
        guard let requestID = notification.userInfo?["requestID"] as? String,
              let sourceSessionID = notification.userInfo?["sourceSessionID"] as? String,
              let sourceTabID = notification.userInfo?["sourceTabID"] as? String,
              sourceSessionID == sessionID,
              pendingWindowTransferIDs.remove(requestID) != nil else { return }
        detachTransferredTab(sourceTabID)
    }

    func detachTransferredTab(_ id: String) {
        guard tab(id) != nil else { return }
        let wasPane = paneState.contains(id)
        let nextActiveID = activeTabID == id
            ? SessionPolicy.selectedTabAfterClosing(tabs, closing: id)
            : activeTabID
        controllers[id] = nil
        cancelPrompts(forTabID: id)
        lastWebProcessTerminationAt[id] = nil
        removeTabThumbnail(tabID: id)
        tabBlockStats[id] = nil
        blockEvents.removeAll { $0.tabID == id }
        disposableReaderTabIDs.remove(id)
        pendingArticleCaptureTabIDs.remove(id)
        tabs.removeAll { $0.id == id }
        if tabs.isEmpty {
            let home = BrowserTab.home(isPrivate: false)
            tabs = [home]
            activeTabID = home.id
        } else if activeTabID == id {
            activeTabID = nextActiveID ?? tabs[0].id
        }
        paneState.repair(existingTabIDs: existingTabIDs, fallbackTabID: activeTabID)
        if wasPane {
            activeTabID = paneState.focusedTabID
        }
        dismissPageResume()
        recyclePrivateStoreIfNeeded()
        ensureLive(activeTabID)
        persist()
    }

    func selectTab(_ id: String) {
        guard let selectedTab = tab(id) else {
            return
        }
        if activeTabID != id {
            cancelPrompts(forTabID: activeTabID)
            captureTabThumbnail(tabID: activeTabID)
            capturePageState(activeTabID)
        }
        dismissPageResume()
        if isSplitActive,
           let primaryTab = tab(paneState.primaryTabID),
           selectedTab.isPrivate != primaryTab.isPrivate {
            paneState.closeSplit(focusedTabID: id)
        } else {
            paneState.select(id, existingTabIDs: existingTabIDs)
        }
        activeTabID = id
        update(tabID: id) { tab in
            tab.lastVisitedAt = Date().timeIntervalSince1970
        }
        showsOverview = false
        endFind()
        ensureLive(id)
        persist()
    }

    func closeTab(_ id: String) {
        capturePageState(id)
        finishClosingTab(id)
    }

    func canCloseOtherTabs(keeping id: String) -> Bool {
        !SessionPolicy.otherTabIDs(in: tabs, keeping: id).isEmpty
    }

    func closeOtherTabs(keeping id: String) {
        guard let target = tab(id) else { return }
        let closeIDs = SessionPolicy.otherTabIDs(in: tabs, keeping: id)
        guard !closeIDs.isEmpty else { return }
        selectTab(id)
        for closeID in closeIDs {
            capturePageState(closeID)
            finishClosingTab(closeID, clearCookiesIfNeeded: false)
        }
        if !target.isPrivate && settings.clearCookiesOnTabClose {
            clearCookies()
        }
        flash("已关闭其他标签页")
    }

    func copyTabLink(_ id: String) {
        guard let target = tab(id),
              !URLPolicy.isHomeURL(target.url),
              let url = URL(string: target.url) else {
            return
        }
        UIPasteboard.general.url = url
        flash("链接已复制")
    }

    func openLinkInBackground(_ url: URL, sourceTabID: String) {
        guard let source = tab(sourceTabID),
              let targetURL = WebLinkActionPolicy.webURL(url),
              let newTabID = createTab(isPrivate: source.isPrivate, select: false) else {
            return
        }
        prepareLinkedTab(newTabID, url: targetURL.absoluteString)
        flash("已在后台标签页打开")
    }

    func openLinkBeside(_ url: URL, sourceTabID: String) {
        guard let source = tab(sourceTabID),
              let targetURL = WebLinkActionPolicy.webURL(url),
              let newTabID = createTab(isPrivate: source.isPrivate, select: false) else {
            return
        }
        prepareLinkedTab(newTabID, url: targetURL.absoluteString)
        selectTab(sourceTabID)
        if !openTabBeside(newTabID) {
            flash("已在后台标签页打开")
        }
    }

    func prepareLinkedTab(_ tabID: String, url: String) {
        let usesDesktop = effectiveSiteControl(for: url).desktopUserAgentEnabled
        update(tabID: tabID) { tab in
            tab.url = url
            tab.title = URLPolicy.displayHost(url)
            tab.isDesktop = usesDesktop
            tab.lastVisitedAt = Date().timeIntervalSince1970
        }
        ensureLive(tabID)
        persist()
    }

    func finishClosingTab(_ id: String, clearCookiesIfNeeded: Bool = true) {
        guard let closingTab = tab(id) else {
            return
        }
        let wasPane = paneState.contains(id)
        if !closingTab.isPrivate {
            recentlyClosedTabs.insert(closingTab, at: 0)
            recentlyClosedTabs = Array(recentlyClosedTabs.prefix(10))
        }
        let nextActiveID = activeTabID == id
            ? SessionPolicy.selectedTabAfterClosing(tabs, closing: id)
            : activeTabID
        controllers[id] = nil
        cancelPrompts(forTabID: id)
        lastWebProcessTerminationAt[id] = nil
        removeTabThumbnail(tabID: id)
        tabBlockStats[id] = nil
        blockEvents.removeAll { $0.tabID == id }
        disposableReaderTabIDs.remove(id)
        pendingArticleCaptureTabIDs.remove(id)
        tabs.removeAll { $0.id == id }
        if tabs.isEmpty {
            let home = BrowserTab.home(isPrivate: false)
            tabs = [home]
            activeTabID = home.id
        } else if activeTabID == id {
            activeTabID = nextActiveID ?? tabs[0].id
        }
        paneState.repair(existingTabIDs: existingTabIDs, fallbackTabID: activeTabID)
        if wasPane {
            activeTabID = paneState.focusedTabID
        }
        dismissPageResume()
        recyclePrivateStoreIfNeeded()
        ensureLive(activeTabID)
        persist()
        if clearCookiesIfNeeded && !closingTab.isPrivate && settings.clearCookiesOnTabClose {
            clearCookies()
        }
    }

    @discardableResult
    func reopenRecentlyClosedTab() -> Bool {
        guard tabs.count < SessionPolicy.maxTabCount,
              var restored = recentlyClosedTabs.first else {
            return false
        }
        recentlyClosedTabs.removeFirst()
        restored.id = UUID().uuidString
        restored.isPrivate = false
        restored.isLoading = false
        restored.progress = 0
        restored.canGoBack = false
        restored.canGoForward = false
        restored.lastVisitedAt = Date().timeIntervalSince1970
        tabs.append(restored)
        selectTab(restored.id)
        flash("已恢复关闭的标签页")
        return true
    }

    func switchAdjacentTab(_ direction: Int) {
        guard let id = SessionPolicy.adjacentTabID(tabs, activeTabID: activeTabID, direction: direction) else {
            return
        }
        selectTab(id)
    }

    func canReorderTab(_ id: String, direction: Int) -> Bool {
        SessionPolicy.canReorderTab(tabs, id: id, direction: direction)
    }

    func reorderTab(_ id: String, direction: Int) {
        guard let reordered = SessionPolicy.reorderedTabs(tabs, moving: id, direction: direction) else {
            return
        }
        tabs = reordered
        persist()
    }

    @discardableResult
    func moveTab(_ id: String, to targetID: String) -> Bool {
        guard let reordered = SessionPolicy.reorderedTabs(tabs, moving: id, targetID: targetID) else {
            return false
        }
        tabs = reordered
        persist()
        return true
    }

    func toggleTabPinned(_ id: String) {
        guard let current = tab(id), !current.isPrivate else {
            return
        }
        update(tabID: id) { tab in
            tab.isPinned.toggle()
        }
        let pinned = tabs.filter { !$0.isPrivate && $0.isPinned }
        let normal = tabs.filter { !$0.isPrivate && !$0.isPinned }
        let privateTabs = tabs.filter(\.isPrivate)
        tabs = pinned + normal + privateTabs
        persist()
        flash(current.isPinned ? "已取消固定标签页" : "已固定标签页")
    }

    func cleanupSoftLimitTabs() {
        let ids = SessionPolicy.softLimitCleanupCandidates(
            tabs: tabs,
            activeTabID: activeTabID,
            limit: settings.tabSoftLimit
        )
        guard !ids.isEmpty else {
            return
        }
        let idSet = Set(ids)
        ids.forEach {
            controllers[$0] = nil
            cancelPrompts(forTabID: $0)
            removeTabThumbnail(tabID: $0)
        }
        tabs.removeAll { idSet.contains($0.id) }
        recyclePrivateStoreIfNeeded()
        persist()
        flash("已清理 \(ids.count) 个旧标签页")
    }

    func restoreExpiredTabs() {
        let availableCount = max(0, SessionPolicy.maxTabCount - tabs.count)
        let archivedToRestore = Array(archivedTabs.prefix(availableCount))
        guard !archivedToRestore.isEmpty else {
            flash("标签页已达上限")
            return
        }
        let now = Date().timeIntervalSince1970
        let restored = archivedToRestore.map { archived -> BrowserTab in
            var tab = archived
            tab.id = UUID().uuidString
            tab.isPrivate = false
            tab.isLoading = false
            tab.progress = 0
            tab.canGoBack = false
            tab.canGoForward = false
            tab.lastVisitedAt = now
            return tab
        }
        tabs.append(contentsOf: restored)
        archivedTabs.removeFirst(archivedToRestore.count)
        persistArchivedTabs()
        persist()
        flash("已恢复 \(restored.count) 个过期标签页")
    }

    func closeAll() {
        let shouldClearCookies = settings.clearCookiesOnTabClose && tabs.contains { !$0.isPrivate }
        cancelPrompts(forTabID: activeTabID)
        dismissPageResume()
        controllers.removeAll()
        clearTabThumbnails()
        tabThumbnailTokens.removeAll()
        disposableReaderTabIDs.removeAll()
        pendingArticleCaptureTabIDs.removeAll()
        pendingWindowTransferIDs.removeAll()
        lastWebProcessTerminationAt.removeAll()
        let home = BrowserTab.home(isPrivate: false)
        tabs = [home]
        activeTabID = home.id
        paneState = BrowserPaneState(primaryTabID: home.id)
        privateStore = WKWebsiteDataStore.nonPersistent()
        persist()
        if shouldClearCookies {
            clearCookies()
        }
    }

    func tabThumbnail(for tab: BrowserTab) -> UIImage? {
        tab.isPrivate ? nil : tabThumbnails[tab.id]
    }

    func captureTabThumbnail(tabID: String, completion: @escaping () -> Void = {}) {
        guard let tab = tab(tabID), let controller = controllers[tabID] else {
            completion()
            return
        }
        let webView = controller.webView
        let bounds = webView.bounds
        guard TabThumbnailPolicy.shouldCapture(
            url: tab.url,
            isPrivate: tab.isPrivate,
            isAttached: webView.window != nil,
            viewWidth: Double(bounds.width),
            viewHeight: Double(bounds.height)
        ) else {
            completion()
            return
        }
        let token = UUID()
        tabThumbnailTokens[tabID] = token
        let configuration = WKSnapshotConfiguration()
        configuration.rect = CGRect(
            x: 0,
            y: 0,
            width: bounds.width,
            height: CGFloat(
                TabThumbnailPolicy.visibleSnapshotHeight(
                    viewWidth: Double(bounds.width),
                    viewHeight: Double(bounds.height)
                )
            )
        )
        configuration.snapshotWidth = NSNumber(value: TabThumbnailPolicy.snapshotWidth)
        webView.takeSnapshot(with: configuration) { [weak self] image, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                if self.tabThumbnailTokens[tabID] == token,
                   self.tab(tabID) != nil,
                   let image {
                    self.setTabThumbnail(image, forTabID: tabID)
                }
                completion()
            }
        }
    }

    func invalidateTabThumbnail(tabID: String) {
        tabThumbnailTokens[tabID] = UUID()
        setTabThumbnail(nil, forTabID: tabID)
    }

    func removeTabThumbnail(tabID: String) {
        tabThumbnailTokens[tabID] = nil
        setTabThumbnail(nil, forTabID: tabID)
    }
}
