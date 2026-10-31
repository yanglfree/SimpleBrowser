import SwiftUI

@main
public struct ZhuoBrowserMacApp: App {
    @StateObject private var session = BrowserSession.shared

    public init() {}

    public var body: some Scene {
        WindowGroup {
            MainWindowView(session: session)
                .navigationTitle("")
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

                Divider()

                Button("清空所有历史记录...") {
                    session.clearHistory()
                }
                .disabled(session.history.isEmpty)
            }
        }
    }
}
