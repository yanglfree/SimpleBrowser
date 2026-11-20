import AppKit
import Combine
import SwiftUI

/// Captures the live page snapshots on quit so the next launch can restore every
/// tab — including tabs that were never frozen — without a single reload.
///
/// It also flushes WebKit's *session* cookies (the ones that only live in the network
/// process memory). Without this, quitting or updating the app signs the user out of
/// every website.
@MainActor
final class ZhuoBrowserMacAppDelegate: NSObject, NSApplicationDelegate {
    private var signalSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !RuntimeEnvironment.isRunningUnitTests else { return }
        DefaultBrowserManager.shared.ensureRegisteredWithLaunchServices()
        DefaultBrowserManager.shared.refreshStatus()
        installTerminationSignalHandlers()
        installContextMenuLocalization()
        handleInitialLaunchArguments()
        Task { @MainActor in
            _ = HomeBackgroundManager.shared
            _ = FavoritesManager.shared
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard !RuntimeEnvironment.isRunningUnitTests else { return }
        for url in urls {
            ProfileManager.shared.focusedSession.openExternalURL(url.absoluteString)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in sender.windows {
                window.makeKeyAndOrderFront(self)
            }
        }
        return true
    }

    func applicationDidResignActive(_ notification: Notification) {
        ProfileManager.shared.persistAllSessionsForResignActive()
    }

    func applicationWillTerminate(_ notification: Notification) {
        SingleInstanceGuard.shared.releaseLock()
        flushAllStateForTermination()
    }

    private func handleInitialLaunchArguments() {
        let urls = SingleInstanceGuard.extractURLs(from: CommandLine.arguments)
        for url in urls {
            ProfileManager.shared.focusedSession.openExternalURL(url)
        }
    }

    private func flushAllStateForTermination() {
        WebPopupWindowManager.shared.closeAllPopups()
        BrowserSettings.shared.flushSynchronously()
        ProfileManager.shared.flushAllSessionsForTermination()
    }

    private func installTerminationSignalHandlers() {
        for sig in [SIGTERM, SIGINT] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { [weak self] in
                self?.flushAllStateForTermination()
                exit(0)
            }
            source.resume()
            signalSources.append(source)
        }
    }

    private func installContextMenuLocalization() {
        NotificationCenter.default.addObserver(
            forName: NSMenu.didBeginTrackingNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let menu = notification.object as? NSMenu else { return }
            Self.localizeWebKitContextMenu(menu)
        }
    }

    static func localizeWebKitContextMenu(_ menu: NSMenu) {
        for item in menu.items {
            guard let rawId = item.identifier?.rawValue else { continue }
            switch rawId {
            case "WKMenuItemIdentifierOpenLink":
                item.title = "打开链接"
            case "WKMenuItemIdentifierOpenLinkInNewWindow":
                item.title = "在新标签页中打开链接"
            case "WKMenuItemIdentifierDownloadLinkedFile":
                item.title = "下载链接文件"
            case "WKMenuItemIdentifierCopyLink":
                item.title = "拷贝链接"
            case "WKMenuItemIdentifierOpenImageInNewWindow":
                item.title = "在新标签页中打开图像"
            case "WKMenuItemIdentifierDownloadImage":
                item.title = "下载图像"
            case "WKMenuItemIdentifierCopyImage":
                item.title = "拷贝图像"
            case "WKMenuItemIdentifierOpenMediaInNewWindow":
                item.title = "在新标签页中打开视频"
            case "WKMenuItemIdentifierDownloadMedia":
                item.title = "下载视频"
            case "WKMenuItemIdentifierCopyMediaLink":
                item.title = "拷贝视频地址"
            case "WKMenuItemIdentifierReload":
                item.title = "重新加载"
            case "WKMenuItemIdentifierGoBack":
                item.title = "返回"
            case "WKMenuItemIdentifierGoForward":
                item.title = "前进"
            case "WKMenuItemIdentifierInspectElement":
                item.title = "检查元素"
            default:
                break
            }
            if let submenu = item.submenu {
                localizeWebKitContextMenu(submenu)
            }
        }
    }
}

public struct MenuHistoryItem: Identifiable, Equatable {
    public let index: Int
    public let entry: HistoryEntry

    public var id: String {
        "\(index)\u{0}\(entry.id)\u{0}\(entry.displayTitle)\u{0}\(entry.url)"
    }

    public var displayTitle: String {
        entry.displayTitle
    }

    public init(index: Int, entry: HistoryEntry) {
        self.index = index
        self.entry = entry
    }

    public static func == (lhs: MenuHistoryItem, rhs: MenuHistoryItem) -> Bool {
        lhs.index == rhs.index
            && lhs.entry.id == rhs.entry.id
            && lhs.entry.displayTitle == rhs.entry.displayTitle
            && lhs.entry.url == rhs.entry.url
    }
}

public struct MenuBookmarkItem: Identifiable, Equatable {
    public let index: Int
    public let bookmarkID: String
    public let displayTitle: String
    public let url: String

    public var id: String {
        "\(index)\u{0}\(bookmarkID)\u{0}\(displayTitle)\u{0}\(url)"
    }

    public init(index: Int, bookmarkID: String, displayTitle: String, url: String) {
        self.index = index
        self.bookmarkID = bookmarkID
        self.displayTitle = displayTitle
        self.url = url
    }
}

public struct MenuBookmarkFolder: Identifiable, Equatable {
    public let index: Int
    public let folderID: String
    public let name: String
    public let items: [MenuBookmarkItem]

    public var id: String {
        "\(index)\u{0}\(folderID)\u{0}\(name)"
    }

    public init(index: Int, folderID: String, name: String, items: [MenuBookmarkItem]) {
        self.index = index
        self.folderID = folderID
        self.name = name
        self.items = items
    }
}

public struct MenuExtensionItem: Identifiable, Equatable {
    public let index: Int
    public let extensionID: String
    public let name: String

    public var id: String {
        "\(index)\u{0}\(extensionID)\u{0}\(name)"
    }

    public init(index: Int, extensionID: String, name: String) {
        self.index = index
        self.extensionID = extensionID
        self.name = name
    }
}

public struct MenuProfileItem: Identifiable, Equatable {
    public let index: Int
    public let profileID: UUID
    public let displayName: String

    public var id: String {
        "\(index)\u{0}\(profileID.uuidString)\u{0}\(displayName)"
    }

    public init(index: Int, profileID: UUID, displayName: String) {
        self.index = index
        self.profileID = profileID
        self.displayName = displayName
    }
}

public struct BrowserMenuSnapshot: Equatable {
    public var tabCount: Int
    public var isActiveTabHome: Bool
    public var canGoBack: Bool
    public var canGoForward: Bool
    public var isLoading: Bool
    public var canReopenClosedTab: Bool
    public var hasFindQuery: Bool
    public var bookmarkFolders: [MenuBookmarkFolder]
    public var ungroupedBookmarks: [MenuBookmarkItem]
    public var recentHistory: [MenuHistoryItem]
    public var isHistoryEmpty: Bool
    public var enabledExtensions: [MenuExtensionItem]
    public var profiles: [MenuProfileItem]
    public var focusedProfileID: UUID
}

/// Projects only menu-relevant state from the focused `BrowserSession` and `ProfileManager`
/// so high-frequency edits (like `omniboxText` or `loadingProgress`) never rebuild the app menu bar.
public final class FocusedMenuState: ObservableObject {
    public static let shared = FocusedMenuState()
    public static let defaultRecentHistoryLimit = 10
    private static let ungroupedBookmarkLimit = 15

    @Published public private(set) var snapshot: BrowserMenuSnapshot

    private let profileManager: ProfileManager
    private let recentHistoryLimit: Int
    private weak var observedSession: BrowserSession?
    private var managerCancellables: Set<AnyCancellable> = []
    private var sessionCancellables: Set<AnyCancellable> = []

    public var currentSession: BrowserSession {
        observedSession ?? profileManager.focusedSession
    }

    public init(
        profileManager: ProfileManager = .shared,
        recentHistoryLimit: Int = defaultRecentHistoryLimit
    ) {
        self.profileManager = profileManager
        self.recentHistoryLimit = max(1, recentHistoryLimit)

        let initialProfiles = profileManager.profiles
        let initialProfileID = profileManager.focusedProfile.id
        let initialSession = profileManager.session(for: initialProfileID)

        self.observedSession = initialSession
        self.snapshot = Self.makeSnapshot(
            profiles: initialProfiles,
            focusedProfileID: initialSession.profileID,
            session: initialSession,
            recentHistoryLimit: self.recentHistoryLimit
        )

        profileManager.$profiles
            .dropFirst()
            .sink { [weak self] newProfiles in
                guard let self else { return }
                let projected = Self.makeProfileProjection(from: newProfiles)
                self.commit { $0.profiles = projected }
            }
            .store(in: &managerCancellables)

        profileManager.$focusedProfileID
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] newProfileID in
                guard let self else { return }
                let nextSession = self.profileManager.session(for: newProfileID)
                self.bindSession(nextSession, focusedProfileID: nextSession.profileID)
            }
            .store(in: &managerCancellables)

        subscribeToSession(initialSession)
    }

    private func bindSession(_ session: BrowserSession, focusedProfileID: UUID) {
        sessionCancellables.removeAll()
        observedSession = session

        let nextTab = Self.makeTabProjection(
            tabs: session.tabs,
            activeTabID: session.activeTabID,
            canReopenClosedTab: session.canReopenClosedTab,
            hasFindQuery: !session.findQuery.isEmpty
        )
        let nextBookmarks = Self.makeBookmarkProjections(
            folders: session.bookmarkFolders,
            bookmarks: session.bookmarks
        )
        let nextHistory = Self.makeHistoryProjection(from: session.history, limit: recentHistoryLimit)
        let nextExtensions = Self.makeExtensionProjection(from: session.extensionManager.extensions)

        commit { snap in
            snap.focusedProfileID = focusedProfileID
            snap.tabCount = nextTab.tabCount
            snap.isActiveTabHome = nextTab.isActiveTabHome
            snap.canGoBack = nextTab.canGoBack
            snap.canGoForward = nextTab.canGoForward
            snap.isLoading = nextTab.isLoading
            snap.canReopenClosedTab = nextTab.canReopenClosedTab
            snap.hasFindQuery = nextTab.hasFindQuery
            snap.bookmarkFolders = nextBookmarks.folders
            snap.ungroupedBookmarks = nextBookmarks.ungrouped
            snap.recentHistory = nextHistory.recent
            snap.isHistoryEmpty = nextHistory.isEmpty
            snap.enabledExtensions = nextExtensions
        }

        subscribeToSession(session)
    }

    private func subscribeToSession(_ session: BrowserSession) {
        session.$history
            .dropFirst()
            .sink { [weak self] newHistory in
                guard let self else { return }
                let projected = Self.makeHistoryProjection(from: newHistory, limit: self.recentHistoryLimit)
                self.commit { snap in
                    snap.recentHistory = projected.recent
                    snap.isHistoryEmpty = projected.isEmpty
                }
            }
            .store(in: &sessionCancellables)

        Publishers.CombineLatest(session.$bookmarkFolders, session.$bookmarks)
            .dropFirst()
            .sink { [weak self] newFolders, newBookmarks in
                guard let self else { return }
                let projected = Self.makeBookmarkProjections(folders: newFolders, bookmarks: newBookmarks)
                self.commit { snap in
                    snap.bookmarkFolders = projected.folders
                    snap.ungroupedBookmarks = projected.ungrouped
                }
            }
            .store(in: &sessionCancellables)

        Publishers.CombineLatest4(
            session.$tabs,
            session.$activeTabID,
            session.$canReopenClosedTab,
            session.$findQuery.map { !$0.isEmpty }.removeDuplicates()
        )
        .dropFirst()
        .sink { [weak self] newTabs, newActiveTabID, newCanReopen, newHasFindQuery in
            guard let self else { return }
            let projected = Self.makeTabProjection(
                tabs: newTabs,
                activeTabID: newActiveTabID,
                canReopenClosedTab: newCanReopen,
                hasFindQuery: newHasFindQuery
            )
            self.commit { snap in
                snap.tabCount = projected.tabCount
                snap.isActiveTabHome = projected.isActiveTabHome
                snap.canGoBack = projected.canGoBack
                snap.canGoForward = projected.canGoForward
                snap.isLoading = projected.isLoading
                snap.canReopenClosedTab = projected.canReopenClosedTab
                snap.hasFindQuery = projected.hasFindQuery
            }
        }
        .store(in: &sessionCancellables)

        session.extensionManager.$extensions
            .dropFirst()
            .sink { [weak self] newExtensions in
                guard let self else { return }
                let projected = Self.makeExtensionProjection(from: newExtensions)
                self.commit { $0.enabledExtensions = projected }
            }
            .store(in: &sessionCancellables)
    }

    private func commit(_ mutate: @escaping (inout BrowserMenuSnapshot) -> Void) {
        if Thread.isMainThread {
            var next = snapshot
            mutate(&next)
            guard next != snapshot else { return }
            snapshot = next
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                var next = self.snapshot
                mutate(&next)
                guard next != self.snapshot else { return }
                self.snapshot = next
            }
        }
    }

    private static func makeSnapshot(
        profiles: [BrowserProfile],
        focusedProfileID: UUID,
        session: BrowserSession,
        recentHistoryLimit: Int
    ) -> BrowserMenuSnapshot {
        let tabProjection = makeTabProjection(
            tabs: session.tabs,
            activeTabID: session.activeTabID,
            canReopenClosedTab: session.canReopenClosedTab,
            hasFindQuery: !session.findQuery.isEmpty
        )
        let bookmarkProjection = makeBookmarkProjections(
            folders: session.bookmarkFolders,
            bookmarks: session.bookmarks
        )
        let historyProjection = makeHistoryProjection(from: session.history, limit: recentHistoryLimit)
        return BrowserMenuSnapshot(
            tabCount: tabProjection.tabCount,
            isActiveTabHome: tabProjection.isActiveTabHome,
            canGoBack: tabProjection.canGoBack,
            canGoForward: tabProjection.canGoForward,
            isLoading: tabProjection.isLoading,
            canReopenClosedTab: tabProjection.canReopenClosedTab,
            hasFindQuery: tabProjection.hasFindQuery,
            bookmarkFolders: bookmarkProjection.folders,
            ungroupedBookmarks: bookmarkProjection.ungrouped,
            recentHistory: historyProjection.recent,
            isHistoryEmpty: historyProjection.isEmpty,
            enabledExtensions: makeExtensionProjection(from: session.extensionManager.extensions),
            profiles: makeProfileProjection(from: profiles),
            focusedProfileID: focusedProfileID
        )
    }

    private static func makeHistoryProjection(
        from history: [HistoryEntry],
        limit: Int
    ) -> (recent: [MenuHistoryItem], isEmpty: Bool) {
        let recent = Array(history.prefix(limit)).enumerated().map { index, entry in
            MenuHistoryItem(index: index, entry: entry)
        }
        return (recent, history.isEmpty)
    }

    private static func makeBookmarkProjections(
        folders: [BookmarkFolder],
        bookmarks: [BookmarkEntry]
    ) -> (folders: [MenuBookmarkFolder], ungrouped: [MenuBookmarkItem]) {
        let projectedFolders = folders.enumerated().map { folderIndex, folder in
            let items = LibraryPolicy.bookmarks(inFolderID: folder.id, from: bookmarks)
                .enumerated()
                .map { itemIndex, bm in
                    MenuBookmarkItem(index: itemIndex, bookmarkID: bm.id, displayTitle: bm.displayTitle, url: bm.url)
                }
            return MenuBookmarkFolder(index: folderIndex, folderID: folder.id, name: folder.name, items: items)
        }
        let validFolderIDs = Set(folders.map(\.id))
        let projectedUngrouped = bookmarks
            .filter {
                guard let fid = $0.folderID else { return true }
                return !validFolderIDs.contains(fid)
            }
            .prefix(ungroupedBookmarkLimit)
            .enumerated()
            .map { itemIndex, bm in
                MenuBookmarkItem(index: itemIndex, bookmarkID: bm.id, displayTitle: bm.displayTitle, url: bm.url)
            }
        return (projectedFolders, projectedUngrouped)
    }

    private static func makeTabProjection(
        tabs: [BrowserTab],
        activeTabID: String?,
        canReopenClosedTab: Bool,
        hasFindQuery: Bool
    ) -> (
        tabCount: Int,
        isActiveTabHome: Bool,
        canGoBack: Bool,
        canGoForward: Bool,
        isLoading: Bool,
        canReopenClosedTab: Bool,
        hasFindQuery: Bool
    ) {
        let activeTab: BrowserTab?
        if let activeTabID {
            activeTab = tabs.first(where: { $0.id == activeTabID })
        } else {
            activeTab = tabs.first
        }
        return (
            tabCount: tabs.count,
            isActiveTabHome: activeTab?.isHome ?? true,
            canGoBack: activeTab?.canGoBack ?? false,
            canGoForward: activeTab?.canGoForward ?? false,
            isLoading: activeTab?.isLoading ?? false,
            canReopenClosedTab: canReopenClosedTab,
            hasFindQuery: hasFindQuery
        )
    }

    private static func makeExtensionProjection(from extensions: [InstalledExtension]) -> [MenuExtensionItem] {
        extensions
            .filter(\.isEnabled)
            .enumerated()
            .map { index, ext in
                MenuExtensionItem(index: index, extensionID: ext.id, name: ext.manifest.name)
            }
    }

    private static func makeProfileProjection(from profiles: [BrowserProfile]) -> [MenuProfileItem] {
        profiles.enumerated().map { index, profile in
            MenuProfileItem(index: index, profileID: profile.id, displayName: profile.displayName)
        }
    }
}

private struct BrowserMenuCommands: Commands {
    @ObservedObject var menuState: FocusedMenuState
    let openProfileWindow: (UUID) -> Void

    private var session: BrowserSession {
        menuState.currentSession
    }

    private var snapshot: BrowserMenuSnapshot {
        menuState.snapshot
    }

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("偏好设置...") {
                session.isShowingSettings = true
            }
            .keyboardShortcut(",", modifiers: .command)
        }

        CommandGroup(replacing: .newItem) {
            Button("新建标签页") {
                session.createTab()
            }
            .keyboardShortcut("t", modifiers: .command)

            Button("新建无痕标签页") {
                session.createTab(isPrivate: true)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Button("重新打开最后关闭的标签页") {
                _ = session.reopenLastClosedTab()
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
            .disabled(!snapshot.canReopenClosedTab)

            Divider()

            Button("关闭标签页") {
                if let activeID = session.activeTabID {
                    session.closeTab(id: activeID)
                }
            }
            .keyboardShortcut("w", modifiers: .command)

            Button("关闭其他标签页") {
                session.closeOtherTabs()
            }
            .keyboardShortcut("w", modifiers: [.command, .option])
            .disabled(snapshot.tabCount <= 1)
        }

        CommandGroup(replacing: .saveItem) {
            Button("存储为...") {
                session.saveActiveTabAs()
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(snapshot.isActiveTabHome)
        }

        CommandGroup(replacing: .printItem) {
            Button("打印...") {
                session.printActiveTab()
            }
            .keyboardShortcut("p", modifiers: .command)
            .disabled(snapshot.isActiveTabHome)
        }

        CommandMenu("浏览") {
            Button("后退") {
                session.goBackActiveTab()
            }
            .keyboardShortcut("[", modifiers: .command)
            .disabled(!snapshot.canGoBack)

            Button("前进") {
                session.goForwardActiveTab()
            }
            .keyboardShortcut("]", modifiers: .command)
            .disabled(!snapshot.canGoForward)

            Button("前往主页") {
                session.goHomeActiveTab()
            }
            .keyboardShortcut("h", modifiers: [.command, .shift])
            .disabled(snapshot.isActiveTabHome)

            Divider()

            Button("重新载入此页") {
                session.reloadActiveTab()
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(snapshot.isActiveTabHome)

            Button("从原始位置重新载入") {
                session.reloadActiveTabFromOrigin()
            }
            .keyboardShortcut("r", modifiers: [.command, .option])
            .disabled(snapshot.isActiveTabHome)

            Button("强制重新载入此页 (忽略缓存)") {
                session.reloadActiveTabFromOrigin()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(snapshot.isActiveTabHome)

            Button("停止载入") {
                session.stopLoadingActiveTab()
            }
            .keyboardShortcut(".", modifiers: .command)
            .disabled(!snapshot.isLoading)

            Divider()

            Button("聚焦地址栏") {
                session.isOmniboxFocused = true
            }
            .keyboardShortcut("l", modifiers: .command)

            Button("拷贝当前网页链接") {
                session.copyActiveTabURL()
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(snapshot.isActiveTabHome)

            Button("显示下载内容") {
                DownloadManager.shared.isShowingPopover.toggle()
            }
            .keyboardShortcut("l", modifiers: [.command, .option])

            Divider()

            Button("在页面中查找...") {
                session.openFindBar()
            }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(snapshot.isActiveTabHome)

            Button("查找下一个") {
                session.findNext()
            }
            .keyboardShortcut("g", modifiers: .command)
            .disabled(snapshot.isActiveTabHome || !snapshot.hasFindQuery)

            Button("查找上一个") {
                session.findPrevious()
            }
            .keyboardShortcut("g", modifiers: [.command, .shift])
            .disabled(snapshot.isActiveTabHome || !snapshot.hasFindQuery)

            Divider()

            Button("实际大小") {
                session.resetZoomActiveTab()
            }
            .keyboardShortcut("0", modifiers: .command)
            .disabled(snapshot.isActiveTabHome)

            Button("放大") {
                session.zoomInActiveTab()
            }
            .keyboardShortcut("=", modifiers: .command)
            .disabled(snapshot.isActiveTabHome)

            Button("缩小") {
                session.zoomOutActiveTab()
            }
            .keyboardShortcut("-", modifiers: .command)
            .disabled(snapshot.isActiveTabHome)

            Divider()

            Button("显示上一个标签页") {
                session.selectPreviousTab()
            }
            .keyboardShortcut("[", modifiers: [.command, .shift])
            .disabled(snapshot.tabCount <= 1)

            Button("显示下一个标签页") {
                session.selectNextTab()
            }
            .keyboardShortcut("]", modifiers: [.command, .shift])
            .disabled(snapshot.tabCount <= 1)

            Divider()

            ForEach(0..<min(snapshot.tabCount, 8), id: \.self) { index in
                Button("切换到标签 \(index + 1)") {
                    guard index < session.tabs.count else { return }
                    session.selectTab(id: session.tabs[index].id)
                }
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }

            if snapshot.tabCount > 0 {
                Button("切换到最后一个标签页") {
                    session.selectLastTab()
                }
                .keyboardShortcut("9", modifiers: .command)
            }
        }

        CommandMenu("书签") {
            Button("添加/编辑当前页书签...") {
                _ = session.ensureActiveTabBookmarked()
                session.isShowingOmniboxBookmarkPopover = true
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(snapshot.isActiveTabHome)

            Button("书签管理器...") {
                session.openBookmarkManager()
            }
            .keyboardShortcut("b", modifiers: [.command, .option])

            Button("显示书签快捷弹窗") {
                session.openLibrary(tabIndex: 0)
            }
            .keyboardShortcut("b", modifiers: [.command, .shift])

            Divider()

            Button("导入书签 (HTML)...") {
                session.importBookmarksFromPanel()
            }

            Button("导出书签 (HTML)...") {
                session.exportBookmarksToPanel()
            }

            if !snapshot.bookmarkFolders.isEmpty || !snapshot.ungroupedBookmarks.isEmpty {
                Divider()

                ForEach(snapshot.bookmarkFolders) { folder in
                    Menu(folder.name) {
                        if folder.items.isEmpty {
                            Text("暂无书签")
                        } else {
                            ForEach(folder.items) { bm in
                                Button(bm.displayTitle) {
                                    session.navigate(to: bm.url)
                                }
                            }
                            Divider()
                            Button("全部在新标签页中打开 (\(folder.items.count))") {
                                session.openAllBookmarks(inFolder: folder.folderID)
                            }
                        }
                    }
                }

                ForEach(snapshot.ungroupedBookmarks) { bm in
                    Button(bm.displayTitle) {
                        session.navigate(to: bm.url)
                    }
                }
            }
        }

        CommandMenu("历史") {
            Button("显示所有历史记录") {
                session.openLibrary(tabIndex: 1)
            }
            .keyboardShortcut("y", modifiers: .command)

            if !snapshot.recentHistory.isEmpty {
                Divider()

                Section("最近访问") {
                    ForEach(snapshot.recentHistory) { item in
                        Button(item.displayTitle) {
                            session.openHistoryEntry(item.entry)
                        }
                    }
                }

                Divider()
            }

            Button("清空所有历史记录...") {
                session.clearHistory()
            }
            .disabled(snapshot.isHistoryEmpty)
        }

        CommandMenu("扩展") {
            Button("管理扩展程序...") {
                session.openExtensionManager()
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])

            if DistributionChannel.current.allowsExternalExtensionPackages {
                Button("新建自定义脚本 / 扩展...") {
                    session.extensionManager.isShowingCreatorSheet = true
                    session.openExtensionManager()
                }
                .keyboardShortcut("e", modifiers: [.command, .option])

                Divider()

                Button("加载已解压的扩展程序...") {
                    session.extensionManager.promptLoadUnpackedExtension()
                }

                Button("安装扩展程序包 (.crx / .zip / .user.js)...") {
                    session.extensionManager.promptInstallExtensionPackage()
                }

                Button("重新加载全部扩展") {
                    session.extensionManager.reloadAllExtensions()
                }
            }

            if !snapshot.enabledExtensions.isEmpty {
                Divider()

                Section("已启用的扩展") {
                    ForEach(snapshot.enabledExtensions) { ext in
                        Button(ext.name) {
                            session.extensionManager.triggerExtensionAction(id: ext.extensionID, in: session)
                        }
                    }
                }
            }
        }

        CommandMenu("个人资料") {
            Button("添加个人资料...") {
                session.isShowingCreateProfile = true
            }

            Button("编辑当前个人资料...") {
                session.isShowingProfileEditor = true
            }

            Button("管理个人资料...") {
                session.isShowingProfileManager = true
            }

            Divider()

            ForEach(snapshot.profiles) { profile in
                Button {
                    openProfileWindow(profile.profileID)
                } label: {
                    if profile.profileID == snapshot.focusedProfileID {
                        Text("✓ \(profile.displayName)")
                    } else {
                        Text(profile.displayName)
                    }
                }
            }
        }
    }
}

@main
public struct ZhuoBrowserMacApp: App {
    @NSApplicationDelegateAdaptor(ZhuoBrowserMacAppDelegate.self) private var appDelegate
    private let profileManager = ProfileManager.shared
    private let menuState = FocusedMenuState.shared
    @Environment(\.openWindow) private var openWindow

    public init() {
        guard !RuntimeEnvironment.isRunningUnitTests else { return }
        SingleInstanceGuard.shared.enforceSingleInstanceOrExit()
        // Migrate the retired private credential store (including its plaintext UserDefaults copy)
        // at launch, not only the first time the user focuses a login field.
        _ = CredentialStore.shared
    }

    private func openProfileWindow(_ id: UUID) {
        if !profileManager.focusExistingWindow(forProfileID: id) {
            openWindow(id: ProfileManager.windowGroupID, value: id)
        }
    }

    public var body: some Scene {
        WindowGroup(id: ProfileManager.windowGroupID, for: UUID.self) { $profileID in
            let targetSession = profileManager.session(for: profileID)
            MainWindowView(session: targetSession)
                .handlesExternalEvents(preferring: Set(["*"]), allowing: Set(["*"]))
                .onOpenURL { url in
                    profileManager.focusedSession.openExternalURL(url.absoluteString)
                }
        } defaultValue: {
            ProfileManager.shared.initialLaunchProfileID
        }
        .windowStyle(.hiddenTitleBar)
        .handlesExternalEvents(matching: Set(["*"]))
        .commands {
            BrowserMenuCommands(menuState: menuState, openProfileWindow: openProfileWindow)
        }
    }
}
