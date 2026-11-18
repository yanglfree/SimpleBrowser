import SwiftUI

/// Main window view composing the toolbar, tab strip, and content viewport.
public struct MainWindowView: View {
    @ObservedObject var session: BrowserSession
    @ObservedObject private var profileManager = ProfileManager.shared

    private var isHomeActive: Bool {
        session.activeTab?.isHome ?? true
    }

    private var currentProfile: BrowserProfile {
        profileManager.profile(for: session.profileID)
    }

    /// Window menu and Mission Control read the window title. Home tabs show the
    /// product name instead of the generic "新标签页" so the chrome never presents
    /// a second, competing brand. When multiple profiles exist, append the profile
    /// name so separate Google account windows are easy to tell apart.
    private var windowTitle: String {
        let baseTitle: String
        if let tab = session.activeTab, !tab.isHome {
            baseTitle = tab.displayTitle
        } else {
            baseTitle = "Zhuo浏览器"
        }
        if profileManager.profiles.count > 1 || !currentProfile.isDefault {
            return "\(baseTitle) — \(currentProfile.displayName)"
        }
        return baseTitle
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
        .background(WindowConfigurator(profileID: session.profileID))
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(isPresented: $session.isShowingSettings) {
            SettingsView(session: session, isPresented: $session.isShowingSettings)
        }
        .onAppear {
            if session.isDefaultProfile && AccountManager.shared.isLoggedIn {
                Task {
                    await AccountManager.shared.syncWithCloud(session: session)
                }
            }
        }
    }
}
