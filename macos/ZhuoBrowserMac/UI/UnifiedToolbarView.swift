import SwiftUI

/// Unified minimalist macOS toolbar containing navigation, omnibox, and status indicators.
public struct UnifiedToolbarView: View {
    @ObservedObject var session: BrowserSession
    @ObservedObject private var profileManager = ProfileManager.shared
    @ObservedObject private var accountManager = AccountManager.shared
    @ObservedObject private var downloadManager = DownloadManager.shared
    @ObservedObject private var extensionManager = ExtensionManager.shared
    @Environment(\.openWindow) private var openWindow
    @State private var isOmniboxFocused: Bool = false
    @State private var currentText: String = ""
    @State private var isShowingSettings: Bool = false
    @State private var isShowingProfilePopover: Bool = false
    @State private var isShowingShieldPopover: Bool = false
    @State private var isFullScreen: Bool = false

    private var activeTab: BrowserTab? {
        session.activeTab
    }

    private var currentProfile: BrowserProfile {
        profileManager.profile(for: session.profileID)
    }

    private var showsProfileNamePill: Bool {
        profileManager.profiles.count > 1 || !currentProfile.isDefault
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 8) {
            // Window Traffic Lights drag area for macOS full-size content view
            if !isFullScreen {
                WindowDragBackground()
                    .frame(width: 70, height: 28)
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

                Button(action: {
                    if activeTab?.isLoading == true {
                        session.stopLoadingActiveTab()
                    } else if NSEvent.modifierFlags.intersection([.option, .shift]).isEmpty == false {
                        session.reloadActiveTabFromOrigin()
                    } else {
                        session.reloadActiveTab()
                    }
                }) {
                    Image(systemName: (activeTab?.isLoading ?? false) ? "xmark" : "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(ToolbarHoverButtonStyle())
                .disabled(activeTab?.isHome ?? true)
                .foregroundColor((activeTab?.isHome ?? true) ? .secondary.opacity(0.4) : .primary)
                .frame(width: 24, height: 24)
                .help((activeTab?.isLoading ?? false) ? "停止载入 (Cmd+.)" : "重新载入 (Cmd+R) · 强制刷新 (Cmd+Option+R)")
            }

            // Omnibox (Address & Search Bar with 1/3 reduced width and balanced side spacing)
            GeometryReader { geometry in
                let omniboxWidth = geometry.size.width * (2.0 / 3.0)
                HStack(spacing: 0) {
                    WindowDragBackground()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    omniboxView
                        .frame(width: omniboxWidth)

                    WindowDragBackground()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .frame(height: 28)

            // Memory Saver Badge
            MemorySaverBadge(session: session)

            // Chrome-Style Extensions Toolbar Bar (Pinned Actions + Puzzle Menu)
            ExtensionToolbarBarView(session: session, extensionManager: extensionManager)

            // On-Demand Downloads Button (Safari / Mainstream Browser style)
            if downloadManager.shouldShowToolbarButton {
                Button(action: { downloadManager.isShowingPopover.toggle() }) {
                    ZStack {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 13))

                        if let progress = downloadManager.overallProgress {
                            Circle()
                                .trim(from: 0, to: CGFloat(progress))
                                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                                .frame(width: 17, height: 17)
                        }
                    }
                    .frame(width: 24, height: 24)
                }
                .buttonStyle(ToolbarHoverButtonStyle())
                .help("下载内容 (Cmd+Option+L)")
                .transition(.scale(scale: 0.85).combined(with: .opacity))
                .popover(
                    isPresented: $downloadManager.isShowingPopover,
                    attachmentAnchor: .rect(.bounds),
                    arrowEdge: .bottom
                ) {
                    DownloadsPopoverView(downloadManager: downloadManager, session: session)
                }
            }

            // Library (Bookmarks & History) Button — anchored Popover
            Button(action: { session.toggleLibrary() }) {
                Image(systemName: "book")
                    .font(.system(size: 13))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(ToolbarHoverButtonStyle())
            .help("书签与历史记录 (Cmd+Y / Cmd+Option+B)")
            .popover(
                isPresented: $session.isShowingLibraryManager,
                attachmentAnchor: .rect(.bounds),
                arrowEdge: .bottom
            ) {
                LibraryManagerView(session: session, isPresented: $session.isShowingLibraryManager)
            }

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

            // Chrome-Style Profile Switcher & Account Button
            Button(action: { isShowingProfilePopover.toggle() }) {
                HStack(spacing: 5) {
                    if profileManager.profiles.count == 1 && currentProfile.isDefault && accountManager.isLoggedIn {
                        if let cachedImage = accountManager.avatarImage {
                            Image(nsImage: cachedImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 22, height: 22)
                                .clipShape(Circle())
                        } else {
                            ProfileAvatarBadge(profile: currentProfile, size: 22)
                        }
                    } else {
                        ProfileAvatarBadge(profile: currentProfile, size: 22)
                    }

                    if showsProfileNamePill {
                        Text(currentProfile.displayName)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .frame(maxWidth: 80, alignment: .leading)
                    }
                }
                .padding(.horizontal, showsProfileNamePill ? 6 : 2)
                .frame(height: 24)
                .background(
                    showsProfileNamePill
                        ? AnyView(Capsule().fill(currentProfile.tintColor.opacity(0.14)))
                        : AnyView(Color.clear)
                )
            }
            .buttonStyle(ToolbarHoverButtonStyle())
            .help("个人资料：\(currentProfile.displayName) · 点击切换或新建独立账号窗口")
            .popover(
                isPresented: $isShowingProfilePopover,
                attachmentAnchor: .rect(.bounds),
                arrowEdge: .bottom
            ) {
                ProfileSwitcherPopoverView(
                    session: session,
                    profileManager: profileManager,
                    isPresented: $isShowingProfilePopover
                ) { targetProfileID in
                    openProfileWindow(targetProfileID)
                }
            }
            .sheet(isPresented: $session.isShowingAccountSheet) {
                AccountView(session: session, isPresented: $session.isShowingAccountSheet)
            }
            .sheet(isPresented: $session.isShowingProfileManager) {
                ProfileManagerSheetView(
                    session: session,
                    profileManager: profileManager,
                    isPresented: $session.isShowingProfileManager
                ) { targetProfileID in
                    openProfileWindow(targetProfileID)
                }
            }
            .sheet(isPresented: $session.isShowingCreateProfile) {
                ProfileEditorSheetView(
                    profileManager: profileManager,
                    mode: .create,
                    isPresented: $session.isShowingCreateProfile
                ) { newProfileID in
                    openProfileWindow(newProfileID)
                }
            }
            .sheet(isPresented: $session.isShowingProfileEditor) {
                ProfileEditorSheetView(
                    profileManager: profileManager,
                    mode: .edit(currentProfile),
                    isPresented: $session.isShowingProfileEditor
                )
            }
            .sheet(isPresented: $session.isShowingBookmarkManager) {
                BookmarkManagerView(session: session, isPresented: $session.isShowingBookmarkManager)
            }
            .sheet(isPresented: $extensionManager.isShowingExtensionManager) {
                ExtensionManagerView(
                    session: session,
                    extensionManager: extensionManager,
                    isPresented: $extensionManager.isShowingExtensionManager
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(height: 38)
        .background(Color(NSColor.windowBackgroundColor))
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
        .onChange(of: activeTab?.id) { _ in
            session.dismissOmniboxSuggestions()
            if isOmniboxFocused {
                isOmniboxFocused = false
            }
            syncDisplayAddress()
        }
        .onChange(of: activeTab?.url) { _ in
            if !isOmniboxFocused {
                syncDisplayAddress()
            }
        }
        .onChange(of: isOmniboxFocused) { focused in
            if focused {
                let displayed = activeTab.map { URLPolicy.displayAddress(for: $0.url) } ?? ""
                if currentText == displayed {
                    if activeTab?.isHome == true {
                        currentText = ""
                    } else {
                        currentText = URLPolicy.upgradeToHTTPSIfPublicHost(activeTab?.url ?? "")
                    }
                }
            } else {
                session.dismissOmniboxSuggestions()
                syncDisplayAddress()
            }
            if session.isOmniboxFocused != focused {
                DispatchQueue.main.async {
                    session.isOmniboxFocused = focused
                }
            }
        }
        .onChange(of: session.isOmniboxFocused) { focused in
            if isOmniboxFocused != focused {
                isOmniboxFocused = focused
            }
        }
    }

    @ViewBuilder
    private var omniboxView: some View {
        HStack(spacing: 6) {
            // Security / Status Icon (clickable to focus omnibox)
            Group {
                if let tab = activeTab, !tab.isHome {
                    Image(systemName: tab.url.hasPrefix("https://") ? "lock.fill" : "globe")
                        .font(.system(size: 11))
                        .foregroundColor(tab.url.hasPrefix("https://") ? .secondary : .orange)
                } else {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                isOmniboxFocused = true
            }

            MacOmniboxTextField(
                text: $currentText,
                isFocused: $isOmniboxFocused,
                placeholder: "搜索或输入网址",
                font: .systemFont(ofSize: 13),
                textColor: .labelColor,
                inlineCompletionProvider: { query in
                    session.inlineCompletion(for: query)
                },
                onUserInput: { query in
                    session.updateOmniboxSuggestions(for: query)
                },
                onMoveSelection: { delta in
                    handleMoveSuggestionSelection(delta: delta)
                },
                onAcceptSuggestion: {
                    handleAcceptSelectedSuggestion()
                },
                onCancelSuggestions: {
                    if session.isShowingOmniboxSuggestions {
                        session.dismissOmniboxSuggestions()
                        return true
                    }
                    return false
                },
                onSubmit: { committed in
                    submitNavigation(with: committed)
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Bookmark star button with quick folder & edit popover
            if let tab = activeTab, !tab.isHome, !tab.url.isEmpty {
                let isBookmarked = session.isBookmarked(url: tab.url)
                Button(action: {
                    _ = session.ensureActiveTabBookmarked()
                    session.isShowingOmniboxBookmarkPopover = true
                }) {
                    Image(systemName: isBookmarked ? "star.fill" : "star")
                        .font(.system(size: 12))
                        .foregroundColor(isBookmarked ? .yellow : .secondary)
                }
                .buttonStyle(.plain)
                .help(isBookmarked ? "编辑此书签或修改所属分组 (Cmd+D)" : "添加到书签并选择分组 (Cmd+D)")
                .popover(
                    isPresented: $session.isShowingOmniboxBookmarkPopover,
                    attachmentAnchor: .rect(.bounds),
                    arrowEdge: .bottom
                ) {
                    OmniboxBookmarkPopoverView(
                        session: session,
                        isPresented: $session.isShowingOmniboxBookmarkPopover
                    )
                }
            }

            // Ad blocker shield button with per-site allowlist popover
            if session.settings.adBlockEnabled {
                let isHostAllowlisted = session.isActiveTabHostAllowlisted
                Button(action: { isShowingShieldPopover.toggle() }) {
                    Image(systemName: isHostAllowlisted ? "shield.slash" : "shield.checkered")
                        .font(.system(size: 12))
                        .foregroundColor(isHostAllowlisted ? .secondary : .accentColor)
                }
                .buttonStyle(.plain)
                .help(isHostAllowlisted ? "已在此站点暂停拦截 · 点击恢复" : "原生规则去广告与追踪保护已开启 · 点击管理站点例外")
                .popover(
                    isPresented: $isShowingShieldPopover,
                    attachmentAnchor: .rect(.bounds),
                    arrowEdge: .bottom
                ) {
                    AdShieldPopoverView(
                        session: session,
                        isPresented: $isShowingShieldPopover
                    )
                }
            }

            if isOmniboxFocused && !currentText.isEmpty {
                Button(action: {
                    currentText = ""
                    session.dismissOmniboxSuggestions()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                Button(action: { submitNavigation() }) {
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
        .frame(height: 28)
        .background(
            Color(NSColor.textBackgroundColor)
                .background(
                    OmniboxDropdownAnchorView(
                        session: session,
                        suggestions: session.omniboxSuggestions,
                        selectedIndex: session.selectedOmniboxSuggestionIndex,
                        isPresented: isOmniboxFocused && session.isShowingOmniboxSuggestions && !session.omniboxSuggestions.isEmpty,
                        onSelect: { suggestion in
                            isOmniboxFocused = false
                            session.commitOmniboxSuggestion(suggestion)
                            syncDisplayAddress()
                        },
                        onDismiss: {
                            session.dismissOmniboxSuggestions()
                            isOmniboxFocused = false
                            session.isOmniboxFocused = false
                        }
                    )
                )
        )
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isOmniboxFocused ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: isOmniboxFocused ? 1.5 : 1)
        )
    }

    private func handleMoveSuggestionSelection(delta: Int) -> Bool {
        if !session.isShowingOmniboxSuggestions {
            let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return false }
            session.updateOmniboxSuggestions(for: trimmed)
            return session.isShowingOmniboxSuggestions
        }

        let count = session.omniboxSuggestions.count
        guard count > 0 else { return false }

        let currentIndex = session.selectedOmniboxSuggestionIndex
        let nextIndex: Int
        if currentIndex < 0 {
            nextIndex = delta > 0 ? 0 : (count - 1)
        } else {
            nextIndex = (currentIndex + delta + count) % count
        }

        session.selectedOmniboxSuggestionIndex = nextIndex
        currentText = session.omniboxSuggestions[nextIndex].completionText
        return true
    }

    private func handleAcceptSelectedSuggestion() -> Bool {
        guard session.isShowingOmniboxSuggestions,
              session.selectedOmniboxSuggestionIndex >= 0,
              session.selectedOmniboxSuggestionIndex < session.omniboxSuggestions.count else {
            return false
        }
        let chosen = session.omniboxSuggestions[session.selectedOmniboxSuggestionIndex]
        currentText = chosen.completionText
        session.updateOmniboxSuggestions(for: chosen.completionText)
        return true
    }

    private func syncDisplayAddress() {
        if let tab = activeTab, !tab.isHome {
            currentText = URLPolicy.displayAddress(for: tab.url)
        } else {
            currentText = ""
        }
    }

    private func submitNavigation(with committedText: String? = nil) {
        let rawInput = (committedText ?? currentText).trimmingCharacters(in: .whitespacesAndNewlines)
        isOmniboxFocused = false
        session.submitOmniboxInput(rawInput)
        syncDisplayAddress()
    }

    private func openProfileWindow(_ id: UUID) {
        if !profileManager.focusExistingWindow(forProfileID: id) {
            openWindow(id: ProfileManager.windowGroupID, value: id)
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

/// Popover anchored to the Omnibox star button for editing the active page's bookmark name, URL, and target folder.
struct OmniboxBookmarkPopoverView: View {
    @ObservedObject var session: BrowserSession
    @Binding var isPresented: Bool

    /// How long the popover has to be on screen before its text fields become editable.
    /// One popover presentation is enough to finish the window setup that would
    /// otherwise pick a key view.
    static let focusEnableDelay: TimeInterval = 0.15

    @State private var bookmarkID: String = ""
    @State private var title: String = ""
    @State private var url: String = ""
    @State private var folderID: String? = nil
    @State private var pinToStartPage: Bool = true
    @State private var isCreatingFolder: Bool = false
    @State private var newFolderName: String = ""
    /// While a popover window is being presented, AppKit asks its content for the first
    /// key view; `NSTextField` answers that by selecting all of its text, and TextKit
    /// follows with a synchronous input-method (IME) activation. Waiting for the IMK XPC
    /// reply inside that nested run loop has been measured at ~1.7s of main-thread freeze
    /// with third-party IMEs (Sogou on a Touch Bar Mac). Keep the fields non-focusable
    /// until the popover is on screen so the window setup never lands on them.
    @State private var fieldsReady: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                        .font(.system(size: 13))
                    Text("已添加到书签")
                        .font(.system(size: 13.5, weight: .bold))
                }
                Spacer()
                Button("管理所有书签...") {
                    isPresented = false
                    session.openBookmarkManager(selectingFolderID: folderID)
                }
                .font(.system(size: 11, weight: .medium))
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
            }

            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("名称")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    TextField("书签名称", text: $title)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                        .disabled(!fieldsReady)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("网址")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    TextField("网址 URL", text: $url)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                        .disabled(!fieldsReady)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("所属分组")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                        Spacer()
                        Button(action: {
                            isCreatingFolder.toggle()
                            newFolderName = ""
                        }) {
                            HStack(spacing: 3) {
                                Image(systemName: "folder.badge.plus")
                                    .font(.system(size: 10))
                                Text("新建分组")
                                    .font(.system(size: 10.5, weight: .medium))
                            }
                            .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)
                    }

                    Picker("", selection: $folderID) {
                        Text("未分组 (主页个人收藏)").tag(String?.none)
                        Divider()
                        ForEach(session.bookmarkFolders) { folder in
                            Text("📁 \(folder.name)").tag(String?.some(folder.id))
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                }

                if isCreatingFolder {
                    HStack(spacing: 6) {
                        TextField("输入新分组名称...", text: $newFolderName)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11.5))
                            .onSubmit {
                                createAndSelectFolder()
                            }

                        Button("创建") {
                            createAndSelectFolder()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(6)
                    .background(Color.accentColor.opacity(0.08))
                    .cornerRadius(6)
                }

                if folderID == nil {
                    Toggle("显示在主页个人收藏", isOn: $pinToStartPage)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 11.5))
                        .padding(.top, 2)
                }
            }

            Divider()

            HStack {
                Button("移除书签", role: .destructive) {
                    if !bookmarkID.isEmpty {
                        session.removeBookmark(id: bookmarkID)
                    } else if let tabURL = session.activeTab?.url {
                        session.removeBookmarkByUrl(tabURL)
                    }
                    isPresented = false
                }
                .controlSize(.small)

                Spacer()

                Button("完成") {
                    saveChanges()
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(width: 310)
        .onAppear {
            fieldsReady = false
            loadActiveBookmarkState()
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.focusEnableDelay) {
                // Only enable while the popover is still up: a quick dismiss/re-open
                // must not carry the enabled state into the next window setup.
                if isPresented {
                    fieldsReady = true
                }
            }
        }
        .onDisappear {
            fieldsReady = false
        }
        .onChange(of: isPresented) { presented in
            if !presented {
                fieldsReady = false
            }
        }
    }

    private func loadActiveBookmarkState() {
        guard let tab = session.activeTab else { return }
        if let existing = session.bookmark(forURL: tab.url) ?? session.ensureActiveTabBookmarked() {
            bookmarkID = existing.id
            title = existing.title
            url = existing.url
            folderID = existing.folderID
            pinToStartPage = existing.isPinnedToStartPage
        }
    }

    private func createAndSelectFolder() {
        let trimmed = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let created = session.createBookmarkFolder(name: trimmed) {
            folderID = created.id
            pinToStartPage = false
        }
        isCreatingFolder = false
        newFolderName = ""
    }

    private func saveChanges() {
        guard !bookmarkID.isEmpty else { return }
        session.updateBookmark(
            id: bookmarkID,
            title: title,
            url: url,
            folderID: folderID,
            isPinnedToStartPage: folderID == nil ? pinToStartPage : false
        )
    }
}

/// Popover anchored to the Omnibox shield icon for toggling per-site ad-block allowlist.
private struct AdShieldPopoverView: View {
    @ObservedObject var session: BrowserSession
    @Binding var isPresented: Bool
    @ObservedObject private var settings = BrowserSettings.shared

    private var currentHost: String {
        guard let tab = session.activeTab, !tab.isHome else { return "" }
        return URLPolicy.rawHost(tab.url)
    }

    private var isAllowlisted: Bool {
        !currentHost.isEmpty && settings.isHostAllowlisted(currentHost)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: isAllowlisted ? "shield.slash.fill" : "shield.checkered")
                    .font(.system(size: 16))
                    .foregroundColor(isAllowlisted ? .orange : .accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isAllowlisted ? "当前站点已暂停拦截" : "原生规则拦截已启用")
                        .font(.system(size: 13, weight: .bold))
                    Text("基于 WebKit 字节码 (EasyList + China) · 零 JS 开销")
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            if !currentHost.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("当前域名")
                            .font(.system(size: 11.5))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(currentHost)
                            .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                            .lineLimit(1)
                    }

                    Button(action: {
                        session.toggleAdBlockAllowlistForActiveTab()
                    }) {
                        HStack {
                            Spacer()
                            Image(systemName: isAllowlisted ? "shield.lefthalf.filled" : "pause.circle")
                                .font(.system(size: 12))
                            Text(isAllowlisted ? "在此网站恢复去广告与净化" : "在此网站暂停拦截（加入白名单）")
                                .font(.system(size: 12, weight: .medium))
                            Spacer()
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(isAllowlisted ? .accentColor : .orange)

                    Text("若某些网页的登录弹窗或播放器被规则误伤，可临时为该域名关闭拦截。")
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("在普通网页标签中可按域名单独配置拦截白名单。")
                    .font(.system(size: 11.5))
                    .foregroundColor(.secondary)
            }

            Divider()

            HStack {
                Text("已放行域名：\(settings.adBlockAllowlistedHosts.count) 个")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
                Button("安全与防护设置...") {
                    isPresented = false
                    session.isShowingSettings = true
                }
                .font(.system(size: 11))
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
            }
        }
        .padding(14)
        .frame(width: 300)
    }
}
