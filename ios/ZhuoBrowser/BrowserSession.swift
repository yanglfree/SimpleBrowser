import Combine
import Foundation
import SwiftUI
import UIKit
import WebKit

@MainActor
final class BrowserSession: ObservableObject {
    @Published var tabs: [BrowserTab]
    @Published var activeTabID: String
    @Published var showsOverview = false
    @Published var showsRecentTabs = false
    @Published var showsFind = false
    @Published var findQuery = ""
    @Published var findCurrent = 0
    @Published var findTotal = 0
    @Published var readerSettings = ReaderSettings()
    @Published var notice: String?
    @Published var settings = BrowserSettings()
    @Published var showsSettings = false
    @Published var settingsInitialSection: SettingsSection? = nil
    @Published var showsDownloads = false
    @Published var showsArticles = false
    @Published var pendingArticleSelectionID: String? = nil
    @Published var showsShare = false
    @Published var shareItems: [Any] = []
    @Published var isGeneratingScreenshot = false
    @Published var showsLibrary = false
    @Published var libraryTab: LibraryTab = .bookmarks
    @Published var history: [HistoryEntry] = []
    @Published var savedItems: [SavedItem] = []
    @Published var bookmarkFolders: [BookmarkFolder] = []
    @Published var bookmarkTombstones: [BookmarkTombstone] = []
    @Published var articleTombstones: [ArticleTombstone] = []
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
    @Published var pageIssueDiagnostic: PageIssueDiagnostic?
    @Published var activeJsDialog: PendingJsDialog?
    @Published var activeHttpAuth: PendingHttpAuth?
    @Published var paneState = BrowserPaneState(primaryTabID: "")
    @Published var homeBackgroundImage: UIImage?
    @Published var isHomeBackgroundLoading = false
    @Published private(set) var siteIcons: [String: UIImage] = [:]
    @Published private(set) var tabThumbnails: [String: UIImage] = [:]

    let downloads = DownloadStore()
    let articles = ArticleStore()
    let pro = ProBillingService()
    let persistence: BrowserPersistenceStore
    let sessionID = UUID().uuidString
    let isPrimaryWindow: Bool
    let acceptedWindowRequestID: String?

    var permissionReply: ((Bool) -> Void)?
    var controllers: [String: TabController] = [:]
    var privateStore = WKWebsiteDataStore.nonPersistent()
    var recentlyClosedTabs: [BrowserTab] = []
    var disposableReaderTabIDs: Set<String> = []
    var pendingArticleCaptureTabIDs: Set<String> = []
    var pendingWindowTransferIDs: Set<String> = []
    var importWebViews: [String: WKWebView] = [:]
    var siteIconLoadingHosts: Set<String> = []
    var deferredSiteIconRequests: [String: (pageURL: String, declaredURL: String)] = [:]
    var tabThumbnailTokens: [String: UUID] = [:]
    var lastWebProcessTerminationAt: [String: TimeInterval] = [:]
    var cancellables: Set<AnyCancellable> = []
    var resumePromptGeneration = 0

    var activeTab: BrowserTab? {
        tab(activeTabID)
    }

    var activeController: TabController? {
        controllers[activeTabID]
    }

    var canReopenRecentlyClosedTab: Bool {
        !recentlyClosedTabs.isEmpty && tabs.count < SessionPolicy.maxTabCount
    }

    var recentTabs: [BrowserTab] {
        SessionPolicy.recentTabs(tabs, activeTabID: activeTabID)
    }

    var existingTabIDs: Set<String> {
        Set(tabs.map(\.id))
    }

    var isSplitActive: Bool {
        paneState.isSplit(existingTabIDs: existingTabIDs)
    }

    var splitTabIDs: (primary: String, secondary: String)? {
        guard isSplitActive, let secondary = paneState.secondaryTabID else { return nil }
        return (paneState.primaryTabID, secondary)
    }

    init(
        windowRequest: BrowserWindowRequest? = nil,
        isPrimaryWindow: Bool = true,
        persistence: BrowserPersistenceStore = .shared
    ) {
        let initializationStartedAt = ProcessInfo.processInfo.systemUptime
        self.isPrimaryWindow = isPrimaryWindow
        self.persistence = persistence
        let decodedTransfer = windowRequest?.tab
        acceptedWindowRequestID = decodedTransfer == nil ? nil : windowRequest?.id
        let loadedSettings = persistence.load(.settings, as: BrowserSettings.self) { BrowserSettings() }

        if var transferredTab = decodedTransfer {
            transferredTab.isLoading = false
            transferredTab.progress = 0
            transferredTab.canGoBack = false
            transferredTab.canGoForward = false
            tabs = [transferredTab]
            activeTabID = transferredTab.id
            archivedTabs = []
        } else if isPrimaryWindow, let restored = Self.restore(settings: loadedSettings, persistence: persistence) {
            if restored.tabs.isEmpty {
                let home = BrowserTab.home(isPrivate: false)
                tabs = [home]
                activeTabID = home.id
            } else {
                tabs = restored.tabs
                activeTabID = restored.activeTabID
            }
            let existingArchived = Self.loadArchivedTabs(persistence: persistence)
            archivedTabs = Self.mergedArchivedTabs(existingArchived, restored.expiredTabs)
        } else {
            let home = BrowserTab.home(isPrivate: false)
            tabs = [home]
            activeTabID = home.id
            archivedTabs = isPrimaryWindow ? Self.loadArchivedTabs(persistence: persistence) : []
        }

        paneState = BrowserPaneState(primaryTabID: activeTabID)
        bindNotifications()

        readerSettings = persistence.load(.readerSettings, as: ReaderSettings.self) { ReaderSettings() }
        settings = loadedSettings
        tabs = tabs.map { tab in
            var resolved = tab
            if !URLPolicy.isHomeURL(tab.url) {
                resolved.isDesktop = BlockingPolicy.effectiveControl(
                    for: tab.url,
                    settings: loadedSettings
                ).desktopUserAgentEnabled
            }
            return resolved
        }

        configureSubStores(settings: loadedSettings)
        history = LibraryPolicy.applyingHistoryRetention(
            persistence.load(.history, as: [HistoryEntry].self) { [] },
            retentionDays: loadedSettings.historyRetention.rawValue
        )
        savedItems = persistence.load(.savedItems, as: [SavedItem].self) { [] }
        bookmarkFolders = persistence.load(.bookmarkFolders, as: [BookmarkFolder].self) { [] }
        bookmarkTombstones = persistence.load(.bookmarkTombstones, as: [BookmarkTombstone].self) { [] }
        articleTombstones = persistence.load(.articleTombstones, as: [ArticleTombstone].self) { [] }
        allowedHosts = persistence.load(.allowedHosts, as: [String].self) { [] }
        sitePermissions = persistence.load(.sitePermissions, as: [SitePermission].self) { [] }
        quickSites = Array(
            persistence.load(.quickSites, as: [QuickSite].self) { QuickSite.defaults }
                .prefix(QuickSitePolicy.maximumCount)
        )
        siteBlockStats = BlockingPolicy.normalizedSiteStats(
            persistence.load(.siteBlockStats, as: [SiteBlockStats].self) { [] }
        )

        persistArchivedTabs()
        showsExpiredTabsPrompt = isPrimaryWindow && !archivedTabs.isEmpty
        ensureLive(activeTabID)
        persist()
        refreshHomeBackground()
        refreshSiteIcons()

        if isPrimaryWindow {
            TelemetryService.shared.syncConsent(
                consentAccepted: settings.privacyConsentAccepted,
                enabled: settings.telemetryEnabled
            )
            let milliseconds = (ProcessInfo.processInfo.systemUptime - initializationStartedAt) * 1_000
            TelemetryService.shared.recordStartup(
                milliseconds: milliseconds,
                context: telemetryContext()
            )
        }
        ContentBlocker.shared.prepare { [weak self] success, usedCachedRules in
            guard let self, success,
                  self.settings.privacyConsentAccepted,
                  self.settings.onboardingCompleted,
                  self.settings.blockAds,
                  (!usedCachedRules || RemoteRuleStore.shouldUpdate(
                    lastUpdatedAt: self.settings.rulesLastUpdatedAt
                  )) else { return }
            self.updateRemoteRules(manual: false)
        }
    }

    private func bindNotifications() {
        NotificationCenter.default.publisher(for: ContentBlocker.listsDidChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.controllers.values.forEach { $0.replaceContentBlockerLists() }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .browserWindowDidOpen)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                self?.completeWindowTransfer(notification)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.recordMemoryPressure() }
            .store(in: &cancellables)
    }

    private func configureSubStores(settings loadedSettings: BrowserSettings) {
        downloads.configure(settings: loadedSettings)
        downloads.onCompletion = { [weak self] task in
            self?.flash("\(task.fileName) 下载完成")
        }
        downloads.onFailure = { [weak self] task in
            self?.flash("\(task.fileName) 下载失败")
        }
        downloads.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        articles.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        pro.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    // MARK: - Active Tab & Navigation

    func tab(_ id: String) -> BrowserTab? {
        tabs.first { $0.id == id }
    }

    func controller(for tabID: String) -> TabController? {
        controllers[tabID]
    }

    func update(tabID: String, mutate: (inout BrowserTab) -> Void) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else {
            return
        }
        mutate(&tabs[index])
    }

    func openInActiveTab(_ raw: String) {
        let address = URLPolicy.normalizeAddress(
            raw,
            engine: settings.searchEngine,
            customTemplate: settings.customSearchTemplate
        )
        let usesDesktop = effectiveSiteControl(for: address).desktopUserAgentEnabled
        prepareNavigation(tabID: activeTabID, to: address)
        update(tabID: activeTabID) { tab in
            tab.url = address
            tab.failedURL = ""
            tab.loadError = .none
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
        if current.loadError != .none {
            retryPage(tabID: current.id)
            return
        }
        if URLPolicy.isHomeURL(current.url) {
            return
        }
        activeController?.reload()
    }

    func retryPage(tabID: String) {
        guard let current = tab(tabID) else { return }
        let targetURL = current.displayAddressURL
        guard !URLPolicy.isHomeURL(targetURL) else { return }
        let controller = controllers[tabID]
        update(tabID: tabID) { tab in
            tab.url = targetURL
            tab.failedURL = ""
            tab.loadError = .none
            tab.isLoading = true
            tab.progress = 0
        }
        if let controller {
            controller.load(targetURL)
        } else {
            ensureLive(tabID)
        }
    }

    func refreshPage(tabID: String) {
        guard let current = tab(tabID),
              PageRefreshPolicy.isEnabled(
                  isBrowsing: !URLPolicy.isHomeURL(current.url),
                  isReader: current.isReader,
                  isLoading: current.isLoading,
                  hasLoadError: current.loadError != .none
              ),
              let controller = controllers[tabID] else {
            return
        }
        update(tabID: tabID) { tab in
            tab.isLoading = true
            tab.progress = 0
        }
        if !controller.reload() {
            update(tabID: tabID) { tab in
                tab.isLoading = false
            }
        }
    }

    // MARK: - Telemetry & Notices

    func recordPageLoad(milliseconds: Double, tabID: String) {
        TelemetryService.shared.recordPageLoad(
            milliseconds: milliseconds,
            context: telemetryContext(tabID: tabID)
        )
    }

    func recordActionUsage(_ action: String, tabID: String? = nil) {
        TelemetryService.shared.recordActionUsage(
            action,
            context: telemetryContext(tabID: tabID)
        )
    }

    private func recordMemoryPressure() {
        if isPrimaryWindow {
            TelemetryService.shared.recordMemoryPressure(context: telemetryContext())
        }
        clearTabThumbnails()
        tabThumbnailTokens.removeAll()
        trimLive(limit: 1)
    }

    func setSiteIcon(_ image: UIImage?, forHost host: String) {
        siteIcons[host] = image
    }

    func setTabThumbnail(_ image: UIImage?, forTabID tabID: String) {
        tabThumbnails[tabID] = image
    }

    func clearTabThumbnails() {
        tabThumbnails.removeAll()
    }

    func telemetryContextForLifecycle() -> TelemetryContext {
        telemetryContext()
    }

    private func telemetryContext(tabID: String? = nil) -> TelemetryContext {
        let target = tabID.flatMap { tab($0) } ?? activeTab
        return TelemetryContext(
            consentAccepted: settings.privacyConsentAccepted,
            enabled: settings.telemetryEnabled,
            isPrivate: target?.isPrivate == true
        )
    }

    func flash(_ message: String) {
        notice = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            if self?.notice == message {
                self?.notice = nil
            }
        }
    }

    // MARK: - Page State & Prompts

    func captureActivePageState() {
        captureTabThumbnail(tabID: activeTabID)
        capturePageState(activeTabID)
    }

    func prepareNavigation(tabID: String, to url: String) {
        guard let current = tab(tabID), !PageStatePolicy.isSamePage(current.url, url) else {
            return
        }
        invalidateTabThumbnail(tabID: tabID)
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

    func openPopupTab(
        from sourceTabID: String,
        configuration: WKWebViewConfiguration,
        initialURL: String
    ) -> WKWebView? {
        guard let sourceIndex = tabs.firstIndex(where: { $0.id == sourceTabID }),
              tabs.count < SessionPolicy.maxTabCount else {
            return nil
        }
        if tabs.count >= settings.tabSoftLimit {
            showsTabSoftLimitPrompt = true
        }
        let source = tabs[sourceIndex]
        let normalizedURL = initialURL.isEmpty ? "about:blank" : initialURL
        var popup = BrowserTab.home(isPrivate: source.isPrivate)
        popup.url = normalizedURL
        popup.title = URLPolicy.displayHost(normalizedURL).isEmpty
            ? (source.isPrivate ? "无痕" : "新标签页")
            : URLPolicy.displayHost(normalizedURL)
        popup.isDesktop = source.isDesktop
        popup.isLoading = true
        tabs.insert(popup, at: sourceIndex + 1)
        let store = popup.isPrivate ? privateStore : WKWebsiteDataStore.default()
        let controller = TabController(
            tab: popup,
            session: self,
            dataStore: store,
            popupConfiguration: configuration
        )
        controllers[popup.id] = controller
        selectTab(popup.id)
        return controller.webView
    }

    func closePopupTab(_ id: String) {
        guard tab(id) != nil else { return }
        finishClosingTab(id)
    }

    func handleWebProcessTerminated(tabID: String) {
        cancelPrompts(forTabID: tabID)
        let now = Date().timeIntervalSince1970
        let previous = lastWebProcessTerminationAt[tabID] ?? 0
        lastWebProcessTerminationAt[tabID] = now
        guard let current = tab(tabID), !URLPolicy.isHomeURL(current.url) else {
            return
        }
        if now - previous < 5 {
            update(tabID: tabID) { tab in
                tab.isLoading = false
                tab.loadError = .unknown
                tab.failedURL = current.displayAddressURL
            }
            flash("网页渲染进程异常中断，请点击重试")
            return
        }
        update(tabID: tabID) { tab in
            tab.isLoading = true
            tab.progress = 0
        }
        controllers[tabID]?.reload()
    }

    func presentJsDialog(_ dialog: PendingJsDialog) {
        guard dialog.tabID == activeTabID else {
            dialog.cancel()
            return
        }
        activeJsDialog?.cancel()
        activeJsDialog = dialog
    }

    func dismissJsDialog() {
        activeJsDialog?.cancel()
        activeJsDialog = nil
    }

    func presentHttpAuth(_ challenge: PendingHttpAuth) {
        guard challenge.tabID == activeTabID else {
            challenge.cancel()
            return
        }
        activeHttpAuth?.cancel()
        activeHttpAuth = challenge
    }

    func dismissHttpAuth() {
        activeHttpAuth?.cancel()
        activeHttpAuth = nil
    }

    func cancelPrompts(forTabID tabID: String) {
        if activeJsDialog?.tabID == tabID {
            activeJsDialog?.cancel()
            activeJsDialog = nil
        }
        if activeHttpAuth?.tabID == tabID {
            activeHttpAuth?.cancel()
            activeHttpAuth = nil
        }
    }

    // MARK: - Live WebViews & State Capture

    func ensureLive(_ id: String) {
        guard let current = tab(id), !URLPolicy.isHomeURL(current.url) else {
            return
        }
        if controllers[id] == nil {
            controllers[id] = makeController(for: current)
        }
        trimLive()
    }

    func makeController(for tab: BrowserTab) -> TabController {
        let store = tab.isPrivate ? privateStore : WKWebsiteDataStore.default()
        return TabController(tab: tab, session: self, dataStore: store)
    }

    func trimLive(limit: Int? = nil) {
        let live = SessionPolicy.liveTabIDs(
            tabs: tabs,
            activeTabID: activeTabID,
            limit: limit ?? settings.liveWebViewLimit,
            requiredTabIDs: isSplitActive
                ? [paneState.primaryTabID, paneState.secondaryTabID].compactMap { $0 }
                : []
        )
        for id in Array(controllers.keys) where !SessionPolicy.isTabLive(live, id) {
            if let controller = controllers[id], let url = controller.webView.url?.absoluteString {
                update(tabID: id) { tab in
                    tab.url = url
                    if let title = controller.webView.title, !title.isEmpty {
                        tab.title = title
                    }
                    tab.isLoading = false
                }
            }
            cancelPrompts(forTabID: id)
            capturePageState(id)
            controllers[id] = nil
        }
    }

    func capturePageState(_ id: String) {
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

    func restoreStoredScroll(tabID: String, promptIfActive: Bool) {
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

    func recyclePrivateStoreIfNeeded() {
        if tabs.contains(where: { $0.isPrivate }) {
            return
        }
        privateStore = WKWebsiteDataStore.nonPersistent()
    }

    // MARK: - Persistence

    func persistSettings() {
        persistence.save(settings, for: .settings)
    }

    func persistReaderSettings() {
        persistence.save(readerSettings, for: .readerSettings)
    }

    func persistSitePermissions() {
        persistence.save(sitePermissions, for: .sitePermissions)
    }

    func persistAllowList() {
        persistence.save(allowedHosts, for: .allowedHosts)
    }

    func persistSiteBlockStats() {
        let limited = Array(siteBlockStats.sorted { $0.stats.total > $1.stats.total }.prefix(500))
        persistence.save(limited, for: .siteBlockStats)
    }

    func persistLibrary() {
        persistence.save(history, for: .history)
        persistence.save(savedItems, for: .savedItems)
        persistence.save(bookmarkFolders, for: .bookmarkFolders)
        persistence.save(bookmarkTombstones, for: .bookmarkTombstones)
        persistence.save(articleTombstones, for: .articleTombstones)
    }

    func persistQuickSites() {
        persistence.save(quickSites, for: .quickSites)
    }

    func persistArchivedTabs() {
        guard isPrimaryWindow else { return }
        persistence.save(archivedTabs, for: .archivedTabs)
    }

    func persist() {
        guard isPrimaryWindow else { return }
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
        persistence.save(payload, for: .session)
    }

    private static func restore(
        settings: BrowserSettings,
        persistence: BrowserPersistenceStore
    ) -> (
        tabs: [BrowserTab],
        activeTabID: String,
        expiredTabs: [BrowserTab]
    )? {
        guard let payload: PersistedSession = persistence.load(
            .session,
            as: PersistedSession?.self,
            default: { nil }
        ) else {
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

    private static func loadArchivedTabs(persistence: BrowserPersistenceStore) -> [BrowserTab] {
        let tabs = persistence.load(.archivedTabs, as: [BrowserTab].self) { [] }
        return SessionPolicy.persistableTabs(tabs)
    }

    private static func mergedArchivedTabs(_ existing: [BrowserTab], _ newlyExpired: [BrowserTab]) -> [BrowserTab] {
        var seen = Set<String>()
        return (newlyExpired + existing).filter { seen.insert($0.id).inserted }
    }

    static let cookieAndStorageDataTypes: Set<String> = [
        WKWebsiteDataTypeCookies,
        WKWebsiteDataTypeSessionStorage,
        WKWebsiteDataTypeLocalStorage,
        WKWebsiteDataTypeWebSQLDatabases,
        WKWebsiteDataTypeIndexedDBDatabases
    ]

    static let cacheDataTypes: Set<String> = [
        WKWebsiteDataTypeDiskCache,
        WKWebsiteDataTypeMemoryCache,
        WKWebsiteDataTypeOfflineWebApplicationCache
    ]
}
