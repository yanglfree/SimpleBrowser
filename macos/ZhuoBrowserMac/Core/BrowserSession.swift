import Foundation
import SwiftUI
import WebKit

/// The central state manager for ZhuoBrowser Mac.
/// Manages tab lifecycle, omnibox navigation, and memory budget enforcement.
public final class BrowserSession: ObservableObject {
    public static let shared = BrowserSession()

    @Published public var tabs: [BrowserTab] = []
    @Published public var activeTabID: String?
    @Published public var omniboxText: String = ""
    @Published public var isOmniboxFocused: Bool = false
    @Published public var activeLiveControllersCount: Int = 0
    @Published public private(set) var activeController: TabController?

    public let settings = BrowserSettings.shared
    private var controllers: [String: TabController] = [:]

    public init() {
        // Prepare content blocking rules asynchronously
        ContentBlocker.shared.prepare()

        // Create initial tab
        let initialTab = BrowserTab(url: "zhuo://home", title: "新标签页")
        tabs = [initialTab]
        activeTabID = initialTab.id
        enforceMemoryBudget()
    }

    public var activeTab: BrowserTab? {
        guard let id = activeTabID else { return tabs.first }
        return tabs.first(where: { $0.id == id })
    }

    public func tab(for id: String) -> BrowserTab? {
        tabs.first(where: { $0.id == id })
    }

    public func controller(for id: String) -> TabController? {
        controllers[id]
    }

    // MARK: - Tab Management

    @discardableResult
    public func createTab(url: String = "zhuo://home", isPrivate: Bool = false, select: Bool = true) -> BrowserTab {
        let newTab = BrowserTab(
            url: url,
            title: url == "zhuo://home" ? (isPrivate ? "无痕新标签" : "新标签页") : url,
            isPrivate: isPrivate,
            lastActiveTime: Date()
        )
        tabs.append(newTab)

        if select {
            selectTab(id: newTab.id)
        } else {
            enforceMemoryBudget()
        }
        return newTab
    }

    public func closeTab(id: String) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }

        // Destroy controller if active
        if let controller = controllers[id] {
            controller.destroy()
            controllers.removeValue(forKey: id)
        }

        tabs.remove(at: index)

        // If closed tab was active, select another tab
        if activeTabID == id {
            if tabs.isEmpty {
                createTab()
            } else {
                let nextIndex = min(index, tabs.count - 1)
                selectTab(id: tabs[nextIndex].id)
            }
        } else {
            enforceMemoryBudget()
        }
    }

    public func selectTab(id: String) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].lastActiveTime = Date()
        activeTabID = id

        let currentTab = tabs[index]
        omniboxText = URLPolicy.displayAddress(for: currentTab.url)

        enforceMemoryBudget()
    }

    public func updateTab(_ id: String, mutate: (inout BrowserTab) -> Void) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        mutate(&tabs[index])
        if activeTabID == id {
            omniboxText = URLPolicy.displayAddress(for: tabs[index].url)
        }
    }

    // MARK: - Navigation

    public func navigate(to text: String) {
        let normalizedURL = URLPolicy.normalizeAddress(text, searchEngine: settings.searchEngine)
        guard let activeID = activeTabID, let index = tabs.firstIndex(where: { $0.id == activeID }) else { return }

        tabs[index].url = normalizedURL
        tabs[index].isHibernated = false
        omniboxText = URLPolicy.displayAddress(for: normalizedURL)

        if normalizedURL == "zhuo://home" {
            // Home page: tear down live webview to maximize memory savings
            if let controller = controllers[activeID] {
                controller.destroy()
                controllers.removeValue(forKey: activeID)
            }
            tabs[index].title = tabs[index].isPrivate ? "无痕新标签" : "新标签页"
            activeLiveControllersCount = controllers.count
            activeController = nil
            return
        }

        guard let url = URL(string: normalizedURL) else { return }

        if let controller = controllers[activeID] {
            controller.load(url: url)
        } else {
            let controller = TabController(
                tabID: activeID,
                session: self,
                initialURL: url,
                isPrivate: tabs[index].isPrivate
            )
            controllers[activeID] = controller
        }

        enforceMemoryBudget()
    }

    public func reloadActiveTab() {
        activeController?.reload()
    }

    public func goBackActiveTab() {
        activeController?.goBack()
    }

    public func goForwardActiveTab() {
        activeController?.goForward()
    }

    // MARK: - Memory Budget Enforcement & Hibernation

    public func enforceMemoryBudget() {
        let plan = MemoryBudgetPolicy.evaluate(
            tabs: tabs,
            activeTabID: activeTabID,
            budget: settings.liveWebViewBudget
        )

        // 1. Evict tabs that exceed budget
        for id in plan.tabsToHibernate {
            if let controller = controllers[id] {
                controller.captureScrollPosition { [weak self] scrollY in
                    self?.updateTab(id) { tab in
                        tab.scrollPositionY = scrollY
                    }
                }
                controller.destroy()
                controllers.removeValue(forKey: id)
                updateTab(id) { tab in
                    tab.isHibernated = true
                }
            }
        }

        // 2. Ensure tabs to keep alive have controllers if not on home
        for id in plan.tabsToKeepAlive {
            guard let tab = tab(for: id) else { continue }
            if !tab.isHome && controllers[id] == nil {
                if let url = URL(string: tab.url) {
                    let controller = TabController(
                        tabID: id,
                        session: self,
                        initialURL: url,
                        isPrivate: tab.isPrivate
                    )
                    controllers[id] = controller
                    updateTab(id) { tab in
                        tab.isHibernated = false
                    }
                }
            }
        }

        activeLiveControllersCount = controllers.count
        activeController = activeTabID != nil ? controllers[activeTabID!] : nil
    }
}
