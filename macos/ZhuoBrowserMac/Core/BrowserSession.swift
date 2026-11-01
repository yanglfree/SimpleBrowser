import Foundation
import SwiftUI
import WebKit

/// The central state manager for ZhuoBrowser Mac.
///
/// Tab lifecycle is organised in three tiers so switching tabs never reloads a page:
///
/// | tier | owner | switching cost |
/// |------|-------|----------------|
/// | hot  | active tab, WebView attached | 0 — same view is re-shown |
/// | warm | recent tabs, WebView detached but alive | 0 — re-attach |
/// | cold | frozen `TabStateSnapshot` in `TabStateStore` | no network, rebuilt from archive |
///
/// The live pool is capped by `MemoryBudgetPolicy` (and auto-shrunk under system
/// memory pressure), so parallel tabs stay bounded without ever forcing a re-fetch.
public final class BrowserSession: ObservableObject {
    public static let shared = BrowserSession()

    @Published public var tabs: [BrowserTab] = []
    @Published public var activeTabID: String?
    @Published public var omniboxText: String = ""
    @Published public var isOmniboxFocused: Bool = false
    @Published public var omniboxSuggestions: [OmniboxSuggestion] = []
    @Published public var selectedOmniboxSuggestionIndex: Int = -1
    @Published public var isShowingOmniboxSuggestions: Bool = false
    public var omniboxFrameInWindow: CGRect = .zero {
        didSet {
            guard isShowingOmniboxSuggestions,
                  abs(omniboxFrameInWindow.minX - oldValue.minX) > 0.5
                    || abs(omniboxFrameInWindow.maxY - oldValue.maxY) > 0.5
                    || abs(omniboxFrameInWindow.width - oldValue.width) > 0.5 else {
                return
            }
            objectWillChange.send()
        }
    }
    @Published public var activeLiveControllersCount: Int = 0
    @Published public private(set) var activeController: TabController?
    @Published public private(set) var memoryPressure: MemoryPressureLevel = .nominal

    /// Diagnostics: how often a tab switch reused the resident WebView versus how
    /// often the page had to be rebuilt. A healthy session shows rebuilds == 0.
    @Published public private(set) var liveReuseCount: Int = 0
    @Published public private(set) var pageRebuildCount: Int = 0

    @Published public var bookmarks: [BookmarkEntry] = []
    @Published public var bookmarkFolders: [BookmarkFolder] = []
    @Published public var history: [HistoryEntry] = []
    @Published public private(set) var siteIcons: [String: NSImage] = [:]
    @Published public var isShowingLibraryManager: Bool = false
    @Published public var isShowingBookmarkManager: Bool = false
    @Published public var isShowingOmniboxBookmarkPopover: Bool = false
    @Published public var bookmarkManagerSelectedFolderID: String? = nil
    @Published public var isShowingSettings: Bool = false
    @Published public var librarySelectedTab: Int = 0
    @Published public private(set) var canReopenClosedTab: Bool = false

    public let settings = BrowserSettings.shared
    private let libraryStore = LibraryStore.shared
    private let stateStore: TabStateStore
    private let pressureMonitor: MemoryPressureMonitor

    private var recentlyClosedTabs: [(url: String, title: String)] = []
    private static let maxRecentlyClosedTabs = 20

    private var siteIconLoadingHosts = Set<String>()
    private var deferredSiteIconRequests: [String: (pageURL: String, declaredURL: String)] = [:]
    private var controllers: [String: TabController] = [:]
    /// Guards against a second freeze being scheduled for the same tab while the
    /// scroll probe of the first one is still in flight.
    private var pendingHibernations: Set<String> = []
    private var sessionPersistenceWork: DispatchWorkItem?

    /// WebViews that are live and not already scheduled for freezing.
    private var committedLiveControllerCount: Int {
        controllers.keys.filter { !pendingHibernations.contains($0) }.count
    }

    public var warmControllersCount: Int {
        max(0, committedLiveControllerCount - (activeController != nil ? 1 : 0))
    }

    public var frozenTabCount: Int {
        tabs.filter(\.isHibernated).count
    }

    public init(
        stateStore: TabStateStore = .shared,
        pressureMonitor: MemoryPressureMonitor = .shared,
        restoresPreviousSession: Bool? = nil
    ) {
        self.stateStore = stateStore
        self.pressureMonitor = pressureMonitor

        // Prepare content blocking rules asynchronously
        ContentBlocker.shared.prepare { [weak self] in
            self?.applyContentProtectionSettingsToAllTabs()
        }

        // Re-inject the session cookies archived at the last quit *before* any page
        // starts loading, otherwise sites would treat the first paint as logged out.
        CookieSessionStore.shared.restoreArchivedCookies()
        CookieSessionStore.shared.startPeriodicFlush()

        // Load saved bookmarks, folders, and history
        let initialLibrary = libraryStore.loadInitialBookmarksAndFolders()
        bookmarkFolders = initialLibrary.folders
        bookmarks = initialLibrary.bookmarks
        history = libraryStore.loadHistory()
        syncFavoritesManager()

        let shouldRestore = restoresPreviousSession ?? Self.shouldRestorePreviousSession
        if shouldRestore, let savedTabs = stateStore.loadTabSession(), !savedTabs.isEmpty {
            tabs = savedTabs.map { persisted in
                let restoredURL = URLPolicy.upgradeToHTTPSIfPublicHost(persisted.url)
                if restoredURL != persisted.url {
                    stateStore.removeSnapshot(for: persisted.id)
                }
                return BrowserTab(
                    id: persisted.id,
                    url: restoredURL,
                    title: persisted.title,
                    isPrivate: false,
                    isHibernated: !(restoredURL.isEmpty || restoredURL == "zhuo://home"),
                    lastActiveTime: persisted.lastActiveTime
                )
            }
            let preferred = savedTabs.first(where: \.isActive)?.id
            if let preferred, tabs.contains(where: { $0.id == preferred }) {
                activeTabID = preferred
            } else {
                activeTabID = tabs.first?.id
            }
        } else {
            let initialTab = BrowserTab(url: "zhuo://home", title: "新标签页")
            tabs = [initialTab]
            activeTabID = initialTab.id
        }

        if let activeTab {
            omniboxText = URLPolicy.displayAddress(for: activeTab.url)
        }

        memoryPressure = pressureMonitor.level
        pressureMonitor.onChange = { [weak self] level in
            guard let self else { return }
            self.memoryPressure = level
            self.enforceMemoryBudget()
        }

        // Only the visible tab materialises a WebView; frozen tabs wake on demand.
        if let activeID = activeTabID {
            ensureLiveController(for: activeID)
        }
        enforceMemoryBudget()
        refreshSiteIcons()
    }

    private static var shouldRestorePreviousSession: Bool {
        guard !RuntimeEnvironment.isRunningUnitTests else { return false }
        return BrowserSettings.shared.restoreSessionOnLaunch
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
            // `selectTab` materialises the controller, which already navigates to the
            // tab URL — calling `navigate(to:)` as well would issue a second load.
            selectTab(id: newTab.id)
        } else {
            enforceMemoryBudget()
        }
        return newTab
    }

    public func closeTab(id: String) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }

        let closingTab = tabs[index]
        if !closingTab.isPrivate && !closingTab.isHome && !closingTab.url.isEmpty {
            recentlyClosedTabs.append((url: closingTab.url, title: closingTab.title))
            if recentlyClosedTabs.count > Self.maxRecentlyClosedTabs {
                recentlyClosedTabs.removeFirst(recentlyClosedTabs.count - Self.maxRecentlyClosedTabs)
            }
            canReopenClosedTab = true
        }

        pendingHibernations.remove(id)
        teardownController(for: id)
        stateStore.removeSnapshot(for: id)

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
        scheduleSessionPersistence()
    }

    @discardableResult
    public func reopenLastClosedTab() -> BrowserTab? {
        guard let last = recentlyClosedTabs.popLast() else { return nil }
        canReopenClosedTab = !recentlyClosedTabs.isEmpty
        var newTab = createTab(url: last.url, isPrivate: false, select: true)
        if !last.title.isEmpty {
            updateTab(newTab.id) { $0.title = last.title }
            newTab.title = last.title
        }
        return newTab
    }

    public func closeOtherTabs(keeping keepID: String? = nil) {
        guard let targetID = keepID ?? activeTabID,
              tabs.contains(where: { $0.id == targetID }) else { return }
        let otherIDs = tabs.map(\.id).filter { $0 != targetID }
        guard !otherIDs.isEmpty else { return }

        for id in otherIDs {
            if let tab = tab(for: id), !tab.isPrivate && !tab.isHome && !tab.url.isEmpty {
                recentlyClosedTabs.append((url: tab.url, title: tab.title))
            }
            pendingHibernations.remove(id)
            teardownController(for: id)
            stateStore.removeSnapshot(for: id)
        }
        if recentlyClosedTabs.count > Self.maxRecentlyClosedTabs {
            recentlyClosedTabs.removeFirst(recentlyClosedTabs.count - Self.maxRecentlyClosedTabs)
        }
        canReopenClosedTab = !recentlyClosedTabs.isEmpty

        tabs.removeAll { $0.id != targetID }
        selectTab(id: targetID)
        scheduleSessionPersistence()
    }

    public func selectNextTab() {
        guard tabs.count > 1 else { return }
        let currentIndex = tabs.firstIndex(where: { $0.id == activeTabID }) ?? 0
        let nextIndex = (currentIndex + 1) % tabs.count
        selectTab(id: tabs[nextIndex].id)
    }

    public func selectPreviousTab() {
        guard tabs.count > 1 else { return }
        let currentIndex = tabs.firstIndex(where: { $0.id == activeTabID }) ?? 0
        let prevIndex = (currentIndex - 1 + tabs.count) % tabs.count
        selectTab(id: tabs[prevIndex].id)
    }

    public func selectLastTab() {
        guard let last = tabs.last else { return }
        selectTab(id: last.id)
    }

    public func selectTab(id: String) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }

        let changed = activeTabID != id
        if changed {
            activeTabID = id
        }
        let nextOmnibox = URLPolicy.displayAddress(for: tabs[index].url)
        if omniboxText != nextOmnibox {
            omniboxText = nextOmnibox
        }
        dismissOmniboxSuggestions()

        // Instant path: reuse the warm WebView, or revive the frozen snapshot. No
        // `load(url:)` happens here, which is what removes the reload flash.
        ensureLiveController(for: id)
        if changed, let currentIndex = tabs.firstIndex(where: { $0.id == id }) {
            let now = Date()
            if now.timeIntervalSince(tabs[currentIndex].lastActiveTime) > 1.0 {
                tabs[currentIndex].lastActiveTime = now
            }
        }
        enforceMemoryBudget()
    }

    public func updateTab(_ id: String, mutate: (inout BrowserTab) -> Void) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let previous = tabs[index]
        var updated = previous
        mutate(&updated)
        let currentURL = updated.url
        let currentTitle = updated.title
        if previous.url != currentURL {
            updated.lastActiveTime = Date()
        }
        if updated != previous {
            tabs[index] = updated
        }
        if activeTabID == id {
            let nextOmnibox = URLPolicy.displayAddress(for: currentURL)
            if omniboxText != nextOmnibox {
                omniboxText = nextOmnibox
            }
        }
        if previous.url != currentURL {
            if controllers[id] != nil {
                stateStore.removeSnapshot(for: id)
            }
            scheduleSessionPersistence()
        } else if previous.title != currentTitle {
            scheduleSessionPersistence()
        }
    }

    // MARK: - Omnibox Autocomplete & Suggestions

    private func effectiveHistoryForSuggestions() -> [HistoryEntry] {
        let nonPrivateTabs = tabs.filter { !$0.isPrivate && !URLPolicy.isHomeURL($0.url) }
        guard !nonPrivateTabs.isEmpty else { return history }

        var combined = history
        var knownURLs = Set(history.map { LibraryPolicy.normalizeComparableURL($0.url) })
        for tab in nonPrivateTabs {
            let key = LibraryPolicy.normalizeComparableURL(tab.url)
            guard !key.isEmpty, !knownURLs.contains(key) else { continue }
            knownURLs.insert(key)
            combined.append(
                HistoryEntry(
                    id: "tab-\(tab.id)",
                    title: tab.title,
                    url: tab.url,
                    visitedAt: tab.lastActiveTime.timeIntervalSince1970,
                    visitCount: 1
                )
            )
        }
        return combined
    }

    public func suggestions(
        for query: String,
        includeSearchSuggestion: Bool = false,
        maxCount: Int = OmniboxSuggestionPolicy.defaultMaxSuggestions
    ) -> [OmniboxSuggestion] {
        OmniboxSuggestionPolicy.suggestions(
            for: query,
            history: effectiveHistoryForSuggestions(),
            bookmarks: bookmarks,
            searchEngine: settings.searchEngine,
            includeSearchSuggestion: includeSearchSuggestion,
            maxCount: maxCount
        )
    }

    public func inlineCompletion(for query: String) -> String? {
        OmniboxSuggestionPolicy.inlineCompletion(
            for: query,
            history: effectiveHistoryForSuggestions(),
            bookmarks: bookmarks
        )
    }

    public func updateOmniboxSuggestions(for query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            dismissOmniboxSuggestions()
            return
        }
        let next = suggestions(for: trimmed, includeSearchSuggestion: false)
        omniboxSuggestions = next
        selectedOmniboxSuggestionIndex = -1
        isShowingOmniboxSuggestions = !next.isEmpty
    }

    public func dismissOmniboxSuggestions() {
        if isShowingOmniboxSuggestions {
            isShowingOmniboxSuggestions = false
        }
        if selectedOmniboxSuggestionIndex != -1 {
            selectedOmniboxSuggestionIndex = -1
        }
        if !omniboxSuggestions.isEmpty {
            omniboxSuggestions = []
        }
    }

    public func commitOmniboxSuggestion(_ suggestion: OmniboxSuggestion) {
        dismissOmniboxSuggestions()
        isOmniboxFocused = false
        navigate(to: suggestion.url)
    }

    public func submitOmniboxInput(_ rawInput: String) {
        let target = OmniboxSuggestionPolicy.resolveSubmissionTarget(
            for: rawInput,
            suggestions: isShowingOmniboxSuggestions ? omniboxSuggestions : [],
            selectedIndex: selectedOmniboxSuggestionIndex
        )
        dismissOmniboxSuggestions()
        isOmniboxFocused = false
        guard !target.isEmpty else { return }
        navigate(to: target)
    }

    // MARK: - Navigation

    public func openExternalURL(_ rawText: String) {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let active = activeTab, active.isHome {
            navigate(to: trimmed)
        } else {
            createTab(url: trimmed, select: true)
        }
    }

    public func navigate(to text: String) {
        dismissOmniboxSuggestions()
        let normalizedURL = URLPolicy.normalizeAddress(text, searchEngine: settings.searchEngine)
        guard let activeID = activeTabID, let index = tabs.firstIndex(where: { $0.id == activeID }) else { return }

        tabs[index].url = normalizedURL
        tabs[index].isHibernated = false
        tabs[index].isSnapshotStale = false
        omniboxText = URLPolicy.displayAddress(for: normalizedURL)

        if normalizedURL == "zhuo://home" {
            // Explicit reset to the start page: the old page is no longer reachable
            // from this tab, so releasing it is intentional rather than a reload.
            pendingHibernations.remove(activeID)
            teardownController(for: activeID)
            stateStore.removeSnapshot(for: activeID)
            tabs[index].title = tabs[index].isPrivate ? "无痕新标签" : "新标签页"
            tabs[index].scrollPositionY = 0
            publishMemoryStats()
            return
        }

        guard let url = URL(string: normalizedURL) else { return }

        // A typed address is a new document: drop the frozen copy so a later switch
        // can never resurrect the previous page.
        stateStore.removeSnapshot(for: activeID)
        tabs[index].scrollPositionY = 0
        requestSiteIcon(pageURL: normalizedURL)

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
        if let activeID = activeTabID {
            stateStore.removeSnapshot(for: activeID)
        }
        activeController?.reload()
    }

    public func reloadActiveTabFromOrigin() {
        if let activeID = activeTabID {
            stateStore.removeSnapshot(for: activeID)
        }
        activeController?.reloadFromOrigin()
    }

    public func stopLoadingActiveTab() {
        activeController?.stopLoading()
        if let activeID = activeTabID {
            updateTab(activeID) { $0.isLoading = false }
        }
    }

    public func goHomeActiveTab() {
        navigate(to: "zhuo://home")
    }

    public func zoomInActiveTab() {
        activeController?.zoomIn()
    }

    public func zoomOutActiveTab() {
        activeController?.zoomOut()
    }

    public func resetZoomActiveTab() {
        activeController?.resetZoom()
    }

    public func copyActiveTabURL() {
        guard let tab = activeTab, !tab.isHome, !tab.url.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(tab.url, forType: .string)
    }

    public func goBackActiveTab() {
        activeController?.goBack()
    }

    public func goForwardActiveTab() {
        activeController?.goForward()
    }

    // MARK: - Live controller pool

    /// Makes sure a WebView exists for the tab without forcing any navigation.
    private func ensureLiveController(for id: String) {
        guard let tab = tab(for: id), !tab.isHome else { return }
        pendingHibernations.remove(id)

        if controllers[id] != nil {
            // Warm tab (or a freeze that was cancelled mid-flight): re-attach as-is and
            // clear the frozen flag so the UI never claims a resident page is asleep.
            if tab.isHibernated {
                updateTab(id) { $0.isHibernated = false }
                pageRebuildCount += 1
            } else {
                liveReuseCount += 1
            }
            return
        }

        let wasFrozen = tab.isHibernated
        let rawSnapshot = stateStore.snapshot(for: id)
        let snapshot: TabStateSnapshot?
        if let rawSnapshot, Self.isSnapshotUsable(rawSnapshot, for: tab) {
            snapshot = rawSnapshot
        } else {
            snapshot = nil
        }
        // A live controller now owns the tab's state; remove any disk/cached snapshot so
        // an older frozen state can never overwrite subsequent navigations or logins.
        if rawSnapshot != nil {
            stateStore.removeSnapshot(for: id)
        }
        if wasFrozen || snapshot != nil {
            pageRebuildCount += 1
        }

        let controller = TabController(
            tabID: id,
            session: self,
            initialURL: URL(string: tab.url),
            isPrivate: tab.isPrivate,
            restoring: snapshot
        )
        controllers[id] = controller

        let strategy = TabRestorePolicy.decide(hasLiveWebView: false, snapshot: snapshot)
        let isStale = strategy == .restoreStateMarkedStale
        let canRestoreWithoutNetwork = snapshot?.hasRestorableState == true
        updateTab(id) { current in
            current.isHibernated = false
            current.isSnapshotStale = isStale
            if let snapshot, canRestoreWithoutNetwork {
                current.title = snapshot.title.isEmpty ? current.title : snapshot.title
                current.canGoBack = snapshot.canGoBack
                current.canGoForward = snapshot.canGoForward
                current.scrollPositionY = snapshot.scrollPositionY
            }
        }
    }

    /// Validates that a persisted snapshot still matches the tab's current URL and was
    /// not superseded by a later navigation or login after the snapshot was captured.
    public static func isSnapshotUsable(_ snapshot: TabStateSnapshot, for tab: BrowserTab) -> Bool {
        let snapshotURL = LibraryPolicy.normalizeComparableURL(snapshot.url)
        let tabURL = LibraryPolicy.normalizeComparableURL(tab.url)
        if !snapshotURL.isEmpty && !tabURL.isEmpty && snapshotURL != tabURL {
            return false
        }
        // Allow 2s tolerance for clock/timer jitter around snapshot capture.
        if snapshot.capturedAt.addingTimeInterval(2) < tab.lastActiveTime {
            return false
        }
        return true
    }

    private func teardownController(for id: String) {
        guard let controller = controllers.removeValue(forKey: id) else { return }
        controller.destroy()
    }

    /// Freezes a tab: archive its page state, then release the WebView.
    private func hibernate(_ id: String) {
        guard let controller = controllers[id], !pendingHibernations.contains(id) else {
            updateTab(id) { $0.isHibernated = true }
            return
        }
        let isPrivate = tab(for: id)?.isPrivate ?? false
        pendingHibernations.insert(id)
        // Reflect the eviction immediately (badge + tab strip), while the archive probe
        // finishes in the background.
        updateTab(id) { tab in
            tab.isHibernated = true
        }
        publishMemoryStats()

        controller.captureSnapshotWithScrollPosition { [weak self, weak controller] snapshot in
            guard let self else { return }
            self.pendingHibernations.remove(id)

            if let snapshot {
                self.stateStore.store(snapshot, for: id, persistToDisk: !isPrivate)
                self.updateTab(id) { tab in
                    tab.lastActiveTime = snapshot.capturedAt
                    tab.scrollPositionY = snapshot.scrollPositionY
                    if !snapshot.title.isEmpty {
                        tab.title = snapshot.title
                    }
                }
            }

            // The user may have switched back while the probe was running: never
            // destroy a WebView that just became visible again.
            guard let controller,
                  self.controllers[id] === controller,
                  self.activeTabID != id else {
                self.publishMemoryStats()
                return
            }

            controller.destroy()
            self.controllers.removeValue(forKey: id)
            self.updateTab(id) { tab in
                tab.isHibernated = true
                tab.isLoading = false
            }
            self.publishMemoryStats()
        }
    }

    // MARK: - Bookmarks & History Management

    public func isBookmarked(url: String) -> Bool {
        LibraryPolicy.isBookmarked(bookmarks, url: url)
    }

    public func bookmark(forURL url: String) -> BookmarkEntry? {
        let target = LibraryPolicy.normalizeComparableURL(url)
        guard !target.isEmpty else { return nil }
        return bookmarks.first { LibraryPolicy.normalizeComparableURL($0.url) == target }
    }

    public func bookmark(forID id: String) -> BookmarkEntry? {
        bookmarks.first { $0.id == id }
    }

    public func folder(forID id: String?) -> BookmarkFolder? {
        guard let id else { return nil }
        return bookmarkFolders.first { $0.id == id }
    }

    public func folderName(for folderID: String?) -> String {
        guard let folderID, let folder = folder(forID: folderID) else {
            return "未分组"
        }
        return folder.name
    }

    public func bookmarks(inFolder folderID: String?) -> [BookmarkEntry] {
        LibraryPolicy.bookmarks(inFolderID: folderID, from: bookmarks)
    }

    public var ungroupedBookmarks: [BookmarkEntry] {
        let validFolderIDs = Set(bookmarkFolders.map(\.id))
        return bookmarks.filter {
            guard let fid = $0.folderID else { return true }
            return !validFolderIDs.contains(fid)
        }
    }

    public var startPagePinnedBookmarks: [BookmarkEntry] {
        bookmarks.filter { $0.folderID == nil && $0.isPinnedToStartPage }
    }

    public func toggleBookmarkForActiveTab() {
        guard let tab = activeTab, !tab.isHome, !tab.url.isEmpty else { return }
        if isBookmarked(url: tab.url) {
            bookmarks = LibraryPolicy.removeBookmarkByUrl(bookmarks, url: tab.url)
        } else {
            bookmarks = LibraryPolicy.addBookmark(bookmarks, url: tab.url, title: tab.title)
        }
        persistAndSyncBookmarks()
    }

    /// Ensures the active tab is bookmarked (creating it if needed) and returns the entry for quick popover editing.
    @discardableResult
    public func ensureActiveTabBookmarked(defaultFolderID: String? = nil) -> BookmarkEntry? {
        guard let tab = activeTab, !tab.isHome, !tab.url.isEmpty else { return nil }
        if let existing = bookmark(forURL: tab.url) {
            return existing
        }
        return addBookmark(
            url: tab.url,
            title: tab.title,
            folderID: defaultFolderID,
            isPinnedToStartPage: defaultFolderID == nil
        )
    }

    public func addBookmark(url: String, title: String) {
        _ = addBookmark(url: url, title: title, folderID: nil, isPinnedToStartPage: nil)
    }

    @discardableResult
    public func addBookmark(
        url: String,
        title: String,
        folderID: String?,
        isPinnedToStartPage: Bool? = nil,
        iconName: String? = nil,
        iconLetter: String? = nil,
        colorHex: String? = nil
    ) -> BookmarkEntry? {
        bookmarks = LibraryPolicy.addBookmark(
            bookmarks,
            url: url,
            title: title,
            folderID: folderID,
            isPinnedToStartPage: isPinnedToStartPage,
            iconName: iconName,
            iconLetter: iconLetter,
            colorHex: colorHex
        )
        persistAndSyncBookmarks()
        if !RuntimeEnvironment.isRunningUnitTests {
            requestSiteIcon(pageURL: LibraryPolicy.normalizeBookmarkURLInput(url))
        }
        return bookmark(forURL: LibraryPolicy.normalizeBookmarkURLInput(url))
    }

    public func removeBookmark(id: String) {
        bookmarks = LibraryPolicy.removeBookmark(bookmarks, id: id)
        persistAndSyncBookmarks()
    }

    public func removeBookmarks(ids: Set<String>) {
        bookmarks = LibraryPolicy.removeBookmarks(bookmarks, ids: ids)
        persistAndSyncBookmarks()
    }

    public func removeBookmarkByUrl(_ url: String) {
        bookmarks = LibraryPolicy.removeBookmarkByUrl(bookmarks, url: url)
        persistAndSyncBookmarks()
    }

    public func updateBookmark(id: String, title: String, url: String) {
        bookmarks = LibraryPolicy.updateBookmark(bookmarks, id: id, title: title, url: url)
        persistAndSyncBookmarks()
    }

    public func updateBookmark(
        id: String,
        title: String,
        url: String,
        folderID: String?,
        isPinnedToStartPage: Bool? = nil
    ) {
        bookmarks = LibraryPolicy.updateBookmark(
            bookmarks,
            id: id,
            title: title,
            url: url,
            folderID: folderID,
            isPinnedToStartPage: isPinnedToStartPage
        )
        persistAndSyncBookmarks()
    }

    public func moveBookmark(id: String, toFolderID folderID: String?) {
        bookmarks = LibraryPolicy.moveBookmark(bookmarks, id: id, toFolderID: folderID)
        persistAndSyncBookmarks()
    }

    public func moveBookmarks(ids: Set<String>, toFolderID folderID: String?) {
        bookmarks = LibraryPolicy.moveBookmarks(bookmarks, ids: ids, toFolderID: folderID)
        persistAndSyncBookmarks()
    }

    public func togglePinBookmarkToStartPage(id: String) {
        bookmarks = LibraryPolicy.togglePinToStartPage(bookmarks, id: id)
        persistAndSyncBookmarks()
    }

    // MARK: - Bookmark Folder Management

    @discardableResult
    public func createBookmarkFolder(name: String, iconName: String = "folder.fill") -> BookmarkFolder? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        bookmarkFolders = LibraryPolicy.createFolder(bookmarkFolders, name: trimmed, iconName: iconName)
        persistAndSyncBookmarks()
        return bookmarkFolders.first { $0.name.lowercased() == trimmed.lowercased() }
    }

    public func renameBookmarkFolder(id: String, newName: String) {
        bookmarkFolders = LibraryPolicy.renameFolder(bookmarkFolders, id: id, newName: newName)
        persistAndSyncBookmarks()
    }

    public func removeBookmarkFolder(id: String, deleteContainedBookmarks: Bool = false) {
        let result = LibraryPolicy.removeFolder(
            bookmarkFolders,
            bookmarks: bookmarks,
            folderID: id,
            deleteContainedBookmarks: deleteContainedBookmarks
        )
        bookmarkFolders = result.folders
        bookmarks = result.bookmarks
        if bookmarkManagerSelectedFolderID == id {
            bookmarkManagerSelectedFolderID = nil
        }
        persistAndSyncBookmarks()
    }

    public func moveBookmarkFolder(id: String, direction: Int) {
        bookmarkFolders = LibraryPolicy.moveFolder(bookmarkFolders, id: id, direction: direction)
        persistAndSyncBookmarks()
    }

    public func openAllBookmarks(inFolder folderID: String?) {
        let items = bookmarks(inFolder: folderID)
        for item in items where !item.url.isEmpty {
            _ = createTab(url: item.url, select: true)
        }
    }

    public func openBookmarkManager(selectingFolderID: String? = nil) {
        if let selectingFolderID {
            bookmarkManagerSelectedFolderID = selectingFolderID
        }
        isShowingLibraryManager = false
        isShowingOmniboxBookmarkPopover = false
        isShowingBookmarkManager = true
    }

    // MARK: - Bookmark HTML Import / Export

    @discardableResult
    public func importBookmarksHTML(_ html: String) -> Int {
        let result = BookmarkHTMLTransfer.importHTML(
            html,
            existingFolders: bookmarkFolders,
            existingBookmarks: bookmarks
        )
        bookmarkFolders = result.folders
        bookmarks = result.bookmarks
        persistAndSyncBookmarks()
        return result.importedCount
    }

    public func exportBookmarksHTML() -> String {
        BookmarkHTMLTransfer.exportHTML(folders: bookmarkFolders, bookmarks: bookmarks)
    }

    public func importBookmarksFromPanel(completion: ((Int) -> Void)? = nil) {
        let panel = NSOpenPanel()
        panel.title = "导入书签 (HTML)"
        panel.allowedFileTypes = ["html", "htm"]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        if panel.runModal() == .OK, let url = panel.url,
           let html = try? String(contentsOf: url, encoding: .utf8) {
            let count = importBookmarksHTML(html)
            completion?(count)
        }
    }

    public func exportBookmarksToPanel(completion: ((Bool) -> Void)? = nil) {
        let panel = NSSavePanel()
        panel.title = "导出书签 (HTML)"
        panel.nameFieldStringValue = "zhuo-bookmarks.html"
        panel.allowedFileTypes = ["html"]
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let url = panel.url {
            let html = exportBookmarksHTML()
            do {
                try html.write(to: url, atomically: true, encoding: .utf8)
                completion?(true)
            } catch {
                completion?(false)
            }
        }
    }

    private func persistAndSyncBookmarks() {
        libraryStore.saveBookmarkFolders(bookmarkFolders)
        libraryStore.saveBookmarks(bookmarks)
        syncFavoritesManager()
    }

    private func syncFavoritesManager() {
        let foldersSnapshot = bookmarkFolders
        let bookmarksSnapshot = bookmarks
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                FavoritesManager.shared.sync(folders: foldersSnapshot, bookmarks: bookmarksSnapshot)
            }
        } else {
            Task { @MainActor in
                FavoritesManager.shared.sync(folders: foldersSnapshot, bookmarks: bookmarksSnapshot)
            }
        }
    }

    public func recordHistory(url: String, title: String) {
        history = LibraryPolicy.recordHistory(history, url: url, title: title)
        libraryStore.saveHistory(history)
    }

    public func removeHistoryItem(id: String) {
        history = LibraryPolicy.removeHistoryItem(history, id: id)
        libraryStore.saveHistory(history)
    }

    public func clearHistory() {
        history = []
        libraryStore.clearHistory()
    }

    public func clearWebsiteData(clearCookies: Bool = true, clearCache: Bool = true, completion: (() -> Void)? = nil) {
        var dataTypes = Set<String>()
        if clearCache {
            dataTypes.insert(WKWebsiteDataTypeDiskCache)
            dataTypes.insert(WKWebsiteDataTypeMemoryCache)
        }
        if clearCookies {
            dataTypes.insert(WKWebsiteDataTypeCookies)
            dataTypes.insert(WKWebsiteDataTypeLocalStorage)
            dataTypes.insert(WKWebsiteDataTypeSessionStorage)
        }
        guard !dataTypes.isEmpty else {
            completion?()
            return
        }
        // Never wipe the user's real WebKit cookies/storage when running unit tests.
        let targetStore: WKWebsiteDataStore = RuntimeEnvironment.isRunningUnitTests
            ? .nonPersistent()
            : .default()
        if clearCookies && !RuntimeEnvironment.isRunningUnitTests {
            CookieSessionStore.shared.clearArchive()
            WebSessionStorageStore.shared.clearAll()
        }
        targetStore.removeData(ofTypes: dataTypes, modifiedSince: Date.distantPast) {
            DispatchQueue.main.async {
                completion?()
            }
        }
    }

    public func openLibrary(tabIndex: Int = 0) {
        librarySelectedTab = tabIndex
        isShowingLibraryManager = true
    }

    public func toggleLibrary(tabIndex: Int? = nil) {
        if let tabIndex {
            if isShowingLibraryManager && librarySelectedTab == tabIndex {
                isShowingLibraryManager = false
            } else {
                librarySelectedTab = tabIndex
                isShowingLibraryManager = true
            }
        } else {
            isShowingLibraryManager.toggle()
        }
    }

    /// Opens a history entry picked from the History menu.
    public func openHistoryEntry(_ entry: HistoryEntry) {
        guard activeTabID != nil else {
            createTab(url: entry.url)
            return
        }
        navigate(to: entry.url)
    }

    // MARK: - Memory Budget Enforcement & Hibernation

    public func applyContentProtectionSettingsToAllTabs(evaluateLiveScripts: Bool = false) {
        for controller in controllers.values {
            controller.applyContentProtectionSettings(evaluateLiveScripts: evaluateLiveScripts)
        }
    }

    public func enforceMemoryBudget() {
        let plan = MemoryBudgetPolicy.evaluate(
            tabs: tabs,
            activeTabID: activeTabID,
            budget: settings.liveWebViewBudget,
            pressure: memoryPressure,
            hibernationEnabled: settings.tabHibernationEnabled
        )

        // 1. The visible tab must always own a live WebView.
        if let activeID = activeTabID, controllers[activeID] == nil {
            ensureLiveController(for: activeID)
        }

        // 2. Freeze everything that fell outside the pool. The budget is only a cap:
        //    tabs inside it are never rebuilt, they simply keep their WebView.
        for id in plan.tabsToHibernate where id != activeTabID {
            guard controllers[id] != nil else {
                updateTab(id) { tab in
                    if !tab.isHome { tab.isHibernated = true }
                }
                continue
            }
            hibernate(id)
        }

        publishMemoryStats()
    }

    private func publishMemoryStats() {
        let nextLiveCount = committedLiveControllerCount
        if activeLiveControllersCount != nextLiveCount {
            activeLiveControllersCount = nextLiveCount
        }

        let active = activeTabID.flatMap { controllers[$0] }
        if activeController !== active {
            activeController = active
        }

        scheduleSessionPersistence()
    }

    // MARK: - Site Icons

    public func siteIcon(for url: String) -> NSImage? {
        let host = URLPolicy.rawHost(url)
        return host.isEmpty ? nil : siteIcons[host]
    }

    public func siteIcon(for tab: BrowserTab) -> NSImage? {
        tab.isPrivate ? nil : siteIcon(for: tab.url)
    }

    public func refreshSiteIcons() {
        for tab in tabs where !tab.isPrivate && !tab.isHome {
            requestSiteIcon(pageURL: tab.url)
        }
    }

    public func refreshSiteIcon(tabID: String, declaredURL: String) {
        guard let tab = tab(for: tabID),
              !tab.isPrivate,
              !tab.isHome else {
            return
        }
        requestSiteIcon(pageURL: tab.url, declaredURL: declaredURL)
    }

    public func requestSiteIcon(pageURL: String, declaredURL: String = "") {
        let host = URLPolicy.rawHost(pageURL)
        guard !host.isEmpty, siteIcons[host] == nil else { return }
        if siteIconLoadingHosts.contains(host) {
            if !declaredURL.isEmpty {
                deferredSiteIconRequests[host] = (pageURL, declaredURL)
            }
            return
        }
        siteIconLoadingHosts.insert(host)
        Task.detached(priority: .utility) { [weak self] in
            let data = await SiteIconStore.shared.iconData(
                for: pageURL,
                declaredURL: declaredURL.isEmpty ? nil : declaredURL
            )
            let decodedImage = data.flatMap { SiteIconImage.decode($0) }
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.siteIconLoadingHosts.remove(host)
                if let decodedImage {
                    self.siteIcons[host] = decodedImage
                    self.deferredSiteIconRequests.removeValue(forKey: host)
                    return
                }
                if let deferred = self.deferredSiteIconRequests.removeValue(forKey: host) {
                    self.requestSiteIcon(pageURL: deferred.pageURL, declaredURL: deferred.declaredURL)
                }
            }
        }
    }

    // MARK: - Session persistence

    /// Persists the tab strip plus the frozen state of every non-live tab.
    /// Private tabs are never written: their URLs and page state stay in memory only.
    public func persistSession(synchronously: Bool = false) {
        let restorableTabs = tabs.filter { !$0.isPrivate }
        let states = restorableTabs.map {
            PersistedTabState(
                id: $0.id,
                url: $0.url,
                title: $0.title,
                isActive: $0.id == activeTabID,
                lastActiveTime: $0.lastActiveTime
            )
        }
        stateStore.saveTabSession(states, synchronously: synchronously)
        stateStore.pruneSnapshots(keeping: Set(restorableTabs.map(\.id)))
    }

    /// Lightweight background checkpoint when the app resigns active, avoiding synchronous
    /// main-thread snapshot encoding across all background WebViews.
    public func captureSessionOnResignActive() {
        if let activeID = activeTabID,
           let controller = controllers[activeID],
           let index = tabs.firstIndex(where: { $0.id == activeID }),
           !tabs[index].isPrivate,
           !tabs[index].isHome {
            if let liveURL = controller.webView?.url?.absoluteString, !liveURL.isEmpty, tabs[index].url != liveURL {
                tabs[index].url = liveURL
            }
            if let liveTitle = controller.webView?.title, !liveTitle.isEmpty, tabs[index].title != liveTitle {
                tabs[index].title = liveTitle
            }
            if let snapshot = controller.makeSnapshot() {
                stateStore.store(snapshot, for: activeID, synchronously: false)
            }
        }
        persistSession(synchronously: false)
    }

    /// Called right before the app terminates so a relaunch resumes every visible
    /// page instantly, including live tabs that were never hibernated.
    public func captureSessionForTermination(synchronously: Bool = false) {
        for (id, controller) in controllers {
            guard let index = tabs.firstIndex(where: { $0.id == id }),
                  !tabs[index].isPrivate,
                  !tabs[index].isHome else { continue }
            if let liveURL = controller.webView?.url?.absoluteString, !liveURL.isEmpty {
                tabs[index].url = liveURL
            }
            if let liveTitle = controller.webView?.title, !liveTitle.isEmpty {
                tabs[index].title = liveTitle
            }
            if let snapshot = controller.makeSnapshot() {
                tabs[index].lastActiveTime = snapshot.capturedAt
                stateStore.store(snapshot, for: id, synchronously: synchronously)
            }
        }
        persistSession(synchronously: synchronously)
    }

    private func scheduleSessionPersistence() {
        guard stateStore.isPersistenceEnabled else { return }
        sessionPersistenceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.persistSession()
        }
        sessionPersistenceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }
}
