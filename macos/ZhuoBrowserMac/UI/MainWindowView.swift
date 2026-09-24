import SwiftUI

/// Main window view composing the toolbar, tab strip, and content viewport.
public struct MainWindowView: View {
    @ObservedObject var session: BrowserSession

    public var body: some View {
        VStack(spacing: 0) {
            // Unified Minimal Toolbar
            UnifiedToolbarView(session: session)

            // Compact Tab Strip
            CompactTabBarView(session: session)

            // Slim Page Loading Progress Bar
            if let tab = session.activeTab, tab.isLoading {
                ProgressView(value: max(0.05, tab.loadingProgress), total: 1.0)
                    .progressViewStyle(.linear)
                    .frame(height: 2)
                    .tint(.accentColor)
            }

            // Content Viewport
            ZStack {
                if let activeTab = session.activeTab, !activeTab.isHome {
                    WebContainerView(controller: session.activeController)
                        .id(activeTab.id)
                } else {
                    MinimalStartView(session: session)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 700, minHeight: 480)
        .background(Color(NSColor.windowBackgroundColor))
    }
}
