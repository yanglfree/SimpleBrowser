import SwiftUI

/// Unified minimalist macOS toolbar containing navigation, omnibox, and status indicators.
public struct UnifiedToolbarView: View {
    @ObservedObject var session: BrowserSession
    @ObservedObject private var accountManager = AccountManager.shared
    @FocusState private var isOmniboxFocused: Bool
    @State private var currentText: String = ""
    @State private var isShowingSettings: Bool = false
    @State private var isShowingAccount: Bool = false
    @State private var isFullScreen: Bool = false

    private var activeTab: BrowserTab? {
        session.activeTab
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 8) {
            // Window Traffic Lights spacer for macOS full-size content view
            if !isFullScreen {
                Spacer()
                    .frame(width: 70)
            }

            // Navigation Buttons
            HStack(spacing: 4) {
                Button(action: { session.goBackActiveTab() }) {
                    Image(systemName: "chevron.backward")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(ToolbarHoverButtonStyle())
                .disabled(!(activeTab?.canGoBack ?? false))
                .foregroundColor((activeTab?.canGoBack ?? false) ? .primary : .secondary.opacity(0.4))
                .frame(width: 24, height: 24)
                .help("后退 (Cmd+[)")

                Button(action: { session.goForwardActiveTab() }) {
                    Image(systemName: "chevron.forward")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(ToolbarHoverButtonStyle())
                .disabled(!(activeTab?.canGoForward ?? false))
                .foregroundColor((activeTab?.canGoForward ?? false) ? .primary : .secondary.opacity(0.4))
                .frame(width: 24, height: 24)
                .help("前进 (Cmd+])")

                Button(action: { session.reloadActiveTab() }) {
                    Image(systemName: (activeTab?.isLoading ?? false) ? "xmark" : "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(ToolbarHoverButtonStyle())
                .disabled(activeTab?.isHome ?? true)
                .foregroundColor((activeTab?.isHome ?? true) ? .secondary.opacity(0.4) : .primary)
                .frame(width: 24, height: 24)
                .help("刷新 (Cmd+R)")
            }

            // Omnibox (Address & Search Bar)
            HStack(spacing: 6) {
                // Security / Status Icon
                if let tab = activeTab, !tab.isHome {
                    Image(systemName: tab.url.hasPrefix("https://") ? "lock.fill" : "globe")
                        .font(.system(size: 11))
                        .foregroundColor(tab.url.hasPrefix("https://") ? .secondary : .orange)
                } else {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                TextField("搜索或输入网址", text: $currentText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($isOmniboxFocused)
                    .onSubmit {
                        submitNavigation()
                    }

                // Bookmark star toggle button
                if let tab = activeTab, !tab.isHome, !tab.url.isEmpty {
                    let isBookmarked = session.isBookmarked(url: tab.url)
                    Button(action: {
                        session.toggleBookmarkForActiveTab()
                    }) {
                        Image(systemName: isBookmarked ? "star.fill" : "star")
                            .font(.system(size: 12))
                            .foregroundColor(isBookmarked ? .yellow : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help(isBookmarked ? "已收藏至书签 (点击移除)" : "添加到书签 (Cmd+D)")
                }

                // Ad blocker shield indicator
                if session.settings.adBlockEnabled {
                    Image(systemName: "shield.checkered")
                        .font(.system(size: 12))
                        .foregroundColor(.accentColor)
                        .help("原生规则去广告与追踪保护已开启")
                }

                if isOmniboxFocused && !currentText.isEmpty {
                    Button(action: { currentText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)

                    Button(action: submitNavigation) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 13))
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .help("前往")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isOmniboxFocused ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: isOmniboxFocused ? 1.5 : 1)
            )

            // Memory Saver Badge
            MemorySaverBadge(session: session)

            // Library (Bookmarks & History) Button
            Button(action: { session.openLibrary() }) {
                Image(systemName: "book")
                    .font(.system(size: 13))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(ToolbarHoverButtonStyle())
            .help("书签与历史记录 (Cmd+Y / Cmd+Option+B)")

            // New Tab Button
            Button(action: { session.createTab() }) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(ToolbarHoverButtonStyle())
            .help("新建标签页 (Cmd+T)")

            // Preferences
            Button(action: { session.isShowingSettings.toggle() }) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 13))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(ToolbarHoverButtonStyle())
            .help("偏好设置 (Cmd+,)")

            // User Account Button
            Button(action: { isShowingAccount.toggle() }) {
                if accountManager.isLoggedIn {
                    if let avatarURL = accountManager.currentUser?.resolvedAvatarURL {
                        AsyncImage(url: avatarURL) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 24, height: 24)
                                    .clipShape(Circle())
                            default:
                                toolbarInitialsAvatar
                            }
                        }
                        .frame(width: 24, height: 24)
                    } else {
                        toolbarInitialsAvatar
                    }
                } else {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 14))
                        .frame(width: 24, height: 24)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(ToolbarHoverButtonStyle())
            .help(accountManager.isLoggedIn ? "账号中心 (\(accountManager.currentUser?.displayName ?? ""))" : "登录 / 注册账号")
            .sheet(isPresented: $isShowingAccount) {
                AccountView(session: session, isPresented: $isShowingAccount)
            }
            .sheet(isPresented: $session.isShowingLibraryManager) {
                LibraryManagerView(session: session, isPresented: $session.isShowingLibraryManager)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(height: 38)
        .background(
            ZStack {
                Color(NSColor.windowBackgroundColor)
                WindowDragBackground()
            }
        )
        .overlay(
            Divider(),
            alignment: .bottom
        )
        .onAppear {
            syncDisplayAddress()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                isFullScreen = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                isFullScreen = false
            }
        }
        .onChange(of: activeTab?.url) { _ in
            if !isOmniboxFocused {
                syncDisplayAddress()
            }
        }
        .onChange(of: isOmniboxFocused) { focused in
            session.isOmniboxFocused = focused
            if focused {
                if activeTab?.isHome == true {
                    currentText = ""
                } else {
                    currentText = activeTab?.url ?? ""
                }
            } else {
                syncDisplayAddress()
            }
        }
        .onChange(of: session.isOmniboxFocused) { focused in
            if isOmniboxFocused != focused {
                isOmniboxFocused = focused
            }
        }
    }

    private func syncDisplayAddress() {
        if let tab = activeTab, !tab.isHome {
            currentText = URLPolicy.displayAddress(for: tab.url)
        } else {
            currentText = ""
        }
    }

    private func submitNavigation() {
        isOmniboxFocused = false
        session.isOmniboxFocused = false
        let textToNavigate = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !textToNavigate.isEmpty else { return }
        session.navigate(to: textToNavigate)
    }

    private var toolbarInitialsAvatar: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.2))
                .frame(width: 24, height: 24)

            Text(accountManager.currentUser?.displayName.prefix(1).uppercased() ?? "U")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.accentColor)
        }
    }
}

/// Dynamic button style with smooth spring hover and tactile press feedback.
private struct ToolbarHoverButtonStyle: ButtonStyle {
    @State private var isHovered: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(configuration.isPressed ? Color.secondary.opacity(0.18) : (isHovered ? Color.secondary.opacity(0.1) : Color(nsColor: .clear)))
            )
            .scaleEffect(configuration.isPressed ? 0.92 : (isHovered ? 1.05 : 1.0))
            .animation(.spring(response: 0.22, dampingFraction: 0.75), value: isHovered)
            .animation(.spring(response: 0.15, dampingFraction: 0.75), value: configuration.isPressed)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}
