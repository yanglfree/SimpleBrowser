import Combine
import Foundation
import SwiftUI
import WebKit

final class BrowserSession: ObservableObject {
    @Published var tabs: [BrowserTab]
    @Published var activeTabID: String
    @Published var showsOverview = false
    @Published var showsFind = false
    @Published var findQuery = ""
    @Published var findCurrent = 0
    @Published var findTotal = 0
    @Published var readerSettings = ReaderSettings()
    @Published var notice: String?
    @Published var settings = BrowserSettings()
    @Published var showsSettings = false
    @Published var showsDownloads = false
    @Published var showsShare = false
    @Published var shareItems: [Any] = []
    @Published var showsLibrary = false
    @Published var libraryTab: LibraryTab = .bookmarks
    @Published var history: [HistoryEntry] = []
    @Published var savedItems: [SavedItem] = []
    @Published var allowedHosts: [String] = []
    @Published var sitePermissions: [SitePermission] = []
    @Published var permissionPrompt: PermissionPrompt?
    @Published var quickSites: [QuickSite] = []
    @Published var navigationHistoryEntries: [NavigationHistoryEntry] = []
    @Published var showsNavigationHistory = false
    @Published var archivedTabs: [BrowserTab] = []
    @Published var showsExpiredTabsPrompt = false
    @Published var showsTabSoftLimitPrompt = false
    let downloads = DownloadStore()
    private var permissionReply: ((Bool) -> Void)?

    private var controllers: [String: TabController] = [:]
    private var privateStore = WKWebsiteDataStore.nonPersistent()
    private var recentlyClosedTabs: [BrowserTab] = []
    private var cancellables: Set<AnyCancellable> = []
    private let defaultsKey = "browser_session"
    private let archivedTabsKey = "browser_archived_tabs"

    var activeTab: BrowserTab? {
        tab(activeTabID)
    }

    var activeController: TabController? {
        controllers[activeTabID]
    }

    var canReopenRecentlyClosedTab: Bool {
        !recentlyClosedTabs.isEmpty && tabs.count < SessionPolicy.maxTabCount
    }

    init() {
        let loadedSettings = Self.loadSettings()
        if let restored = Self.restore(settings: loadedSettings) {
            if restored.tabs.isEmpty {
                let home = BrowserTab.home(isPrivate: false)
                tabs = [home]
                activeTabID = home.id
            } else {
                tabs = restored.tabs
                activeTabID = restored.activeTabID
            }
            archivedTabs = Self.mergedArchivedTabs(Self.loadArchivedTabs(), restored.expiredTabs)
        } else {
            let home = BrowserTab.home(isPrivate: false)
            tabs = [home]
            activeTabID = home.id
            archivedTabs = Self.loadArchivedTabs()
        }
        ContentBlocker.shared.onListsChanged = { [weak self] in
            self?.controllers.values.forEach { $0.applyContentBlocker() }
        }
        ContentBlocker.shared.prepare()
        readerSettings = Self.loadReaderSettings()
        settings = loadedSettings
        history = Self.loadHistory()
        savedItems = Self.loadSavedItems()
        allowedHosts = Self.loadAllowedHosts()
        sitePermissions = Self.loadSitePermissions()
        quickSites = Self.loadQuickSites()
        persistArchivedTabs()
        showsExpiredTabsPrompt = !archivedTabs.isEmpty
        downloads.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        ensureLive(activeTabID)
        persist()
    }

    func tab(_ id: String) -> BrowserTab? {
        tabs.first { $0.id == id }
    }

    func update(tabID: String, mutate: (inout BrowserTab) -> Void) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else {
            return
        }
        mutate(&tabs[index])
    }

    func openInActiveTab(_ raw: String) {
        let address = URLPolicy.normalizeAddress(raw, engine: settings.searchEngine)
        update(tabID: activeTabID) { tab in
            tab.url = address
            tab.lastVisitedAt = Date().timeIntervalSince1970
        }
        if URLPolicy.isHomeURL(address) {
            persist()
            return
        }
        if let controller = controllers[activeTabID] {
            controller.load(address)
        } else if let current = activeTab {
            let controller = makeController(for: current)
            controllers[current.id] = controller
            controller.load(address)
            trimLive()
        }
        persist()
    }

    func recordVisit(of tab: BrowserTab) {
        guard SessionPolicy.shouldRecordHistory(tab.isPrivate), !URLPolicy.isHomeURL(tab.url) else {
            return
        }
        let title = tab.title.isEmpty ? URLPolicy.displayHost(tab.url) : tab.title
        history = LibraryPolicy.recordHistory(
            history,
            entry: HistoryEntry(
                id: "history-\(Int(Date().timeIntervalSince1970 * 1000))",
                title: title,
                url: tab.url,
                visitedAt: Date().timeIntervalSince1970,
                visitCount: 0
            )
        )
        persistLibrary()
    }

    func isCurrentPageSaved() -> Bool {
        guard let tab = activeTab else {
            return false
        }
        return LibraryPolicy.isSaved(savedItems, url: tab.url)
    }

    func toggleSaved() {
        guard let tab = activeTab, !URLPolicy.isHomeURL(tab.url) else {
            return
        }
        if let existing = savedItems.first(where: { $0.url == tab.url }) {
            savedItems = LibraryPolicy.removeSavedItem(savedItems, id: existing.id)
            flash("已取消书签")
        } else {
            let now = Date().timeIntervalSince1970
            let title = tab.title.isEmpty ? URLPolicy.displayHost(tab.url) : tab.title
            savedItems = LibraryPolicy.addSavedItem(
                savedItems,
                item: SavedItem(
                    id: "saved-\(Int(now * 1000))",
                    title: title,
                    url: tab.url,
                    createdAt: now,
                    updatedAt: now
                )
            )
            flash("已加入书签")
        }
        persistLibrary()
    }

    func removeSavedItems(at offsets: IndexSet) {
        let ids = offsets.compactMap { savedItems.indices.contains($0) ? savedItems[$0].id : nil }
        savedItems = savedItems.filter { !ids.contains($0.id) }
        persistLibrary()
    }

    func removeHistory(at offsets: IndexSet) {
        let ids = offsets.compactMap { history.indices.contains($0) ? history[$0].id : nil }
        history = history.filter { !ids.contains($0.id) }
        persistLibrary()
    }

    func suggestions(for query: String) -> [AddressSuggestion] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let search = URLPolicy.looksLikeURL(trimmed)
            ? ""
            : URLPolicy.searchURL(trimmed, engine: settings.searchEngine)
        return LibraryPolicy.suggestions(
            query: query,
            history: history,
            savedItems: savedItems,
            searchSuggestionsEnabled: settings.searchSuggestionsEnabled && !URLPolicy.looksLikeURL(trimmed),
            searchURL: search
        )
    }

    func goBack() {
        if let controller = activeController {
            controller.goBack()
            return
        }
        openInActiveTab(URLPolicy.homeURL)
    }

    func goForward() {
        activeController?.goForward()
    }

    func openNavigationHistory() {
        navigationHistoryEntries = activeController?.navigationHistory() ?? []
        showsNavigationHistory = true
    }

    func navigateHistory(to offset: Int) {
        activeController?.navigateHistory(to: offset)
        showsNavigationHistory = false
    }

    func reloadOrStop() {
        guard let current = activeTab else {
            return
        }
        if current.isLoading {
            activeController?.stop()
            return
        }
        if URLPolicy.isHomeURL(current.url) {
            return
        }
        activeController?.reload()
    }

    func createTab(isPrivate: Bool, select: Bool = true) {
        guard tabs.count < SessionPolicy.maxTabCount else {
            return
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
    }

    func selectTab(_ id: String) {
        guard tabs.contains(where: { $0.id == id }) else {
            return
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
        if let closing = tab(id), !closing.isPrivate {
            recentlyClosedTabs.insert(closing, at: 0)
            recentlyClosedTabs = Array(recentlyClosedTabs.prefix(10))
        }
        let nextActiveID = activeTabID == id
            ? SessionPolicy.selectedTabAfterClosing(tabs, closing: id)
            : activeTabID
        controllers[id] = nil
        tabs.removeAll { $0.id == id }
        if tabs.isEmpty {
            let home = BrowserTab.home(isPrivate: false)
            tabs = [home]
            activeTabID = home.id
        } else if activeTabID == id {
            activeTabID = nextActiveID ?? tabs[0].id
        }
        recyclePrivateStoreIfNeeded()
        ensureLive(activeTabID)
        persist()
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
        ids.forEach { controllers[$0] = nil }
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
        controllers.removeAll()
        let home = BrowserTab.home(isPrivate: false)
        tabs = [home]
        activeTabID = home.id
        privateStore = WKWebsiteDataStore.nonPersistent()
        persist()
    }

    func toggleReader() {
        guard let current = activeTab, !URLPolicy.isHomeURL(current.url) else {
            return
        }
        if current.isReader {
            activeController?.exitReader()
            update(tabID: current.id) { tab in
                tab.isReader = false
            }
            persist()
            return
        }
        ensureLive(current.id)
        activeController?.applyReader(settings: readerSettings) { [weak self] ok in
            DispatchQueue.main.async {
                guard let self else {
                    return
                }
                if !ok {
                    self.flash("无法提取正文")
                    return
                }
                self.update(tabID: current.id) { tab in
                    tab.isReader = true
                }
                self.persist()
            }
        }
    }

    func refreshReader() {
        guard activeTab?.isReader == true else {
            return
        }
        persistReaderSettings()
        activeController?.applyReader(settings: readerSettings) { _ in }
    }

    func toggleDesktop() {
        guard let current = activeTab, !URLPolicy.isHomeURL(current.url) else {
            return
        }
        let next = !current.isDesktop
        update(tabID: current.id) { tab in
            tab.isDesktop = next
            tab.isReader = false
        }
        ensureLive(current.id)
        activeController?.applyUserAgent(isDesktop: next)
        let target = next ? URLPolicy.desktopURL(for: current.url) : current.url
        activeController?.load(target, rewriteDesktop: next)
        persist()
    }

    func beginFind() {
        guard let current = activeTab, !URLPolicy.isHomeURL(current.url) else {
            return
        }
        showsFind = true
    }

    func updateFindQuery(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            findCurrent = 0
            findTotal = 0
            return
        }
        ensureLive(activeTabID)
        activeController?.countMatches(trimmed) { [weak self] total in
            guard let self else {
                return
            }
            self.findTotal = total
            if total == 0 {
                self.findCurrent = 0
                return
            }
            self.activeController?.find(trimmed, backwards: false) { found in
                self.findCurrent = found ? 1 : 0
            }
        }
    }

    func findNext() {
        let trimmed = findQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard findTotal > 0, !trimmed.isEmpty else {
            return
        }
        activeController?.find(trimmed, backwards: false) { [weak self] found in
            guard let self, found else {
                return
            }
            self.findCurrent = self.findCurrent >= self.findTotal ? 1 : self.findCurrent + 1
        }
    }

    func findPrevious() {
        let trimmed = findQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard findTotal > 0, !trimmed.isEmpty else {
            return
        }
        activeController?.find(trimmed, backwards: true) { [weak self] found in
            guard let self, found else {
                return
            }
            self.findCurrent = self.findCurrent <= 1 ? self.findTotal : self.findCurrent - 1
        }
    }

    func endFind() {
        showsFind = false
        findQuery = ""
        findCurrent = 0
        findTotal = 0
    }

    func setSearchEngine(_ engine: SearchEngine) {
        settings.searchEngine = engine
        persistSettings()
    }

    func openLibrary(_ tab: LibraryTab) {
        libraryTab = tab
        showsLibrary = true
    }

    func setSearchSuggestionsEnabled(_ enabled: Bool) {
        settings.searchSuggestionsEnabled = enabled
        persistSettings()
    }

    func acceptPrivacyConsent() {
        settings.privacyConsentAccepted = true
        persistSettings()
    }

    func finishOnboarding() {
        settings.onboardingCompleted = true
        persistSettings()
    }

    func setAppearance(_ appearance: AppearanceMode) {
        settings.appearance = appearance
        persistSettings()
    }

    func setQuickSitesEnabled(_ enabled: Bool) {
        settings.quickSitesEnabled = enabled
        persistSettings()
    }

    func setQuickSiteLimit(_ limit: Int) {
        settings.quickSiteLimit = BrowserSettings.clampedQuickSiteLimit(limit)
        persistSettings()
    }

    func setHomeBackgroundStyle(_ style: HomeBackgroundStyle) {
        settings.homeBackgroundStyle = style
        persistSettings()
    }

    func setTabExpiry(_ expiry: TabExpiry) {
        settings.tabExpiry = expiry
        persistSettings()
    }

    func setLiveWebViewLimit(_ limit: Int) {
        settings.liveWebViewLimit = BrowserSettings.clampedLiveWebViewLimit(limit)
        trimLive()
        persistSettings()
    }

    func setTabSoftLimit(_ limit: Int) {
        settings.tabSoftLimit = BrowserSettings.clampedTabSoftLimit(limit)
        persistSettings()
    }

    @discardableResult
    func saveQuickSite(title: String, url: String, replacing: QuickSite? = nil) -> Bool {
        guard let site = QuickSitePolicy.normalized(title: title, url: url, replacing: replacing, in: quickSites) else {
            return false
        }
        quickSites = QuickSitePolicy.upsert(quickSites, site: site)
        persistQuickSites()
        return true
    }

    func removeQuickSite(_ id: String) {
        quickSites.removeAll { $0.id == id }
        persistQuickSites()
    }

    func moveQuickSites(from offsets: IndexSet, to destination: Int) {
        quickSites = QuickSitePolicy.move(quickSites, from: offsets, to: destination)
        persistQuickSites()
    }

    func requestSitePermission(
        origin: String,
        kinds: [SitePermissionKind],
        persist: Bool,
        completion: @escaping (Bool) -> Void
    ) {
        if origin.isEmpty || kinds.isEmpty {
            completion(false)
            return
        }
        if permissionReply != nil {
            completion(false)
            return
        }
        let stored = persist ? sitePermissions.first(where: { $0.origin == origin }) : nil
        switch SitePermissionPolicy.decision(stored: stored, kinds: kinds) {
        case .allow:
            completion(true)
        case .deny:
            completion(false)
        case .prompt:
            permissionReply = completion
            permissionPrompt = PermissionPrompt(origin: origin, kinds: kinds, persist: persist)
        }
    }

    func allowPermission() {
        completePermission(true)
    }

    func denyPermission() {
        completePermission(false)
    }

    func denyPermissionIfPending() {
        if permissionReply != nil {
            completePermission(false)
        }
    }

    func removeSitePermission(_ origin: String) {
        sitePermissions.removeAll { $0.origin == origin }
        persistSitePermissions()
    }

    func adsBlockEnabled(for url: String) -> Bool {
        AllowListPolicy.adsBlockEnabled(for: url, hosts: allowedHosts, blockAds: settings.blockAds)
    }

    func isCurrentHostAllowed() -> Bool {
        guard let tab = activeTab else {
            return false
        }
        return AllowListPolicy.isHostAllowed(allowedHosts, URLPolicy.rawHost(tab.url))
    }

    func toggleCurrentHostAllowed() {
        guard let tab = activeTab, !URLPolicy.isHomeURL(tab.url) else {
            return
        }
        let host = URLPolicy.rawHost(tab.url)
        let allowed = !AllowListPolicy.isHostAllowed(allowedHosts, host)
        allowedHosts = AllowListPolicy.setHostAllowed(allowedHosts, host: host, allowed: allowed)
        persistAllowList()
        controllers.values.forEach { $0.applyContentBlocker() }
        activeController?.reload()
        flash(allowed ? "已允许此站点加载广告" : "已对此站点恢复拦截")
    }

    func removeAllowedHost(_ host: String) {
        allowedHosts = AllowListPolicy.setHostAllowed(allowedHosts, host: host, allowed: false)
        persistAllowList()
        controllers.values.forEach { $0.applyContentBlocker() }
        if let tab = activeTab, URLPolicy.rawHost(tab.url) == host {
            activeController?.reload()
        }
    }

    func setBlockAds(_ enabled: Bool) {
        settings.blockAds = enabled
        persistSettings()
        controllers.values.forEach { $0.applyContentBlocker() }
    }

    func shareCurrentPage() {
        guard let tab = activeTab, !URLPolicy.isHomeURL(tab.url) else {
            return
        }
        var items: [Any] = []
        if let url = URL(string: tab.url) {
            items.append(url)
        } else {
            items.append(tab.url)
        }
        if !tab.title.isEmpty {
            items.insert(tab.title, at: 0)
        }
        shareItems = items
        showsShare = true
    }

    func clearBrowsingData() {
        let store = WKWebsiteDataStore.default()
        store.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
            store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: records) {
                DispatchQueue.main.async {
                    self.flash("已清除浏览数据")
                }
            }
        }
        privateStore = WKWebsiteDataStore.nonPersistent()
        history = []
        persistLibrary()
    }

    func persistSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: "browser_settings")
        }
    }

    func flash(_ message: String) {
        notice = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            if self?.notice == message {
                self?.notice = nil
            }
        }
    }

    func persistReaderSettings() {
        if let data = try? JSONEncoder().encode(readerSettings) {
            UserDefaults.standard.set(data, forKey: "reader_settings")
        }
    }

    private func completePermission(_ allowed: Bool) {
        guard let prompt = permissionPrompt else {
            return
        }
        let reply = permissionReply
        permissionReply = nil
        permissionPrompt = nil
        if prompt.persist {
            sitePermissions = SitePermissionPolicy.apply(
                sitePermissions,
                origin: prompt.origin,
                kinds: prompt.kinds,
                decision: allowed ? .allow : .deny
            )
            persistSitePermissions()
        }
        reply?(allowed)
    }

    func persistSitePermissions() {
        if let data = try? JSONEncoder().encode(sitePermissions) {
            UserDefaults.standard.set(data, forKey: "site_permissions")
        }
    }

    func persistAllowList() {
        if let data = try? JSONEncoder().encode(allowedHosts) {
            UserDefaults.standard.set(data, forKey: "allowed_hosts")
        }
    }

    func persistLibrary() {
        if let historyData = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(historyData, forKey: "browser_history")
        }
        if let savedData = try? JSONEncoder().encode(savedItems) {
            UserDefaults.standard.set(savedData, forKey: "browser_saved_items")
        }
    }

    func persistQuickSites() {
        if let data = try? JSONEncoder().encode(quickSites) {
            UserDefaults.standard.set(data, forKey: "browser_quick_sites")
        }
    }

    func persistArchivedTabs() {
        if let data = try? JSONEncoder().encode(archivedTabs) {
            UserDefaults.standard.set(data, forKey: archivedTabsKey)
        }
    }

    func persist() {
        persistSettings()
        persistReaderSettings()
        persistLibrary()
        persistAllowList()
        persistSitePermissions()
        persistQuickSites()
        let persistable = SessionPolicy.persistableTabs(tabs).map { tab -> BrowserTab in
            var copy = tab
            copy.isLoading = false
            copy.progress = 0
            copy.canGoBack = false
            copy.canGoForward = false
            return copy
        }
        let active = persistable.contains(where: { $0.id == activeTabID })
            ? activeTabID
            : persistable.first?.id ?? ""
        let payload = PersistedSession(tabs: persistable, activeTabID: active)
        if let data = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    private func ensureLive(_ id: String) {
        guard let current = tab(id), !URLPolicy.isHomeURL(current.url) else {
            return
        }
        if controllers[id] == nil {
            controllers[id] = makeController(for: current)
        }
        trimLive()
    }

    private func makeController(for tab: BrowserTab) -> TabController {
        let store = tab.isPrivate ? privateStore : WKWebsiteDataStore.default()
        return TabController(tab: tab, session: self, dataStore: store)
    }

    private func trimLive() {
        let live = SessionPolicy.liveTabIDs(
            tabs: tabs,
            activeTabID: activeTabID,
            limit: settings.liveWebViewLimit
        )
        for id in controllers.keys where !SessionPolicy.isTabLive(live, id) {
            if let controller = controllers[id], let url = controller.webView.url?.absoluteString {
                update(tabID: id) { tab in
                    tab.url = url
                    if let title = controller.webView.title, !title.isEmpty {
                        tab.title = title
                    }
                    tab.isLoading = false
                }
            }
            controllers[id] = nil
        }
    }

    private func recyclePrivateStoreIfNeeded() {
        if tabs.contains(where: { $0.isPrivate }) {
            return
        }
        privateStore = WKWebsiteDataStore.nonPersistent()
    }

    private static func restore(settings: BrowserSettings) -> (
        tabs: [BrowserTab],
        activeTabID: String,
        expiredTabs: [BrowserTab]
    )? {
        guard let data = UserDefaults.standard.data(forKey: "browser_session"),
              let payload = try? JSONDecoder().decode(PersistedSession.self, from: data) else {
            return nil
        }
        let partition = SessionPolicy.partitionExpiredTabs(
            SessionPolicy.persistableTabs(payload.tabs),
            expiry: settings.tabExpiry
        )
        let tabs = partition.active
        if tabs.isEmpty {
            return ([], "", partition.expired)
        }
        let active = tabs.contains(where: { $0.id == payload.activeTabID }) ? payload.activeTabID : tabs[0].id
        return (tabs, active, partition.expired)
    }

    private static func loadArchivedTabs() -> [BrowserTab] {
        guard let data = UserDefaults.standard.data(forKey: "browser_archived_tabs"),
              let tabs = try? JSONDecoder().decode([BrowserTab].self, from: data) else {
            return []
        }
        return SessionPolicy.persistableTabs(tabs)
    }

    private static func mergedArchivedTabs(_ existing: [BrowserTab], _ newlyExpired: [BrowserTab]) -> [BrowserTab] {
        var seen = Set<String>()
        return (newlyExpired + existing).filter { seen.insert($0.id).inserted }
    }

    private static func loadSitePermissions() -> [SitePermission] {
        guard let data = UserDefaults.standard.data(forKey: "site_permissions"),
              let items = try? JSONDecoder().decode([SitePermission].self, from: data) else {
            return []
        }
        return items
    }

    private static func loadAllowedHosts() -> [String] {
        guard let data = UserDefaults.standard.data(forKey: "allowed_hosts"),
              let hosts = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return hosts
    }

    private static func loadHistory() -> [HistoryEntry] {
        guard let data = UserDefaults.standard.data(forKey: "browser_history"),
              let items = try? JSONDecoder().decode([HistoryEntry].self, from: data) else {
            return []
        }
        return items
    }

    private static func loadSavedItems() -> [SavedItem] {
        guard let data = UserDefaults.standard.data(forKey: "browser_saved_items"),
              let items = try? JSONDecoder().decode([SavedItem].self, from: data) else {
            return []
        }
        return items
    }

    private static func loadSettings() -> BrowserSettings {
        guard let data = UserDefaults.standard.data(forKey: "browser_settings"),
              let settings = try? JSONDecoder().decode(BrowserSettings.self, from: data) else {
            return BrowserSettings()
        }
        return settings
    }

    private static func loadQuickSites() -> [QuickSite] {
        guard let data = UserDefaults.standard.data(forKey: "browser_quick_sites"),
              let sites = try? JSONDecoder().decode([QuickSite].self, from: data) else {
            return QuickSite.defaults
        }
        return Array(sites.prefix(QuickSitePolicy.maximumCount))
    }

    private static func loadReaderSettings() -> ReaderSettings {
        guard let data = UserDefaults.standard.data(forKey: "reader_settings"),
              let settings = try? JSONDecoder().decode(ReaderSettings.self, from: data) else {
            return ReaderSettings()
        }
        return settings
    }
}
