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
        .windowToolbarStyle(.unifiedCompact)
        .commands {
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

                Divider()

                ForEach(0..<min(session.tabs.count, 9), id: \.self) { index in
                    Button("切换到标签 \(index + 1)") {
                        session.selectTab(id: session.tabs[index].id)
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                }
            }
        }
    }
}
