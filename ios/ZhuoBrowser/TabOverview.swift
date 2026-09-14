import SwiftUI

struct TabOverview: View {
    @EnvironmentObject private var session: BrowserSession

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
                    LazyVGrid(columns: columns(for: proxy.size.width), spacing: 12) {
                        ForEach(session.tabs) { tab in
                            tabCard(tab)
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

    private func tabCard(_ tab: BrowserTab) -> some View {
        let selected = tab.id == session.activeTabID
        return ZStack(alignment: .topTrailing) {
            Button {
                session.selectTab(tab.id)
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    Text(tab.isPrivate ? "无痕" : tab.displayTitle)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(DesignTokens.textPrimary)
                        .lineLimit(2)
                        .padding(.trailing, 28)
                    if tab.isPinned {
                        Label("已固定", systemImage: "pin.fill")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(DesignTokens.accent)
                    }
                    Text(URLPolicy.isHomeURL(tab.url) ? "起始页" : tab.url)
                        .font(.system(size: 11))
                        .foregroundStyle(DesignTokens.textSecondary)
                        .lineLimit(2)
                        .padding(.trailing, tab.isPrivate ? 0 : 28)
                }
                .padding(12)
                .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
                .background(
                    tab.isPrivate ? DesignTokens.surfaceSubtle : DesignTokens.surfacePanel,
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
