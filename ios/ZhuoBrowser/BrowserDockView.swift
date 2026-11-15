import SwiftUI

struct DockSwipeTapGuard: Equatable {
    private(set) var isDragging = false
    private(set) var suppressTapUntil: Date = .distantPast

    mutating func beginDrag() {
        isDragging = true
    }

    mutating func endDrag(at now: Date = Date(), cooldown: TimeInterval = 0.35) {
        isDragging = false
        suppressTapUntil = now.addingTimeInterval(cooldown)
    }

    func canTriggerTap(at now: Date = Date()) -> Bool {
        !isDragging && now >= suppressTapUntil
    }
}

struct BrowserDockView: View {
    @EnvironmentObject private var session: BrowserSession
    @Binding var toolbarDragOffset: CGFloat
    @State private var tapGuard = DockSwipeTapGuard()
    let onBeginEditAddress: () -> Void
    let onOpenActions: () -> Void
    let onSwipeGestureEnded: (DragGesture.Value) -> Void

    private var activeTab: BrowserTab? {
        session.activeTab
    }

    private var isPrivate: Bool {
        activeTab?.isPrivate == true
    }

    private var displayURL: String {
        activeTab?.displayAddressURL ?? URLPolicy.homeURL
    }

    private var isBrowsing: Bool {
        !URLPolicy.isHomeURL(displayURL)
    }

    private var canGoBack: Bool {
        isBrowsing || activeTab?.canGoBack == true
    }

    private var canGoForward: Bool {
        activeTab?.canGoForward == true
    }

    private var blockedCount: Int {
        session.tabBlockStats[session.activeTabID]?.total ?? 0
    }

    private var addressLabel: String {
        guard isBrowsing else {
            return isPrivate ? "无痕搜索或输入网址" : "搜索或输入网址"
        }
        let host = URLPolicy.displayHost(displayURL)
        return host.isEmpty ? displayURL : host
    }

    var body: some View {
        VStack(spacing: 0) {
            progressHairline

            if session.tabs.count > 1 && session.settings.gesturesEnabled && session.settings.gestureTabSwitchEnabled {
                tabSwipeIndicator
            }

            HStack(spacing: 4) {
                backButton
                forwardButton
                addressPill
                tabBadgeButton
                menuButton
            }
            .padding(.horizontal, 8)
            .frame(height: 50)
        }
        .offset(x: toolbarDragOffset)
        .background(isPrivate ? DesignTokens.surfaceSubtle : DesignTokens.surfacePanel)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(DesignTokens.border)
                .frame(height: 0.75)
        }
        .highPriorityGesture(
            DragGesture(minimumDistance: session.settings.gesturesEnabled ? 12 : 100_000)
                .onChanged { value in
                    guard session.settings.gesturesEnabled else { return }
                    tapGuard.beginDrag()
                    if abs(value.translation.width) > abs(value.translation.height) {
                        toolbarDragOffset = value.translation.width * 0.15
                    }
                }
                .onEnded { value in
                    tapGuard.endDrag()
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        toolbarDragOffset = 0
                    }
                    onSwipeGestureEnded(value)
                }
        )
        .accessibilityIdentifier("browser-bottom-dock")
    }

    private func performDockTap(_ action: () -> Void) {
        // Ignore residual button tap events emitted when finishing a dock swipe gesture.
        guard tapGuard.canTriggerTap() else { return }
        action()
    }

    @ViewBuilder
    private var progressHairline: some View {
        if isBrowsing, activeTab?.isLoading == true {
            GeometryReader { proxy in
                let fraction = max(0.08, min(1.0, activeTab?.progress ?? 0.1))
                Rectangle()
                    .fill(DesignTokens.accentStrong)
                    .frame(width: proxy.size.width * fraction, height: 2)
                    .animation(.easeOut(duration: 0.18), value: fraction)
            }
            .frame(height: 2)
        }
    }

    private var tabSwipeIndicator: some View {
        let activeIndex = session.tabs.firstIndex(where: { $0.id == session.activeTabID }) ?? 0
        return HStack(spacing: 4) {
            ForEach(Array(session.tabs.enumerated()), id: \.element.id) { index, _ in
                Capsule()
                    .fill(index == activeIndex ? DesignTokens.accentStrong : DesignTokens.handle)
                    .frame(width: index == activeIndex ? 12 : 4, height: 4)
            }
        }
        .padding(.top, 4)
        .accessibilityHidden(true)
    }

    private var backButton: some View {
        Button {
            performDockTap { session.goBack() }
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(canGoBack ? DesignTokens.dockIcon : DesignTokens.textSecondary.opacity(0.45))
                .frame(width: 34, height: 38)
                .contentShape(Rectangle())
        }
        .disabled(!canGoBack)
        .accessibilityIdentifier("nav-back")
        .accessibilityLabel("后退")
        .onLongPressGesture {
            session.openNavigationHistory()
        }
    }

    private var forwardButton: some View {
        Button {
            performDockTap { session.goForward() }
        } label: {
            Image(systemName: "chevron.right")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(canGoForward ? DesignTokens.dockIcon : DesignTokens.textSecondary.opacity(0.45))
                .frame(width: 32, height: 38)
                .contentShape(Rectangle())
        }
        .disabled(!canGoForward)
        .accessibilityIdentifier("nav-forward")
        .accessibilityLabel("前进")
        .onLongPressGesture {
            session.openNavigationHistory()
        }
    }

    private var addressPill: some View {
        HStack(spacing: 6) {
            if isPrivate {
                Text("无痕")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DesignTokens.accentStrong)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(DesignTokens.accentStrong.opacity(0.14), in: Capsule())
            }

            if isBrowsing {
                Button {
                    performDockTap { session.openSecurityPanel() }
                } label: {
                    Image(systemName: securitySymbolName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(securityTint)
                        .frame(width: 22, height: 28)
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier("dock-security-badge")
                .accessibilityLabel("网站安全信息")
            }

            if isBrowsing && blockedCount > 0 {
                Button {
                    performDockTap {
                        session.recordActionUsage("blocking")
                        session.showsBlockPanel = true
                    }
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "shield.lefthook.filled")
                            .font(.system(size: 10, weight: .semibold))
                        Text("\(blockedCount)")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                    }
                    .foregroundStyle(DesignTokens.accentStrong)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(DesignTokens.accentStrong.opacity(0.12), in: Capsule())
                }
                .accessibilityIdentifier("dock-block-badge")
                .accessibilityLabel("已拦截 \(blockedCount) 项内容")
            }

            Button {
                performDockTap(onBeginEditAddress)
            } label: {
                Text(addressLabel)
                    .font(.system(size: 14, weight: isBrowsing ? .medium : .regular))
                    .foregroundStyle(addressTextColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: isBrowsing ? .leading : .center)
                    .frame(height: 36)
                    .contentShape(Rectangle())
            }
            .accessibilityIdentifier("dock-address-pill")
            .accessibilityLabel(isBrowsing ? "地址栏 \(addressLabel)" : "搜索或输入网址")

            if isBrowsing {
                Button {
                    performDockTap { session.reloadOrStop() }
                } label: {
                    Image(systemName: activeTab?.isLoading == true ? "xmark" : "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DesignTokens.dockIcon)
                        .frame(width: 28, height: 34)
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier("nav-reload")
                .accessibilityLabel(activeTab?.isLoading == true ? "停止加载" : "刷新")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 38)
        .background(DesignTokens.surfaceSubtle, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
        .contextMenu {
            Button {
                session.visitClipboardLink()
            } label: {
                Label("访问剪贴板", systemImage: "arrow.right.doc.on.clipboard")
            }
            .accessibilityIdentifier("address-menu-visit-clipboard")

            if isBrowsing {
                Button {
                    session.copyCurrentLink()
                } label: {
                    Label("复制链接", systemImage: "doc.on.doc")
                }
                .accessibilityIdentifier("address-menu-copy-link")
            }

            Button(role: .destructive) {
                session.closeTab(session.activeTabID)
            } label: {
                Label("关闭当前标签页", systemImage: "xmark")
            }
            .accessibilityIdentifier("address-menu-close-tab")
        }
    }

    private var tabBadgeButton: some View {
        Button {
            performDockTap { session.toggleTabOverview() }
        } label: {
            Text("\(session.tabs.count)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(DesignTokens.dockIcon)
                .frame(minWidth: 22, minHeight: 22)
                .padding(.horizontal, 3)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(DesignTokens.dockIcon, lineWidth: 1.6)
                )
                .frame(width: 36, height: 38)
                .contentShape(Rectangle())
        }
        .accessibilityIdentifier("tab-launcher")
        .accessibilityLabel("\(session.tabs.count) 个标签页")
        .onLongPressGesture {
            session.showsRecentTabs = true
        }
    }

    private var menuButton: some View {
        Button {
            performDockTap(onOpenActions)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(DesignTokens.dockIcon)
                .frame(width: 34, height: 38)
                .contentShape(Rectangle())
        }
        .accessibilityIdentifier("page-actions")
        .accessibilityLabel("页面工具")
        .onLongPressGesture(minimumDuration: 0.45) {
            guard BrowserGesturePolicy.canOpenBlocking(
                settings: session.settings,
                isBrowsing: isBrowsing
            ) else {
                return
            }
            session.recordActionUsage("blocking")
            session.showsBlockPanel = true
        }
    }

    private var securitySymbolName: String {
        switch activeTab?.securityState ?? .unknown {
        case .secure:
            return "lock.fill"
        case .certificateError:
            return "exclamationmark.triangle.fill"
        case .insecure:
            return "lock.open.fill"
        case .unknown:
            return "globe"
        }
    }

    private var securityTint: Color {
        switch activeTab?.securityState ?? .unknown {
        case .secure:
            return DesignTokens.accentStrong
        case .certificateError:
            return DesignTokens.danger
        case .insecure:
            return .orange
        case .unknown:
            return DesignTokens.dockIcon
        }
    }

    private var addressTextColor: Color {
        if !isBrowsing {
            return DesignTokens.textSecondary
        }
        if activeTab?.loadError != .none || activeTab?.securityState == .certificateError {
            return DesignTokens.danger
        }
        return DesignTokens.textPrimary
    }
}

struct CollapsedDockPill: View {
    let tab: BrowserTab?
    let onRestore: () -> Void

    private var label: String {
        guard let tab else { return "" }
        let url = tab.displayAddressURL
        let host = URLPolicy.displayHost(url)
        return host.isEmpty ? tab.displayTitle : host
    }

    var body: some View {
        Button(action: onRestore) {
            HStack(spacing: 6) {
                Image(systemName: symbolName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(symbolTint)
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DesignTokens.textPrimary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .frame(height: 30)
            .background(.ultraThinMaterial, in: Capsule())
            .background(DesignTokens.capsuleBackground, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(DesignTokens.border, lineWidth: 0.8)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 8, y: 2)
        }
        .gesture(
            DragGesture(minimumDistance: 12)
                .onEnded { value in
                    if value.translation.height <= -16 {
                        onRestore()
                    }
                }
        )
        .accessibilityIdentifier("dock-collapsed-pill")
        .accessibilityLabel("展开地址栏 \(label)")
    }

    private var symbolName: String {
        switch tab?.securityState ?? .unknown {
        case .secure:
            return "lock.fill"
        case .certificateError:
            return "exclamationmark.triangle.fill"
        case .insecure:
            return "lock.open.fill"
        case .unknown:
            return "globe"
        }
    }

    private var symbolTint: Color {
        switch tab?.securityState ?? .unknown {
        case .secure:
            return DesignTokens.accentStrong
        case .certificateError:
            return DesignTokens.danger
        case .insecure:
            return .orange
        case .unknown:
            return DesignTokens.textSecondary
        }
    }
}
