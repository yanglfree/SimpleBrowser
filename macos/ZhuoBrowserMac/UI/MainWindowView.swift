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

            // Find-in-Page Bar (Cmd+F)
            if session.isShowingFindBar && !isHomeActive {
                FindBarView(session: session)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

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

                if let tab = session.activeTab,
                   !isHomeActive,
                   let errorDescription = tab.loadErrorDescription {
                    LoadErrorOverlayView(
                        urlString: tab.url,
                        errorMessage: errorDescription,
                        onRetry: { session.reloadActiveTab() },
                        onGoHome: { session.goHomeActiveTab() }
                    )
                }

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

/// Compact native Find-in-Page toolbar (`Cmd+F`).
private struct FindBarView: View {
    @ObservedObject var session: BrowserSession
    @FocusState private var isInputFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                TextField("在页面中查找...", text: $session.findQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .frame(width: 220)
                    .focused($isInputFocused)
                    .onSubmit {
                        session.findNext()
                    }
                    .onChange(of: session.findQuery) { newQuery in
                        if !newQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            session.findNext()
                        }
                    }

                if !session.findQuery.isEmpty {
                    Button(action: { session.findQuery = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
            )

            Button(action: { session.findPrevious() }) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.borderless)
            .disabled(session.findQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help("查找上一个 (Cmd+Shift+G)")

            Button(action: { session.findNext() }) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.borderless)
            .disabled(session.findQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help("查找下一个 (Cmd+G)")

            Button("完成") {
                session.closeFindBar()
            }
            .controlSize(.small)
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(Divider(), alignment: .bottom)
        .onAppear {
            isInputFocused = true
        }
    }
}

/// Native fallback error surface displayed when a main-frame navigation fails.
private struct LoadErrorOverlayView: View {
    let urlString: String
    let errorMessage: String
    let onRetry: () -> Void
    let onGoHome: () -> Void

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)

            VStack(spacing: 16) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 40))
                    .foregroundColor(.secondary)

                Text("无法打开此页面")
                    .font(.system(size: 20, weight: .bold))

                Text(errorMessage)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)

                if !urlString.isEmpty {
                    Text(urlString)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.85))
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.secondary.opacity(0.08))
                        .cornerRadius(6)
                        .frame(maxWidth: 460)
                }

                HStack(spacing: 12) {
                    Button("返回主页") {
                        onGoHome()
                    }
                    .controlSize(.large)

                    Button("重新加载") {
                        onRetry()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .padding(.top, 4)
            }
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
