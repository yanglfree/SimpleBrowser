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
    let downloads = DownloadStore()

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

    func persist() {
        persistSettings()
        persistReaderSettings()
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
