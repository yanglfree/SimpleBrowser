import Foundation
import SwiftUI
import WebKit

final class BrowserSession: ObservableObject {
    @Published var tabs: [BrowserTab]
    @Published var activeTabID: String
    @Published var showsOverview = false

    private var controllers: [String: TabController] = [:]
    private var privateStore = WKWebsiteDataStore.nonPersistent()
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
        let address = URLPolicy.normalizeAddress(raw)
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

    func persist() {
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
}
