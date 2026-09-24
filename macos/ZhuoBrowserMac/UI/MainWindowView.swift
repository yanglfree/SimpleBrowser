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
