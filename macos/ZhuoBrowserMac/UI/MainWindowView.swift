import SwiftUI

/// Main window view composing the toolbar, tab strip, and content viewport.
public struct MainWindowView: View {
    @ObservedObject var session: BrowserSession

    private var isHomeActive: Bool {
        session.activeTab?.isHome ?? true
    }

    /// Window menu and Mission Control read the window title. Home tabs show the
    /// product name instead of the generic "新标签页" so the chrome never presents
    /// a second, competing brand.
    private var windowTitle: String {
        guard let tab = session.activeTab, !tab.isHome else { return "Zhuo浏览器" }
        return tab.displayTitle
    }

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
                    .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                    .animation(.easeInOut(duration: 0.15), value: tab.loadingProgress)
            }

            // Content Viewport
            //
            // The web host stays mounted for the lifetime of the window. Giving it a
            // per-tab `.id()` used to rebuild the NSView on every switch, which tore
            // the WebView out of its hierarchy and made tab changes feel like a reload.
            // Now switching only re-parents the already-rendered WebView.
            ZStack {
                WebContainerView(controller: session.activeController)
                    .opacity(isHomeActive ? 0 : 1)
                    .allowsHitTesting(!isHomeActive)
                    .accessibilityHidden(isHomeActive)

                MinimalStartView(session: session)
                    .opacity(isHomeActive ? 1 : 0)
                    .allowsHitTesting(isHomeActive)
                    .accessibilityHidden(!isHomeActive)
            }
            .animation(.easeInOut(duration: 0.14), value: isHomeActive)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 700, minHeight: 480)
        .navigationTitle(windowTitle)
        .ignoresSafeArea(.all, edges: .top)
        .background(WindowConfigurator())
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(isPresented: $session.isShowingSettings) {
            SettingsView(session: session, isPresented: $session.isShowingSettings)
        }
        .onAppear {
            if AccountManager.shared.isLoggedIn {
                Task {
                    await AccountManager.shared.syncWithCloud(session: session)
                }
            }
        }
    }
}
