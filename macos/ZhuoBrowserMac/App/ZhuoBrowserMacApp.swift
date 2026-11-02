import AppKit
import SwiftUI

/// Captures the live page snapshots on quit so the next launch can restore every
/// tab — including tabs that were never frozen — without a single reload.
///
/// It also flushes WebKit's *session* cookies (the ones that only live in the network
/// process memory). Without this, quitting or updating the app signs the user out of
/// every website.
final class ZhuoBrowserMacAppDelegate: NSObject, NSApplicationDelegate {
    private var signalSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !RuntimeEnvironment.isRunningUnitTests else { return }
        DefaultBrowserManager.shared.ensureRegisteredWithLaunchServices()
        DefaultBrowserManager.shared.refreshStatus()
        installTerminationSignalHandlers()
        handleInitialLaunchArguments()
        Task { @MainActor in
            _ = HomeBackgroundManager.shared
            _ = FavoritesManager.shared
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard !RuntimeEnvironment.isRunningUnitTests else { return }
        for url in urls {
            BrowserSession.shared.openExternalURL(url.absoluteString)
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
        CookieSessionStore.shared.persistSessionCookies()
        WebSessionStorageStore.shared.flushAsync()
        BrowserSession.shared.captureSessionOnResignActive()
    }

    func applicationWillTerminate(_ notification: Notification) {
        SingleInstanceGuard.shared.releaseLock()
        flushAllStateForTermination()
    }

    private func handleInitialLaunchArguments() {
        let urls = SingleInstanceGuard.extractURLs(from: CommandLine.arguments)
        for url in urls {
            BrowserSession.shared.openExternalURL(url)
        }
    }

    private func flushAllStateForTermination() {
        BrowserSettings.shared.flushSynchronously()
        CookieSessionStore.shared.persistSessionCookiesSynchronously()
        WebSessionStorageStore.shared.flushSynchronously()
        BrowserSession.shared.captureSessionForTermination(synchronously: true)
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
}

@main
public struct ZhuoBrowserMacApp: App {
    @NSApplicationDelegateAdaptor(ZhuoBrowserMacAppDelegate.self) private var appDelegate
    private let session = BrowserSession.shared

    /// How many of the most recent visits are listed directly in the History menu.
    private static let recentHistoryLimit = 10

    public init() {
        guard !RuntimeEnvironment.isRunningUnitTests else { return }
        SingleInstanceGuard.shared.enforceSingleInstanceOrExit()
    }

    public var body: some Scene {
        WindowGroup {
            MainWindowView(session: session)
                .onOpenURL { url in
                    session.openExternalURL(url.absoluteString)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
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
                .disabled(!session.canReopenClosedTab)

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
                .disabled(session.tabs.count <= 1)
            }

            CommandMenu("浏览") {
                Button("后退") {
                    session.goBackActiveTab()
                }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(!(session.activeTab?.canGoBack ?? false))

                Button("前进") {
                    session.goForwardActiveTab()
                }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(!(session.activeTab?.canGoForward ?? false))

                Button("前往主页") {
                    session.goHomeActiveTab()
                }
                .keyboardShortcut("h", modifiers: [.command, .shift])
                .disabled(session.activeTab?.isHome ?? true)

                Divider()

                Button("重新载入此页") {
                    session.reloadActiveTab()
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(session.activeTab?.isHome ?? true)

                Button("从原始位置重新载入") {
                    session.reloadActiveTabFromOrigin()
                }
                .keyboardShortcut("r", modifiers: [.command, .option])
                .disabled(session.activeTab?.isHome ?? true)

                Button("强制重新载入此页 (忽略缓存)") {
                    session.reloadActiveTabFromOrigin()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(session.activeTab?.isHome ?? true)

                Button("停止载入") {
                    session.stopLoadingActiveTab()
                }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(!(session.activeTab?.isLoading ?? false))

                Divider()

                Button("聚焦地址栏") {
                    session.isOmniboxFocused = true
                }
                .keyboardShortcut("l", modifiers: .command)

                Button("拷贝当前网页链接") {
                    session.copyActiveTabURL()
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(session.activeTab?.isHome ?? true)

                Button("显示下载内容") {
                    DownloadManager.shared.isShowingPopover.toggle()
                }
                .keyboardShortcut("l", modifiers: [.command, .option])

                Divider()

                Button("实际大小") {
                    session.resetZoomActiveTab()
                }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(session.activeTab?.isHome ?? true)

                Button("放大") {
                    session.zoomInActiveTab()
                }
                .keyboardShortcut("=", modifiers: .command)
                .disabled(session.activeTab?.isHome ?? true)

                Button("缩小") {
                    session.zoomOutActiveTab()
                }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(session.activeTab?.isHome ?? true)

                Divider()

                Button("显示上一个标签页") {
                    session.selectPreviousTab()
                }
                .keyboardShortcut("[", modifiers: [.command, .shift])
                .disabled(session.tabs.count <= 1)

                Button("显示下一个标签页") {
                    session.selectNextTab()
                }
                .keyboardShortcut("]", modifiers: [.command, .shift])
                .disabled(session.tabs.count <= 1)

                Divider()

                ForEach(0..<min(session.tabs.count, 8), id: \.self) { index in
                    Button("切换到标签 \(index + 1)") {
                        session.selectTab(id: session.tabs[index].id)
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                }

                if !session.tabs.isEmpty {
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
                .disabled(session.activeTab?.isHome ?? true)

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

                if !session.bookmarkFolders.isEmpty || !session.ungroupedBookmarks.isEmpty {
                    Divider()

                    ForEach(session.bookmarkFolders) { folder in
                        let items = session.bookmarks(inFolder: folder.id)
                        Menu(folder.name) {
                            if items.isEmpty {
                                Text("暂无书签")
                            } else {
                                ForEach(items) { bm in
                                    Button(bm.displayTitle) {
                                        session.navigate(to: bm.url)
                                    }
                                }
                                Divider()
                                Button("全部在新标签页中打开 (\(items.count))") {
                                    session.openAllBookmarks(inFolder: folder.id)
                                }
                            }
                        }
                    }

                    ForEach(session.ungroupedBookmarks.prefix(15)) { bm in
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

                let recentHistory = Array(session.history.prefix(Self.recentHistoryLimit))

                if !recentHistory.isEmpty {
                    Divider()

                    Section("最近访问") {
                        ForEach(recentHistory) { entry in
                            Button(entry.displayTitle) {
                                session.openHistoryEntry(entry)
                            }
                        }
                    }

                    Divider()
                }

                Button("清空所有历史记录...") {
                    session.clearHistory()
                }
                .disabled(session.history.isEmpty)
            }

            CommandMenu("扩展") {
                Button("管理扩展程序...") {
                    session.openExtensionManager()
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])

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

                if !session.extensionManager.enabledExtensions.isEmpty {
                    Divider()

                    Section("已启用的扩展") {
                        ForEach(session.extensionManager.enabledExtensions) { ext in
                            Button(ext.manifest.name) {
                                session.extensionManager.triggerExtensionAction(id: ext.id, in: session)
                            }
                        }
                    }
                }
            }
        }
    }
}
