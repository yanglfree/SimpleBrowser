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
    let downloads = DownloadStore()
    private var permissionReply: ((Bool) -> Void)?

    private var controllers: [String: TabController] = [:]
    private var privateStore = WKWebsiteDataStore.nonPersistent()
    private var cancellables: Set<AnyCancellable> = []
    private let defaultsKey = "browser_session"

    var activeTab: BrowserTab? {
        tab(activeTabID)
    }

    var activeController: TabController? {
        controllers[activeTabID]
    }

    init() {
        if let restored = Self.restore() {
            tabs = restored.tabs
            activeTabID = restored.activeTabID
        } else {
            let home = BrowserTab.home(isPrivate: false)
            tabs = [home]
            activeTabID = home.id
        }
        ContentBlocker.shared.onListsChanged = { [weak self] in
            self?.controllers.values.forEach { $0.applyContentBlocker() }
        }
        ContentBlocker.shared.prepare()
        readerSettings = Self.loadReaderSettings()
        settings = Self.loadSettings()
        history = Self.loadHistory()
        savedItems = Self.loadSavedItems()
        allowedHosts = Self.loadAllowedHosts()
        sitePermissions = Self.loadSitePermissions()
        downloads.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        ensureLive(activeTabID)
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
        controllers[id] = nil
        tabs.removeAll { $0.id == id }
        if tabs.isEmpty {
            let home = BrowserTab.home(isPrivate: false)
            tabs = [home]
            activeTabID = home.id
        } else if activeTabID == id {
            activeTabID = tabs[0].id
        }
        recyclePrivateStoreIfNeeded()
        ensureLive(activeTabID)
        persist()
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

    func persist() {
        persistSettings()
        persistReaderSettings()
        persistLibrary()
        persistAllowList()
        persistSitePermissions()
        let persistable = SessionPolicy.persistableTabs(tabs).map { tab -> BrowserTab in
            var copy = tab
            copy.isLoading = false
            copy.progress = 0
            copy.canGoBack = false
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
        let live = SessionPolicy.liveTabIDs(tabs: tabs, activeTabID: activeTabID, limit: SessionPolicy.liveWebViewLimit)
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

    private static func restore() -> (tabs: [BrowserTab], activeTabID: String)? {
        guard let data = UserDefaults.standard.data(forKey: "browser_session"),
              let payload = try? JSONDecoder().decode(PersistedSession.self, from: data) else {
            return nil
        }
        let tabs = SessionPolicy.persistableTabs(payload.tabs)
        if tabs.isEmpty {
            return nil
        }
        let active = tabs.contains(where: { $0.id == payload.activeTabID }) ? payload.activeTabID : tabs[0].id
        return (tabs, active)
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

    private static func loadReaderSettings() -> ReaderSettings {
        guard let data = UserDefaults.standard.data(forKey: "reader_settings"),
              let settings = try? JSONDecoder().decode(ReaderSettings.self, from: data) else {
            return ReaderSettings()
        }
        return settings
    }
}
