import SwiftUI

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openWindow) private var openWindow
    @StateObject private var session: BrowserSession
    private let windowRequest: BrowserWindowRequest?
    @State private var addressText = ""
    @State private var quickSiteEditor: QuickSiteEditorRequest?
    @State private var sidebarPanel: BrowserSidebarPanel = .tabs
    @State private var sidebarVisible = false
    @State private var sidebarPresentation: SidebarPresentation = .unavailable
    @State private var splitDragStartRatio = 0.5
    @State private var isDraggingSplit = false
    @State private var toolbarHidden = false
    @State private var pageScrollOffsets: [String: CGFloat] = [:]
    @FocusState private var addressFocused: Bool

    init(windowRequest: BrowserWindowRequest? = nil, isPrimaryWindow: Bool = true) {
        self.windowRequest = windowRequest
        _session = StateObject(
            wrappedValue: BrowserSession(
                windowRequest: windowRequest,
                isPrimaryWindow: isPrimaryWindow
            )
        )
    }

    var body: some View {
        GeometryReader { proxy in
            adaptiveWorkspace(width: proxy.size.width)
                .onAppear { updateLayout(width: proxy.size.width) }
                .onChange(of: proxy.size.width) { _, width in
                    updateLayout(width: width)
                }
        }
        .background(pageBackground)
        .environmentObject(session)
        .preferredColorScheme(preferredColorScheme)
        .fullScreenCover(isPresented: setupRequired) {
            SetupFlowView()
                .environmentObject(session)
                .preferredColorScheme(preferredColorScheme)
        }
        .sheet(isPresented: $session.showsSettings) {
            SettingsSheet()
                .environmentObject(session)
        }
        .sheet(isPresented: $session.showsDownloads) {
            DownloadSheet()
                .environmentObject(session)
        }
        .fullScreenCover(isPresented: $session.showsArticles) {
            ArticleLibrarySheet()
                .environmentObject(session)
                .preferredColorScheme(preferredColorScheme)
        }
        .sheet(isPresented: $session.showsProPaywall) {
            ProPaywallView()
                .environmentObject(session)
                .preferredColorScheme(preferredColorScheme)
        }
        .sheet(isPresented: $session.showsSecurityPanel) {
            SiteSecuritySheet()
                .environmentObject(session)
                .preferredColorScheme(preferredColorScheme)
        }
        .sheet(isPresented: $session.showsPageSettings) {
            PageDisplaySettingsSheet()
                .environmentObject(session)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $session.showsBlockPanel) {
            BlockPanelSheet()
                .environmentObject(session)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $session.showsShare) {
            ShareSheet(items: session.shareItems)
        }
        .sheet(isPresented: $session.showsLibrary) {
            LibrarySheet()
                .environmentObject(session)
        }
        .sheet(isPresented: $session.showsNavigationHistory) {
            NavigationHistorySheet()
                .environmentObject(session)
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $session.permissionPrompt, onDismiss: {
            session.denyPermissionIfPending()
        }) { prompt in
            PermissionSheet(
                prompt: prompt,
                onAllow: { session.allowPermission() },
                onDeny: { session.denyPermission() }
            )
            .presentationDetents([.medium])
        }
        .sheet(item: $quickSiteEditor) { request in
            QuickSiteEditorSheet(request: request, onSave: session.saveQuickSite)
                .preferredColorScheme(preferredColorScheme)
        }
        .alert("恢复过期标签页？", isPresented: $session.showsExpiredTabsPrompt) {
            Button("恢复") { session.restoreExpiredTabs() }
            Button("稍后处理", role: .cancel) {}
        } message: {
            Text("有 \(session.archivedTabs.count) 个标签页超过保留期限。")
        }
        .alert("标签页较多", isPresented: $session.showsTabSoftLimitPrompt) {
            Button("清理旧标签页") { session.cleanupSoftLimitTabs() }
            Button("继续新建", role: .cancel) {}
        } message: {
            Text("已达到 \(session.settings.tabSoftLimit) 个标签页。可以清理较旧的标签页，也可以继续新建。")
        }
        .alert(item: downloadPolicyBinding) { request in
            switch request.reason {
            case .wifiRequired:
                return Alert(
                    title: Text("需要 Wi-Fi"),
                    message: Text("“\(request.fileName)”将在连接 Wi-Fi 后才能下载。"),
                    dismissButton: .cancel(Text("取消下载")) {
                        session.downloads.cancelPolicy(request.taskID)
                    }
                )
            case .largeFile:
                return Alert(
                    title: Text("使用移动网络下载？"),
                    message: Text("“\(request.fileName)”超过大文件提醒阈值。"),
                    primaryButton: .default(Text("继续下载")) {
                        session.downloads.approvePolicy(request.taskID)
                    },
                    secondaryButton: .cancel(Text("取消")) {
                        session.downloads.cancelPolicy(request.taskID)
                    }
                )
            }
        }
        .alert(item: $session.securityWarning) { warning in
            Alert(
                title: Text("此页面连接不安全"),
                message: Text("\(warning.host) 使用未加密的 HTTP 连接。请勿在此页面输入密码或其他敏感信息。"),
                dismissButton: .default(Text("知道了"))
            )
        }
        .alert(item: $session.externalProtocolRequest) { request in
            Alert(
                title: Text(request.category.promptTitle),
                message: Text(request.promptMessage),
                primaryButton: .default(Text("打开")) {
                    session.openExternalProtocol(request)
                },
                secondaryButton: .cancel(Text("取消")) {
                    session.cancelPendingExternalProtocol()
                }
            )
        }
        .alert(item: $session.pageIssueDiagnostic) { diagnostic in
            Alert(
                title: Text("页面问题诊断"),
                message: Text(diagnostic.summary),
                primaryButton: .default(Text("复制诊断信息")) {
                    session.copyPageIssueDiagnostic(diagnostic)
                },
                secondaryButton: .cancel(Text("取消"))
            )
        }
        .onAppear {
            addressText = displayAddress(session.activeTab?.url ?? "")
            session.consumeInboundShares()
            if let windowRequest, session.acceptedWindowRequestID == windowRequest.id {
                BrowserWindowTransfer.acknowledge(windowRequest)
            }
        }
        .task {
            await session.pro.activate()
        }
        .onChange(of: session.activeTabID) { _, _ in
            addressText = displayAddress(session.activeTab?.url ?? "")
            toolbarHidden = false
        }
        .onChange(of: session.settings.autoHideToolbarEnabled) { _, enabled in
            if !enabled { toolbarHidden = false }
        }
        .onChange(of: session.activeTab?.url) { _, newValue in
            if !addressFocused {
                addressText = displayAddress(newValue ?? "")
            }
        }
        .onChange(of: scenePhase) { _, newValue in
            if newValue != .active {
                session.captureActivePageState()
            } else {
                Task { await session.pro.refreshForForeground() }
                session.consumeInboundShares()
            }
        }
        .onChange(of: session.settings.onboardingCompleted) { _, completed in
            if completed {
                session.consumeInboundShares()
            }
        }
        .focusedSceneValue(\.browserCommandActions, browserCommandActions)
    }

    @ViewBuilder
    private func adaptiveWorkspace(width: CGFloat) -> some View {
        let presentation = AdaptiveWorkspacePolicy.sidebarPresentation(width: Double(width))
        switch presentation {
        case .unavailable:
            browserSurface
        case .overlay:
            ZStack(alignment: .trailing) {
                browserSurface
                if sidebarVisible {
                    Color.black.opacity(0.12)
                        .ignoresSafeArea()
                        .onTapGesture { sidebarVisible = false }
                    sidebar(width: width)
                        .shadow(color: Color.black.opacity(0.12), radius: 16, x: -3)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        case .inline:
            HStack(spacing: 0) {
                browserSurface
                if sidebarVisible {
                    sidebar(width: width)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
    }

    private var browserSurface: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                if !toolbarHidden || !session.settings.autoHideToolbarEnabled {
                    addressBar(width: proxy.size.width)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if session.showsFind {
                    FindBar()
                }
                if session.activeTab?.isReader == true && !session.showsOverview {
                    ReaderBar()
                }
                ZStack {
                    pageArea(width: proxy.size.width)
                    if addressFocused && !session.showsOverview {
                        SuggestionList(suggestions: session.suggestions(for: addressText)) { item in
                            addressFocused = false
                            addressText = displayAddress(item.url)
                            session.openInActiveTab(item.url)
                        }
                    }
                    if session.showsOverview {
                        TabOverview()
                    }
                    pageOverlays
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var pageOverlays: some View {
        ZStack {
            if let notice = session.notice {
                VStack {
                    Text(notice)
                        .font(.system(size: 14))
                        .foregroundStyle(DesignTokens.textPrimary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(DesignTokens.surfacePanel, in: Capsule())
                        .shadow(color: Color.black.opacity(0.08), radius: 8, y: 2)
                        .padding(.top, 16)
                    Spacer()
                }
                .allowsHitTesting(false)
                .accessibilityIdentifier("page-notice")
            }
            if session.isGeneratingScreenshot {
                ZStack {
                    Color.black.opacity(0.12)
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("正在生成长截图…").font(.subheadline)
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 18)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
                .contentShape(Rectangle())
                .accessibilityIdentifier("screenshot-progress")
            }
            if session.pageResumeRequest?.tabID == session.activeTabID && !session.showsOverview {
                VStack {
                    Spacer()
                    PageResumePrompt(
                        onContinue: session.continuePageResume,
                        onStartOver: session.startPageResumeFromTop
                    )
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func sidebar(width: CGFloat) -> some View {
        BrowserWorkspaceSidebar(
            panel: $sidebarPanel,
            onDismiss: {
                withAnimation(.easeInOut(duration: 0.2)) { sidebarVisible = false }
            },
            onOpenBeside: { tabID in
                withAnimation(.easeInOut(duration: 0.2)) { _ = session.openTabBeside(tabID) }
            },
            onOpenWindow: { tabID in
                guard let request = session.makeWindowRequest(for: tabID) else { return }
                openWindow(id: "browser-window", value: request)
            }
        )
        .environmentObject(session)
        .frame(width: CGFloat(AdaptiveWorkspacePolicy.sidebarWidth(width: Double(width))))
    }

    private func updateLayout(width: CGFloat) {
        let next = AdaptiveWorkspacePolicy.sidebarPresentation(width: Double(width))
        if next == .unavailable {
            sidebarVisible = false
            session.showsOverview = false
        } else if next == .inline && sidebarPresentation != .inline {
            sidebarVisible = true
        }
        sidebarPresentation = next
    }

    private var pageBackground: Color {
        if session.activeTab?.isReader == true {
            return Color(hex: ReaderTheme.theme(for: session.readerSettings.paper).background)
        }
        return DesignTokens.pageBackground
    }

    @ViewBuilder
    private func pageArea(width: CGFloat) -> some View {
        if width >= CGFloat(AdaptiveWorkspacePolicy.mediumMinimumWidth),
           let split = session.splitTabIDs {
            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    pageBody(tabID: split.primary)
                        .frame(width: width * CGFloat(session.paneState.primaryRatio))
                    pageBody(tabID: split.secondary)
                        .frame(width: width * CGFloat(1 - session.paneState.primaryRatio))
                }
                splitDivider(totalWidth: width)
                    .offset(x: width * CGFloat(session.paneState.primaryRatio) - 14)
            }
            .clipped()
            .accessibilityIdentifier("browser-split-view")
        } else {
            pageBody(tabID: session.activeTabID)
        }
    }

    @ViewBuilder
    private func pageBody(tabID: String) -> some View {
        let tab = session.tab(tabID)
        if URLPolicy.isHomeURL(tab?.url ?? URLPolicy.homeURL) {
            NativeHomeView(
                sites: session.quickSites,
                settings: session.settings,
                backgroundImage: session.homeBackgroundImage,
                onOpen: { url in
                    session.focusPane(tabID)
                    session.openInActiveTab(url)
                },
                onAdd: {
                    session.focusPane(tabID)
                    quickSiteEditor = .add
                },
                onEdit: { site in
                    session.focusPane(tabID)
                    quickSiteEditor = .edit(site)
                },
                onRemove: { site in
                    session.focusPane(tabID)
                    session.removeQuickSite(site.id)
                },
                onSettings: {
                    session.focusPane(tabID)
                    session.showsSettings = true
                },
                onBookmarks: {
                    session.focusPane(tabID)
                    session.openLibrary(.bookmarks)
                },
                onHistory: {
                    session.focusPane(tabID)
                    session.openLibrary(.history)
                }
            )
            .overlay {
                paneFocusBorder(tabID: tabID)
                    .allowsHitTesting(false)
            }
        } else if let controller = session.controller(for: tabID) {
            BrowserWebView(
                webView: controller.webView,
                onFocus: { session.focusPane(tabID) },
                onScroll: { offset in handlePageScroll(tabID: tabID, offset: offset) }
            )
            .id(tabID)
            .overlay {
                paneFocusBorder(tabID: tabID)
                    .allowsHitTesting(false)
            }
        } else {
            pageBackground
        }
    }

    private func handlePageScroll(tabID: String, offset: CGFloat) {
        let previous = pageScrollOffsets[tabID] ?? offset
        pageScrollOffsets[tabID] = offset
        guard tabID == session.activeTabID,
              session.settings.autoHideToolbarEnabled,
              !session.showsOverview,
              !URLPolicy.isHomeURL(session.tab(tabID)?.url ?? URLPolicy.homeURL) else {
            return
        }
        let delta = offset - previous
        if offset <= 8 || delta < -4 {
            withAnimation(.easeOut(duration: 0.18)) { toolbarHidden = false }
        } else if offset > 36 && delta > 4 {
            addressFocused = false
            withAnimation(.easeOut(duration: 0.18)) { toolbarHidden = true }
        }
    }

    @ViewBuilder
    private func paneFocusBorder(tabID: String) -> some View {
        if session.isSplitActive && tabID == session.activeTabID {
            Rectangle()
                .stroke(DesignTokens.accent.opacity(0.55), lineWidth: 2)
                .accessibilityHidden(true)
        }
    }

    private func splitDivider(totalWidth: CGFloat) -> some View {
        VStack(spacing: 8) {
            ForEach([0.3, 0.5, 0.7], id: \.self) { ratio in
                Button("\(Int(ratio * 100))") {
                    withAnimation(.easeInOut(duration: 0.2)) { session.setSplitRatio(ratio) }
                }
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(DesignTokens.textSecondary)
            }
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { session.closeSplit() }
            } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
            }
            .accessibilityLabel("关闭双栏")
        }
        .frame(width: 28)
        .padding(.vertical, 10)
        .background(DesignTokens.surfacePanel, in: Capsule())
        .overlay(Capsule().stroke(DesignTokens.border, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.08), radius: 8, y: 2)
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { value in
                    if !isDraggingSplit {
                        splitDragStartRatio = session.paneState.primaryRatio
                        isDraggingSplit = true
                    }
                    session.setSplitRatio(splitDragStartRatio + Double(value.translation.width / max(1, totalWidth)))
                }
                .onEnded { _ in isDraggingSplit = false }
        )
        .accessibilityIdentifier("browser-split-divider")
    }

    private func addressBar(width: CGFloat) -> some View {
        HStack(spacing: 6) {
            Button {
                session.goBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(canGoBack ? DesignTokens.textPrimary : DesignTokens.textSecondary)
                    .frame(width: 32, height: 36)
            }
            .disabled(!canGoBack)
            .accessibilityIdentifier("nav-back")
            .onLongPressGesture {
                session.openNavigationHistory()
            }

            Button {
                session.goForward()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(canGoForward ? DesignTokens.textPrimary : DesignTokens.textSecondary)
                    .frame(width: 30, height: 36)
            }
            .disabled(!canGoForward)
            .accessibilityIdentifier("nav-forward")
            .onLongPressGesture {
                session.openNavigationHistory()
            }

            TextField(session.activeTab?.isPrivate == true ? "无痕搜索或输入网址" : "搜索或输入网址", text: $addressText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .submitLabel(.go)
                .font(.system(size: 15))
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(DesignTokens.surfaceSubtle, in: Capsule())
                .focused($addressFocused)
                .accessibilityIdentifier("omni-field")
                .onSubmit {
                    addressFocused = false
                    session.openInActiveTab(addressText)
                }

            pageActions

            Button {
                session.reloadOrStop()
            } label: {
                Image(systemName: session.activeTab?.isLoading == true ? "xmark" : "arrow.clockwise")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DesignTokens.textPrimary)
                    .frame(width: 32, height: 36)
            }
            .accessibilityIdentifier("nav-reload")

            Button {
                if AdaptiveWorkspacePolicy.sidebarPresentation(width: Double(width)) == .unavailable {
                    session.showsOverview.toggle()
                } else {
                    session.showsOverview = false
                    sidebarPanel = .tabs
                    withAnimation(.easeInOut(duration: 0.2)) { sidebarVisible.toggle() }
                }
            } label: {
                Text("\(session.tabs.count)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DesignTokens.textPrimary)
                    .frame(minWidth: 32, minHeight: 36)
                    .background(DesignTokens.surfaceSubtle, in: Capsule())
            }
            .accessibilityIdentifier("tab-launcher")
            .accessibilityLabel("\(session.tabs.count) 个标签页")
            .onLongPressGesture {
                session.createTab(isPrivate: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(session.activeTab?.isPrivate == true ? DesignTokens.surfaceSubtle : DesignTokens.surfacePanel)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DesignTokens.border)
                .frame(height: 1)
        }
    }

    private var pageActions: some View {
        let browsing = !(session.activeTab.map { URLPolicy.isHomeURL($0.url) } ?? true)
        let isSavingArticle = session.activeTab.map { session.articles.capturingURLs.contains($0.url) } ?? false
        return Menu {
            Button(session.activeTab?.isReader == true ? "退出阅读模式" : "阅读模式") {
                session.toggleReader()
            }
            .disabled(!browsing)
            Button("在页面中查找") {
                session.beginFind()
            }
            .disabled(!browsing)
            Button("网页显示") {
                session.showsPageSettings = true
            }
            .disabled(!browsing)
            Button("内容拦截") {
                session.showsBlockPanel = true
            }
            .disabled(!browsing)
            Button("网站安全") {
                session.openSecurityPanel()
            }
            .disabled(!browsing)
            Button(session.isCurrentPageSaved() ? "取消书签" : "加入书签") {
                session.toggleSaved()
            }
            .disabled(!browsing)
            Button(session.isCurrentPageSavedForLater() ? "已加入稍后读" : "稍后阅读") {
                session.saveCurrentPageForLater()
            }
            .disabled(!browsing || session.activeTab?.isPrivate == true)
            Button(isSavingArticle ? "正在保存文章" : "保存离线文章") {
                session.captureCurrentArticle()
            }
            .disabled(!browsing || session.activeTab?.isPrivate == true || isSavingArticle)
            Button("离线文章库") {
                session.openArticleLibrary()
            }
            Button("书签与历史") {
                session.openLibrary(.bookmarks)
            }
            Button("导航历史") {
                session.openNavigationHistory()
            }
            .disabled(session.activeController == nil)
            Button("分享") {
                session.shareCurrentPage()
            }
            .disabled(!browsing)
            Button(session.isGeneratingScreenshot ? "正在生成长截图" : "分享页面长截图") {
                Task { await session.shareCurrentScreenshot() }
            }
            .disabled(!browsing || session.isGeneratingScreenshot)
            .accessibilityIdentifier("page-share-screenshot")
            Button("复制链接") {
                session.copyCurrentLink()
            }
            .disabled(!browsing)
            .accessibilityIdentifier("page-copy-link")
            Button("访问剪贴板链接") {
                session.visitClipboardLink()
            }
            .accessibilityIdentifier("page-visit-clipboard")
            Button("报告页面问题") {
                session.reportPageIssue()
            }
            .disabled(!browsing)
            .accessibilityIdentifier("page-report-issue")
            Button("下载") {
                session.showsDownloads = true
            }
            Button("设置") {
                session.showsSettings = true
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DesignTokens.textPrimary)
                .frame(width: 32, height: 36)
        }
        .accessibilityIdentifier("page-actions")
    }

    private var canGoBack: Bool {
        guard let tab = session.activeTab else {
            return false
        }
        return !URLPolicy.isHomeURL(tab.url)
    }

    private var canGoForward: Bool {
        session.activeTab?.canGoForward == true
    }

    private var setupRequired: Binding<Bool> {
        Binding(
            get: { !session.settings.privacyConsentAccepted || !session.settings.onboardingCompleted },
            set: { _ in }
        )
    }

    private var preferredColorScheme: ColorScheme? {
        switch session.settings.appearance {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    private var downloadPolicyBinding: Binding<DownloadPolicyRequest?> {
        Binding(
            get: { session.downloads.policyRequest },
            set: { session.downloads.policyRequest = $0 }
        )
    }

    private var browserCommandActions: BrowserCommandActions {
        BrowserCommandActions(
            canReopenTab: session.canReopenRecentlyClosedTab,
            canReload: !(session.activeTab.map { URLPolicy.isHomeURL($0.url) } ?? true),
            canFind: !(session.activeTab.map { URLPolicy.isHomeURL($0.url) } ?? true),
            focusAddress: {
                session.showsOverview = false
                addressText = displayAddress(session.activeTab?.url ?? "")
                addressFocused = true
            },
            newTab: {
                session.createTab(isPrivate: session.activeTab?.isPrivate == true)
            },
            closeTab: {
                session.closeTab(session.activeTabID)
            },
            reopenTab: {
                session.reopenRecentlyClosedTab()
            },
            nextTab: {
                session.switchAdjacentTab(1)
            },
            previousTab: {
                session.switchAdjacentTab(-1)
            },
            reload: {
                session.reloadOrStop()
            },
            find: {
                session.beginFind()
            }
        )
    }

    private func displayAddress(_ url: String) -> String {
        URLPolicy.isHomeURL(url) ? "" : url
    }
}
