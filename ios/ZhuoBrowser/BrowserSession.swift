import Combine
import Foundation
import SwiftUI
import UIKit
import UserNotifications
import WebKit

@MainActor
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
    @Published var showsArticles = false
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
    @Published var pageResumeRequest: PageResumeRequest?
    @Published var showsProPaywall = false
    @Published var showsSecurityPanel = false
    @Published var showsPageSettings = false
    @Published var showsBlockPanel = false
    @Published var isRulesUpdating = false
    @Published var tabBlockStats: [String: BlockStats] = [:]
    @Published var blockEvents: [BlockEvent] = []
    @Published var siteBlockStats: [SiteBlockStats] = []
    @Published var securityWarning: SiteSecurityWarning?
    @Published var externalProtocolRequest: ExternalProtocolRequest?
    let downloads = DownloadStore()
    let articles = ArticleStore()
    let pro = ProBillingService()
    private var permissionReply: ((Bool) -> Void)?

    private var controllers: [String: TabController] = [:]
    private var privateStore = WKWebsiteDataStore.nonPersistent()
    private var recentlyClosedTabs: [BrowserTab] = []
    private var cancellables: Set<AnyCancellable> = []
    private var resumePromptGeneration = 0
    private let defaultsKey = "browser_session"
    private let archivedTabsKey = "browser_archived_tabs"
    private let siteBlockStatsKey = "browser_site_block_stats"

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
        tabs = tabs.map { tab in
            var resolved = tab
            if !URLPolicy.isHomeURL(tab.url) {
                resolved.isDesktop = WebAppearancePolicy.usesDesktopUserAgent(
                    for: tab.url,
                    settings: loadedSettings
                )
            }
            return resolved
        }
        downloads.configure(settings: loadedSettings)
        downloads.onCompletion = { [weak self] task in
            self?.flash("\(task.fileName) 下载完成")
        }
        downloads.onFailure = { [weak self] task in
            self?.flash("\(task.fileName) 下载失败")
        }
        history = LibraryPolicy.applyingHistoryRetention(
            Self.loadHistory(),
            retentionDays: loadedSettings.historyRetention.rawValue
        )
        savedItems = Self.loadSavedItems()
        allowedHosts = Self.loadAllowedHosts()
        sitePermissions = Self.loadSitePermissions()
        quickSites = Self.loadQuickSites()
        siteBlockStats = Self.loadSiteBlockStats()
        persistArchivedTabs()
        showsExpiredTabsPrompt = !archivedTabs.isEmpty
        downloads.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        articles.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        pro.objectWillChange
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
        let usesDesktop = WebAppearancePolicy.usesDesktopUserAgent(for: address, settings: settings)
        prepareNavigation(tabID: activeTabID, to: address)
        update(tabID: activeTabID) { tab in
            tab.url = address
            tab.lastVisitedAt = Date().timeIntervalSince1970
            tab.isDesktop = usesDesktop
        }
        if URLPolicy.isHomeURL(address) {
            persist()
            return
        }
        if let controller = controllers[activeTabID] {
            controller.applyUserAgent(isDesktop: usesDesktop)
            controller.applyWebAppearance(for: address)
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
            ),
            retentionDays: settings.historyRetention.rawValue
        )
        savedItems = LibraryPolicy.markSavedItemRead(savedItems, url: tab.url)
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

    func removeSavedItem(_ id: String) {
        savedItems = LibraryPolicy.removeSavedItem(savedItems, id: id)
        persistLibrary()
    }

    func renameSavedItem(_ id: String, title: String) {
        savedItems = LibraryPolicy.renameSavedItem(savedItems, id: id, title: title)
        persistLibrary()
    }

    func saveCurrentPageForLater() {
        guard let tab = activeTab, !tab.isPrivate, !URLPolicy.isHomeURL(tab.url) else {
            return
        }
        savedItems = LibraryPolicy.saveForLater(
            savedItems,
            url: tab.url,
            title: tab.displayTitle
        )
        persistLibrary()
        flash("已加入稍后读")
    }

    func isCurrentPageSavedForLater() -> Bool {
        guard let tab = activeTab else {
            return false
        }
        return LibraryPolicy.isSavedForLater(savedItems, url: tab.url)
    }

    func removeHistoryEntry(_ id: String) {
        history.removeAll { $0.id == id }
        persistLibrary()
    }

    func removeHistory(forHost host: String) {
        history = LibraryPolicy.removeHistoryForHost(history, host: host)
        persistLibrary()
    }

    @discardableResult
    func importBookmarks(_ data: Data) throws -> Int {
        let imported = try BookmarkTransfer.parse(data)
        let result = LibraryPolicy.mergeSavedItems(savedItems, imported: imported)
        savedItems = result.items
        persistLibrary()
        return result.importedCount
    }

    func bookmarkExportHTML() -> String {
        BookmarkTransfer.export(savedItems)
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
        if activeTabID != id {
            capturePageState(activeTabID)
        }
        dismissPageResume()
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

    private func finishClosingTab(_ id: String) {
        guard let closingTab = tab(id) else {
            return
        }
        if !closingTab.isPrivate {
            recentlyClosedTabs.insert(closingTab, at: 0)
            recentlyClosedTabs = Array(recentlyClosedTabs.prefix(10))
        }
        let nextActiveID = activeTabID == id
            ? SessionPolicy.selectedTabAfterClosing(tabs, closing: id)
            : activeTabID
        controllers[id] = nil
        tabBlockStats[id] = nil
        blockEvents.removeAll { $0.tabID == id }
        tabs.removeAll { $0.id == id }
        if tabs.isEmpty {
            let home = BrowserTab.home(isPrivate: false)
            tabs = [home]
            activeTabID = home.id
        } else if activeTabID == id {
            activeTabID = nextActiveID ?? tabs[0].id
        }
        dismissPageResume()
        recyclePrivateStoreIfNeeded()
        ensureLive(activeTabID)
        persist()
        if !closingTab.isPrivate && settings.clearCookiesOnTabClose {
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
        let shouldClearCookies = settings.clearCookiesOnTabClose && tabs.contains { !$0.isPrivate }
        dismissPageResume()
        controllers.removeAll()
        let home = BrowserTab.home(isPrivate: false)
        tabs = [home]
        activeTabID = home.id
        privateStore = WKWebsiteDataStore.nonPersistent()
        persist()
        if shouldClearCookies {
            clearCookies()
        }
    }

    func toggleReader() {
        guard let current = activeTab, !URLPolicy.isHomeURL(current.url) else {
            return
        }
        if current.isReader {
            capturePageState(current.id)
            guard let controller = controllers[current.id] else {
                return
            }
            controller.exitReader { [weak self] in
                guard let self else {
                    return
                }
                self.update(tabID: current.id) { tab in
                    tab.isReader = false
                }
                self.restoreStoredScroll(tabID: current.id, promptIfActive: false)
                self.persist()
            }
            return
        }
        capturePageState(current.id)
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
                self.restoreStoredScroll(tabID: current.id, promptIfActive: true)
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

    func applyUserAgentOnce(_ preference: UserAgentPreference) {
        guard let current = activeTab, !URLPolicy.isHomeURL(current.url) else {
            return
        }
        let next = preference == .desktop
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

    func setSiteUserAgentPreference(_ preference: UserAgentPreference) {
        guard let current = activeTab else {
            return
        }
        let host = WebAppearancePolicy.host(for: current.url)
        guard !host.isEmpty else {
            return
        }
        settings.siteUserAgentPreferences.removeAll { $0.host == host }
        if preference != .default {
            settings.siteUserAgentPreferences.append(
                SiteUserAgentPreference(host: host, preference: preference)
            )
        }
        settings.siteUserAgentPreferences = WebAppearancePolicy.normalizedUserAgentPreferences(
            settings.siteUserAgentPreferences
        )
        persistSettings()
        applyResolvedUserAgentToActive()
    }

    func setDefaultUserAgentPreference(_ preference: UserAgentPreference) {
        settings.defaultUserAgentPreference = preference
        persistSettings()
        applyResolvedUserAgentToActive()
    }

    func resetUserAgentPreferences() {
        settings.defaultUserAgentPreference = .default
        settings.siteUserAgentPreferences = []
        persistSettings()
        applyResolvedUserAgentToActive()
    }

    func userAgentPreference(for rawURL: String) -> UserAgentPreference {
        WebAppearancePolicy.userAgentPreference(for: rawURL, settings: settings)
    }

    func siteUserAgentPreference(for rawURL: String) -> UserAgentPreference {
        let host = WebAppearancePolicy.host(for: rawURL)
        return settings.siteUserAgentPreferences.first(where: { $0.host == host })?.preference ?? .default
    }

    func setMinimumFontSize(_ size: Int) {
        settings.minimumFontSize = BrowserSettings.clampedMinimumFontSize(size)
        persistSettings()
        controllers.values.forEach { $0.applyWebAppearance() }
        activeController?.reload()
    }

    func setWebDarkMode(_ preference: WebDarkModePreference) {
        settings.webDarkMode = preference
        persistSettings()
        controllers.values.forEach { $0.applyWebAppearance() }
    }

    func isWebDarkModeExcluded(for rawURL: String) -> Bool {
        WebAppearancePolicy.isDarkModeExcluded(for: rawURL, settings: settings)
    }

    func setCurrentSiteDarkModeExcluded(_ excluded: Bool) {
        guard let current = activeTab else {
            return
        }
        let host = WebAppearancePolicy.host(for: current.url)
        guard !host.isEmpty else {
            return
        }
        settings.webDarkModeExcludedHosts.removeAll { $0 == host }
        if excluded {
            settings.webDarkModeExcludedHosts.append(host)
        }
        settings.webDarkModeExcludedHosts = WebAppearancePolicy.normalizedHosts(
            settings.webDarkModeExcludedHosts
        )
        persistSettings()
        activeController?.applyWebAppearance()
    }

    func zoomPercent(for rawURL: String) -> Int {
        WebAppearancePolicy.zoomPercent(for: rawURL, settings: settings)
    }

    func setCurrentSiteZoom(_ percent: Int) {
        guard let current = activeTab else {
            return
        }
        let host = WebAppearancePolicy.host(for: current.url)
        guard !host.isEmpty else {
            return
        }
        settings.siteZoomRatios.removeAll { $0.host == host }
        let clamped = WebAppearancePolicy.clampedZoomPercent(percent)
        if clamped != 100 {
            settings.siteZoomRatios.append(SiteZoomRatio(host: host, percent: clamped))
        }
        settings.siteZoomRatios = WebAppearancePolicy.normalizedZoomRatios(settings.siteZoomRatios)
        persistSettings()
        activeController?.applyWebAppearance()
    }

    private func applyResolvedUserAgentToActive() {
        guard let current = activeTab, !URLPolicy.isHomeURL(current.url) else {
            return
        }
        let preference = userAgentPreference(for: current.url)
        applyUserAgentOnce(preference == .desktop ? .desktop : .mobile)
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

    func setHistoryRetention(_ retention: HistoryRetention) {
        settings.historyRetention = retention
        history = LibraryPolicy.applyingHistoryRetention(
            history,
            retentionDays: retention.rawValue
        )
        persistSettings()
        persistLibrary()
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

    func setDownloadConcurrency(_ limit: Int) {
        settings.downloadConcurrency = BrowserSettings.clampedDownloadConcurrency(limit)
        persistDownloadSettings()
    }

    func setLargeDownloadThresholdMB(_ threshold: Int) {
        settings.largeDownloadThresholdMB = BrowserSettings.clampedLargeDownloadThresholdMB(threshold)
        persistDownloadSettings()
    }

    func setWifiOnlyDownloads(_ enabled: Bool) {
        settings.wifiOnlyDownloads = enabled
        persistDownloadSettings()
    }

    func setDownloadNotificationsEnabled(_ enabled: Bool) {
        guard enabled else {
            settings.downloadNotificationsEnabled = false
            persistDownloadSettings()
            return
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.settings.downloadNotificationsEnabled = granted
                self.persistDownloadSettings()
                if !granted {
                    self.flash("未获得通知权限")
                }
            }
        }
    }

    func setClearCookiesOnTabClose(_ enabled: Bool) {
        settings.clearCookiesOnTabClose = enabled
        persistSettings()
    }

    func retryDownload(_ id: String) {
        downloads.retry(id, using: activeController?.webView)
    }

    private func persistDownloadSettings() {
        downloads.configure(settings: settings)
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
        let effective = BlockingPolicy.effectiveControl(for: url, settings: settings)
        return effective.networkBlockingEnabled && effective.trackerBlockingEnabled &&
            !AllowListPolicy.isHostAllowed(allowedHosts, URLPolicy.rawHost(url))
    }

    func effectiveSiteControl(for url: String) -> EffectiveSiteControl {
        BlockingPolicy.effectiveControl(for: url, settings: settings)
    }

    func isBlockingAllowListed(for url: String) -> Bool {
        AllowListPolicy.isHostAllowed(allowedHosts, URLPolicy.rawHost(url))
    }

    func currentSiteControl() -> SiteControl {
        BlockingPolicy.siteControl(for: activeTab?.url ?? "", controls: settings.siteControls)
    }

    func setCurrentSiteControl(_ control: SiteControl) {
        let host = URLPolicy.rawHost(activeTab?.url ?? "").lowercased()
        guard !host.isEmpty else { return }
        var normalized = control
        normalized.host = host
        settings.siteControls.removeAll { $0.host == host }
        if normalized.hasOverride {
            settings.siteControls.append(normalized)
        }
        settings.siteControls = BlockingPolicy.normalizedSiteControls(settings.siteControls)
        persistSettings()
        controllers.values.forEach { $0.applyContentBlocker() }
        activeController?.reload()
    }

    func setRuleStrength(_ strength: RuleStrength) {
        guard settings.ruleStrength != strength else { return }
        settings.ruleStrength = strength
        persistSettings()
        activeController?.reload()
    }

    func reloadBundledRules() {
        guard !isRulesUpdating else { return }
        isRulesUpdating = true
        ContentBlocker.shared.reloadBundledRules { [weak self] success in
            guard let self else { return }
            self.isRulesUpdating = false
            if success {
                self.settings.rulesLastUpdatedAt = Date().timeIntervalSince1970
                self.persistSettings()
                self.flash("内置拦截规则已重新加载")
            } else {
                self.flash("内置拦截规则加载失败")
            }
        }
    }

    func recordObservedBlocking(tabID: String, url: String, stats: BlockStats) {
        guard stats.total > 0, PageStatePolicy.isSamePage(tab(tabID)?.url ?? "", url) else { return }
        var tabStats = tabBlockStats[tabID] ?? BlockStats()
        tabStats.add(stats)
        tabBlockStats[tabID] = tabStats
        let now = Date()
        let categories: [(BlockCategory, Int)] = [
            (.advertisement, stats.ads), (.tracker, stats.trackers),
            (.popup, stats.popups), (.cookieBanner, stats.cookieBanners)
        ]
        for (category, count) in categories where count > 0 {
            blockEvents.insert(
                BlockEvent(
                    id: UUID().uuidString,
                    tabID: tabID,
                    pageURL: url,
                    category: category,
                    count: count,
                    occurredAt: now
                ),
                at: 0
            )
        }
        blockEvents = Array(blockEvents.prefix(200))
        guard tab(tabID)?.isPrivate == false else { return }
        let host = URLPolicy.rawHost(url).lowercased()
        guard !host.isEmpty else { return }
        var entries = siteBlockStats
        if let index = entries.firstIndex(where: { $0.host == host }) {
            entries[index].stats.add(stats)
        } else {
            entries.append(SiteBlockStats(host: host, stats: stats))
        }
        siteBlockStats = BlockingPolicy.normalizedSiteStats(entries)
        persistSiteBlockStats()
    }

    func observedStatsForActiveTab() -> BlockStats {
        tabBlockStats[activeTabID] ?? BlockStats()
    }

    func observedStatsForCurrentSite() -> BlockStats {
        let host = URLPolicy.rawHost(activeTab?.url ?? "").lowercased()
        return siteBlockStats.first(where: { $0.host == host })?.stats ?? BlockStats()
    }

    func observedEventsForActiveTab() -> [BlockEvent] {
        blockEvents.filter { $0.tabID == activeTabID }
    }

    func resetObservedBlocking(tabID: String) {
        tabBlockStats[tabID] = BlockStats()
        blockEvents.removeAll { $0.tabID == tabID }
    }

    func applyAutomaticReaderIfNeeded(tabID: String) {
        guard let current = tab(tabID), !current.isReader,
              effectiveSiteControl(for: current.url).autoReaderEnabled,
              let controller = controllers[tabID] else { return }
        controller.applyReader(settings: readerSettings) { [weak self] success in
            guard let self, success else { return }
            self.update(tabID: tabID) { $0.isReader = true }
            self.persist()
        }
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
        activeController?.reload()
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

    func copyCurrentLink() {
        guard let tab = activeTab, !URLPolicy.isHomeURL(tab.url), let url = URL(string: tab.url) else {
            return
        }
        UIPasteboard.general.url = url
        flash("链接已复制")
    }

    func visitClipboardLink() {
        guard let value = UIPasteboard.general.string,
              let address = ExternalProtocolPolicy.clipboardAddress(from: value, engine: settings.searchEngine) else {
            flash("剪贴板中没有可访问的网页链接")
            return
        }
        openInActiveTab(address)
    }

    func handleExternalNavigation(_ rawURL: String, sourceURL: String) -> Bool {
        switch ExternalProtocolPolicy.decision(for: rawURL, sourceURL: sourceURL) {
        case .allow:
            return false
        case .blocked:
            flash("已阻止不安全的外部协议")
            return true
        case let .confirm(request):
            externalProtocolRequest = request
            return true
        }
    }

    func openExternalProtocol(_ request: ExternalProtocolRequest) {
        guard let url = URL(string: request.url) else {
            externalProtocolRequest = nil
            return
        }
        externalProtocolRequest = nil
        UIApplication.shared.open(url, options: [:]) { [weak self] opened in
            guard !opened else { return }
            DispatchQueue.main.async {
                self?.flash("没有可处理此链接的应用")
            }
        }
    }

    func cancelPendingExternalProtocol() {
        externalProtocolRequest = nil
    }

    func captureCurrentArticle() {
        guard pro.isPro else {
            showsProPaywall = true
            flash("保存离线文章需要卓阅 Pro")
            return
        }
        guard let tab = activeTab,
              !tab.isPrivate,
              !URLPolicy.isHomeURL(tab.url),
              let webView = activeController?.webView else {
            return
        }
        let expectedURL = tab.url
        Task { [weak self, weak webView] in
            guard let self, let webView else { return }
            do {
                let snapshot = try await ArticleCapture.capture(from: webView)
                guard PageStatePolicy.isSamePage(expectedURL, snapshot.sourceUrl) else {
                    self.flash("页面已变化，请重新保存")
                    return
                }
                let article = try await self.articles.save(snapshot)
                let suffix = article.quality == .partial ? "，部分图片未保存" : ""
                self.flash("已保存离线文章\(suffix)")
            } catch {
                self.flash(error.localizedDescription)
            }
        }
    }

    func clearBrowsingData(_ selection: BrowsingDataSelection) {
        guard selection.hasSelection else {
            return
        }
        if selection.history {
            let cutoff = BrowsingPrivacyPolicy.cutoff(for: selection.range).timeIntervalSince1970
            history.removeAll { $0.visitedAt >= cutoff }
            persistLibrary()
        }
        if selection.permissions {
            allowedHosts = []
            sitePermissions = []
            settings.siteControls = []
            persistAllowList()
            persistSitePermissions()
            persistSettings()
            controllers.values.forEach { $0.applyContentBlocker() }
        }
        var dataTypes = Set<String>()
        if selection.cookies {
            dataTypes.formUnion(Self.cookieAndStorageDataTypes)
        }
        if selection.cache {
            dataTypes.formUnion(Self.cacheDataTypes)
        }
        guard !dataTypes.isEmpty else {
            flash("已清除所选浏览数据")
            return
        }
        let store = WKWebsiteDataStore.default()
        store.removeData(ofTypes: dataTypes, modifiedSince: .distantPast) {
            DispatchQueue.main.async {
                self.flash("已清除所选浏览数据")
            }
        }
    }

    func clearCurrentSiteData() {
        guard let tab = activeTab else { return }
        let host = URLPolicy.rawHost(tab.url)
        guard !host.isEmpty else { return }
        history = LibraryPolicy.removeHistoryForHost(history, host: host)
        allowedHosts.removeAll { $0.caseInsensitiveCompare(host) == .orderedSame }
        sitePermissions.removeAll { permission in
            guard let permissionHost = URL(string: permission.origin)?.host else { return false }
            return permissionHost.caseInsensitiveCompare(host) == .orderedSame
        }
        settings.siteControls.removeAll { $0.host == host.lowercased() }
        siteBlockStats.removeAll { $0.host == host.lowercased() }
        persistLibrary()
        persistAllowList()
        persistSitePermissions()
        persistSettings()
        persistSiteBlockStats()
        controllers.values.forEach { $0.applyContentBlocker() }

        let store = WKWebsiteDataStore.default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        store.fetchDataRecords(ofTypes: types) { records in
            let matching = records.filter {
                BrowsingPrivacyPolicy.recordDisplayName($0.displayName, matches: host)
            }
            store.removeData(ofTypes: types, for: matching) {
                DispatchQueue.main.async {
                    self.activeController?.reload()
                    self.showsSecurityPanel = false
                    self.flash("已清除 \(host) 的站点数据")
                }
            }
        }
    }

    func openSecurityPanel() {
        guard let tab = activeTab, !URLPolicy.isHomeURL(tab.url) else { return }
        showsSecurityPanel = true
    }

    func handlePasswordFocus(tabID: String, url: String) {
        guard tabID == activeTabID,
              PageStatePolicy.isSamePage(tab(tabID)?.url ?? "", url),
              SiteSecurityPolicy.shouldWarnForPasswordFocus(on: url) else {
            return
        }
        securityWarning = SiteSecurityWarning(host: URLPolicy.displayHost(url))
    }

    private func clearCookies() {
        WKWebsiteDataStore.default().removeData(
            ofTypes: [WKWebsiteDataTypeCookies],
            modifiedSince: .distantPast
        ) {}
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

    func captureActivePageState() {
        capturePageState(activeTabID)
    }

    func prepareNavigation(tabID: String, to url: String) {
        guard let current = tab(tabID), !PageStatePolicy.isSamePage(current.url, url) else {
            return
        }
        dismissPageResume()
        resetObservedBlocking(tabID: tabID)
        update(tabID: tabID) { tab in
            tab.scrollY = 0
            tab.readerScrollY = 0
            tab.scrollSavedAt = 0
            tab.readerScrollSavedAt = 0
            tab.formDraft = ""
        }
    }

    func restorePageStateAfterLoad(tabID: String) {
        guard let current = tab(tabID), let controller = controllers[tabID] else {
            return
        }
        controller.restoreFormDraft(current.formDraft)
        restoreStoredScroll(tabID: tabID, promptIfActive: true)
    }

    func updateCapturedFormDraft(tabID: String, url: String, rawDraft: String) {
        guard let current = tab(tabID),
              !URLPolicy.isHomeURL(current.url),
              PageStatePolicy.isSamePage(current.url, url) else {
            return
        }
        let normalized = PageStatePolicy.normalizedFormDraft(rawDraft)
        guard normalized != current.formDraft else {
            return
        }
        update(tabID: tabID) { tab in
            tab.formDraft = normalized
        }
        persist()
    }

    func continuePageResume() {
        guard let request = pageResumeRequest,
              request.tabID == activeTabID,
              let controller = controllers[request.tabID] else {
            dismissPageResume()
            return
        }
        controller.restoreScrollPosition(request.position)
        dismissPageResume()
    }

    func startPageResumeFromTop() {
        guard let request = pageResumeRequest else {
            return
        }
        update(tabID: request.tabID) { tab in
            if request.isReader {
                tab.readerScrollY = 0
                tab.readerScrollSavedAt = 0
            } else {
                tab.scrollY = 0
                tab.scrollSavedAt = 0
            }
        }
        dismissPageResume()
        persist()
    }

    func dismissPageResume() {
        resumePromptGeneration += 1
        pageResumeRequest = nil
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

    private func persistSiteBlockStats() {
        let limited = Array(siteBlockStats.sorted { $0.stats.total > $1.stats.total }.prefix(500))
        if let data = try? JSONEncoder().encode(limited) {
            UserDefaults.standard.set(data, forKey: siteBlockStatsKey)
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
            capturePageState(id)
            controllers[id] = nil
        }
    }

    private func capturePageState(_ id: String) {
        guard let current = tab(id),
              !URLPolicy.isHomeURL(current.url),
              let controller = controllers[id] else {
            return
        }
        let capturedURL = current.url
        let position = controller.currentScrollPosition()
        let savedAt = Date().timeIntervalSince1970
        update(tabID: id) { tab in
            if tab.isReader {
                tab.readerScrollY = position
                tab.readerScrollSavedAt = savedAt
            } else {
                tab.scrollY = position
                tab.scrollSavedAt = savedAt
            }
        }
        persist()
        controller.captureFormDraft { [weak self] rawDraft in
            guard let self else { return }
            if let latest = self.tab(id), PageStatePolicy.isSamePage(latest.url, capturedURL) {
                self.update(tabID: id) { tab in
                    tab.formDraft = PageStatePolicy.normalizedFormDraft(rawDraft)
                }
                self.persist()
            }
        }
    }

    private func restoreStoredScroll(tabID: String, promptIfActive: Bool) {
        guard let current = tab(tabID), let controller = controllers[tabID] else {
            return
        }
        let position = current.isReader ? current.readerScrollY : current.scrollY
        let savedAt = current.isReader ? current.readerScrollSavedAt : current.scrollSavedAt
        guard PageStatePolicy.shouldOfferResume(position: position, savedAt: savedAt) else {
            if position > 0 || savedAt > 0 {
                update(tabID: tabID) { tab in
                    if tab.isReader {
                        tab.readerScrollY = 0
                        tab.readerScrollSavedAt = 0
                    } else {
                        tab.scrollY = 0
                        tab.scrollSavedAt = 0
                    }
                }
                persist()
            }
            return
        }
        if promptIfActive && tabID == activeTabID {
            pageResumeRequest = PageResumeRequest(tabID: tabID, position: position, isReader: current.isReader)
            schedulePageResumeDismissal(tabID: tabID)
            return
        }
        controller.restoreScrollPosition(position)
    }

    private func schedulePageResumeDismissal(tabID: String) {
        resumePromptGeneration += 1
        let generation = resumePromptGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + PageStatePolicy.resumePromptDuration) { [weak self] in
            guard let self,
                  self.resumePromptGeneration == generation,
                  self.pageResumeRequest?.tabID == tabID else {
                return
            }
            self.pageResumeRequest = nil
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

    private static func loadSiteBlockStats() -> [SiteBlockStats] {
        guard let data = UserDefaults.standard.data(forKey: "browser_site_block_stats"),
              let entries = try? JSONDecoder().decode([SiteBlockStats].self, from: data) else {
            return []
        }
        return BlockingPolicy.normalizedSiteStats(entries)
    }

    private static func loadReaderSettings() -> ReaderSettings {
        guard let data = UserDefaults.standard.data(forKey: "reader_settings"),
              let settings = try? JSONDecoder().decode(ReaderSettings.self, from: data) else {
            return ReaderSettings()
        }
        return settings
    }

    private static let cookieAndStorageDataTypes: Set<String> = [
        WKWebsiteDataTypeCookies,
        WKWebsiteDataTypeSessionStorage,
        WKWebsiteDataTypeLocalStorage,
        WKWebsiteDataTypeWebSQLDatabases,
        WKWebsiteDataTypeIndexedDBDatabases
    ]

    private static let cacheDataTypes: Set<String> = [
        WKWebsiteDataTypeDiskCache,
        WKWebsiteDataTypeMemoryCache,
        WKWebsiteDataTypeOfflineWebApplicationCache
    ]
}
