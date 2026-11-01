import SwiftUI

/// Unified minimalist macOS toolbar containing navigation, omnibox, and status indicators.
public struct UnifiedToolbarView: View {
    @ObservedObject var session: BrowserSession
    @ObservedObject private var accountManager = AccountManager.shared
    @ObservedObject private var downloadManager = DownloadManager.shared
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

            // User Account Button
            Button(action: { isShowingAccount.toggle() }) {
                if accountManager.isLoggedIn {
                    if let cachedImage = accountManager.avatarImage {
                        Image(nsImage: cachedImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 24, height: 24)
                            .clipShape(Circle())
                    } else if let avatarURL = accountManager.currentUser?.resolvedAvatarURL {
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
            .sheet(isPresented: $session.isShowingBookmarkManager) {
                BookmarkManagerView(session: session, isPresented: $session.isShowingBookmarkManager)
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
        .onChange(of: activeTab?.url) { _ in
            if !isOmniboxFocused {
                syncDisplayAddress()
            }
        }
        .onChange(of: isOmniboxFocused) { focused in
            if focused {
                if activeTab?.isHome == true {
                    currentText = ""
                } else {
                    currentText = activeTab?.url ?? ""
                }
            } else {
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

            TextField("搜索或输入网址", text: $currentText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .focused($isOmniboxFocused)
                .onSubmit {
                    submitNavigation()
                }

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
        .frame(height: 28)
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isOmniboxFocused ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: isOmniboxFocused ? 1.5 : 1)
        )
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

/// Popover anchored to the Omnibox star button for editing the active page's bookmark name, URL, and target folder.
private struct OmniboxBookmarkPopoverView: View {
    @ObservedObject var session: BrowserSession
    @Binding var isPresented: Bool

    @State private var bookmarkID: String = ""
    @State private var title: String = ""
    @State private var url: String = ""
    @State private var folderID: String? = nil
    @State private var pinToStartPage: Bool = true
    @State private var isCreatingFolder: Bool = false
    @State private var newFolderName: String = ""

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
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("网址")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    TextField("网址 URL", text: $url)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
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
            loadActiveBookmarkState()
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
