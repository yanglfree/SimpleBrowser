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
        installTerminationSignalHandlers()
        handleInitialLaunchArguments()
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
        WebSessionStorageStore.shared.flushSynchronously()
        BrowserSession.shared.captureSessionForTermination()
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
    @StateObject private var session = BrowserSession.shared

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

                Button("关闭标签页") {
                    if let activeID = session.activeTabID {
                        session.closeTab(id: activeID)
                    }
                }
                .keyboardShortcut("w", modifiers: .command)
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

                Button("重新载入此页") {
                    session.reloadActiveTab()
                }
                .keyboardShortcut("r", modifiers: .command)

                Button("聚焦地址栏") {
                    session.isOmniboxFocused = true
                }
                .keyboardShortcut("l", modifiers: .command)

                Divider()

                ForEach(0..<min(session.tabs.count, 9), id: \.self) { index in
                    Button("切换到标签 \(index + 1)") {
                        session.selectTab(id: session.tabs[index].id)
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                }
            }

            CommandMenu("书签") {
                Button("添加/移除书签") {
                    session.toggleBookmarkForActiveTab()
                }
                .keyboardShortcut("d", modifiers: .command)
                .disabled(session.activeTab?.isHome ?? true)

                Divider()

                Button("显示所有书签") {
                    session.openLibrary(tabIndex: 0)
                }
                .keyboardShortcut("b", modifiers: [.command, .option])
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
        }
    }
}
