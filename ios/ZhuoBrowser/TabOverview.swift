import SwiftUI

struct TabOverview: View {
    @EnvironmentObject private var session: BrowserSession
    let allowsWorkspaceActions: Bool
    let onOpenBeside: (String) -> Void
    let onMoveToWindow: (String) -> Void

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                HStack {
                    Text("\(session.tabs.count) 个标签页")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(DesignTokens.textPrimary)
                    Spacer()
                    if !session.archivedTabs.isEmpty {
                        Button {
                            session.showsExpiredTabsPrompt = true
                        } label: {
                            Label("\(session.archivedTabs.count)", systemImage: "archivebox")
                        }
                        .font(.system(size: 13))
                        .foregroundStyle(DesignTokens.textSecondary)
                        .accessibilityLabel("\(session.archivedTabs.count) 个已过期标签页")
                        .accessibilityIdentifier("expired-tabs")
                    }
                    if session.canReopenRecentlyClosedTab {
                        Button {
                            session.reopenRecentlyClosedTab()
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                        }
                        .foregroundStyle(DesignTokens.textSecondary)
                        .accessibilityLabel("恢复关闭的标签页")
                        .accessibilityIdentifier("reopen-closed-tab")
                    }
                    Button("全部关闭") {
                        session.closeAll()
                        session.showsOverview = false
                    }
                    .font(.system(size: 15))
                    .foregroundStyle(DesignTokens.accent)
                    .accessibilityIdentifier("close-all-tabs")
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        tabGrid(normalTabs, width: proxy.size.width)

                        if !privateTabs.isEmpty {
                            Text("无痕")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(DesignTokens.textSecondary)
                                .padding(.top, 8)
                                .accessibilityIdentifier("private-tabs-heading")
                            tabGrid(privateTabs, width: proxy.size.width)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }

                HStack(spacing: 12) {
                    Button {
                        session.createTab(isPrivate: false)
                        session.showsOverview = false
                    } label: {
                        labelButton(title: "新建标签页", systemImage: "plus")
                    }
                    .accessibilityIdentifier("new-tab")

                    Button {
                        session.createTab(isPrivate: true)
                        session.showsOverview = false
                    } label: {
                        labelButton(title: "无痕标签页", systemImage: "eyeglasses")
                    }
                    .accessibilityIdentifier("new-private-tab")
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(DesignTokens.surfacePanel)
            }
        }
        .background(DesignTokens.pageBackground)
        .accessibilityIdentifier("tab-overview")
    }

    private func columns(for width: CGFloat) -> [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: 12),
            count: AdaptiveWorkspacePolicy.tabColumnCount(width: Double(width))
        )
    }

    private var normalTabs: [BrowserTab] {
        session.tabs.filter { !$0.isPrivate }
    }

    private var privateTabs: [BrowserTab] {
        session.tabs.filter(\.isPrivate)
    }

    private func tabGrid(_ tabs: [BrowserTab], width: CGFloat) -> some View {
        LazyVGrid(columns: columns(for: width), spacing: 12) {
            ForEach(tabs) { tab in
                tabCard(tab)
            }
        }
    }

    private func tabCard(_ tab: BrowserTab) -> some View {
        let selected = tab.id == session.activeTabID
        return ZStack(alignment: .topTrailing) {
            Button {
                session.selectTab(tab.id)
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 7) {
                        if let image = session.siteIcon(for: tab) {
                            SiteIconThumbnail(image: image, size: 18, cornerRadius: 4)
                        } else {
                            Image(systemName: tab.isPrivate ? "eyeglasses" : "globe")
                                .font(.system(size: 13))
                                .foregroundStyle(DesignTokens.textSecondary)
                        }
                        Text(cardTitle(tab))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(DesignTokens.textPrimary)
                            .lineLimit(1)
                    }
                    .padding(.trailing, 28)
                    .padding(.horizontal, 12)
                    .frame(height: 46)

                    tabThumbnail(tab)
                }
                .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
                .background(
                    DesignTokens.surfacePanel,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(selected ? DesignTokens.accent : DesignTokens.border, lineWidth: selected ? 2 : 1)
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("tab-card-\(tab.id)")
            .contextMenu {
                Button("关闭标签页", systemImage: "xmark", role: .destructive) {
                    session.closeTab(tab.id)
                }
                Button("关闭其他标签页", systemImage: "rectangle.stack.badge.minus") {
                    session.closeOtherTabs(keeping: tab.id)
                }
                .disabled(!session.canCloseOtherTabs(keeping: tab.id))
                Button("复制链接", systemImage: "doc.on.doc") {
                    session.copyTabLink(tab.id)
                }
                .disabled(URLPolicy.isHomeURL(tab.url))
                if allowsWorkspaceActions {
                    Button("在右侧打开", systemImage: "rectangle.split.2x1") {
                        onOpenBeside(tab.id)
                    }
                    .disabled(!session.canOpenTabBeside(tab.id))
                    Button("移到新窗口", systemImage: "macwindow.badge.plus") {
                        onMoveToWindow(tab.id)
                    }
                }
                if !tab.isPrivate {
                    Button(tab.isPinned ? "取消固定" : "固定标签页", systemImage: tab.isPinned ? "pin.slash" : "pin") {
                        session.toggleTabPinned(tab.id)
                    }
                }
                Divider()
                Button("向前移动", systemImage: "arrow.left") {
                    session.reorderTab(tab.id, direction: -1)
                }
                .disabled(!session.canReorderTab(tab.id, direction: -1))
                Button("向后移动", systemImage: "arrow.right") {
                    session.reorderTab(tab.id, direction: 1)
                }
                .disabled(!session.canReorderTab(tab.id, direction: 1))
            }
            .simultaneousGesture(tabSwitchGesture)
            .accessibilityAction(named: "上一个标签页") {
                session.switchAdjacentTab(-1)
            }
            .accessibilityAction(named: "下一个标签页") {
                session.switchAdjacentTab(1)
            }
            .accessibilityAction(named: "向前移动") {
                session.reorderTab(tab.id, direction: -1)
            }
            .accessibilityAction(named: "向后移动") {
                session.reorderTab(tab.id, direction: 1)
            }
            .accessibilityAction(named: "复制链接") {
                session.copyTabLink(tab.id)
            }
            .accessibilityAction(named: "关闭其他标签页") {
                session.closeOtherTabs(keeping: tab.id)
            }

            Button {
                session.closeTab(tab.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DesignTokens.textSecondary)
                    .frame(width: 28, height: 28)
            }
            .accessibilityIdentifier("close-tab-\(tab.id)")
            .padding(4)

            if !tab.isPrivate {
                Button {
                    session.toggleTabPinned(tab.id)
                } label: {
                    Image(systemName: tab.isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(tab.isPinned ? DesignTokens.accent : DesignTokens.textSecondary)
                        .frame(width: 28, height: 28)
                }
                .accessibilityLabel(tab.isPinned ? "取消固定" : "固定标签页")
                .accessibilityIdentifier("pin-tab-\(tab.id)")
                .padding(4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }

            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DesignTokens.textSecondary)
                .frame(width: 28, height: 28)
                .padding(4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .draggable(tab.id) {
                    Label(tab.displayTitle, systemImage: "rectangle.on.rectangle")
                        .padding(10)
                        .background(DesignTokens.surfacePanel, in: RoundedRectangle(cornerRadius: 10))
                }
                .accessibilityHidden(true)
        }
        .dropDestination(for: String.self) { ids, _ in
            guard let id = ids.first else {
                return false
            }
            return session.moveTab(id, to: tab.id)
        }
    }

    @ViewBuilder
    private func tabThumbnail(_ tab: BrowserTab) -> some View {
        ZStack {
            if let image = session.tabThumbnail(for: tab) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                TabThumbnailPlaceholder(isPrivate: tab.isPrivate)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 144)
        .background(DesignTokens.pageBackground)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(DesignTokens.border)
                .frame(height: 1)
        }
        .accessibilityHidden(true)
    }

    private func cardTitle(_ tab: BrowserTab) -> String {
        guard !URLPolicy.isHomeURL(tab.url) else { return "新标签页" }
        let host = URLPolicy.displayHost(tab.url)
        return host.isEmpty ? tab.displayTitle : host
    }

    private var tabSwitchGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                guard session.settings.gesturesEnabled,
                      session.settings.gestureTabSwitchEnabled,
                      abs(value.translation.width) > abs(value.translation.height) * 1.5,
                      abs(value.translation.width) >= 56 else {
                    return
                }
                session.switchAdjacentTab(value.translation.width < 0 ? 1 : -1)
            }
    }

    private func labelButton(title: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
            Text(title)
        }
        .font(.system(size: 15, weight: .medium))
        .foregroundStyle(DesignTokens.textPrimary)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(DesignTokens.surfaceSubtle, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct TabThumbnailPlaceholder: View {
    let isPrivate: Bool

    var body: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: 8) {
                Capsule()
                    .fill(DesignTokens.border)
                    .frame(width: proxy.size.width * 0.4, height: 6)
                Capsule()
                    .fill(DesignTokens.surfaceSubtle)
                    .frame(width: proxy.size.width * 0.92, height: 9)
                Capsule()
                    .fill(DesignTokens.surfaceSubtle)
                    .frame(width: proxy.size.width * 0.7, height: 9)
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(DesignTokens.surfaceSubtle)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 2)
            }
            .padding(12)
        }
        .opacity(isPrivate ? 0.5 : 1)
    }
}
