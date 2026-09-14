import SwiftUI

struct DesktopTabStrip: View {
    @EnvironmentObject private var session: BrowserSession

    let availableWidth: CGFloat
    let onOpenBeside: (String) -> Void
    let onMoveToWindow: (String) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 4) {
                    ForEach(session.tabs) { tab in
                        DesktopTabStripItem(
                            tab: tab,
                            width: tabWidth(tab),
                            onOpenBeside: onOpenBeside,
                            onMoveToWindow: onMoveToWindow
                        )
                        .id(tab.id)
                    }

                    Button {
                        session.createTab(isPrivate: session.activeTab?.isPrivate == true)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(DesignTokens.textSecondary)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("新建标签页")
                    .accessibilityIdentifier("desktop-new-tab")
                }
                .padding(.horizontal, 8)
            }
            .onAppear {
                proxy.scrollTo(session.activeTabID, anchor: .center)
            }
            .onChange(of: session.activeTabID) { _, tabID in
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo(tabID, anchor: .center)
                }
            }
        }
        .frame(height: 44)
        .background(DesignTokens.surfaceSubtle)
        .accessibilityIdentifier("desktop-tab-strip")
    }

    private var regularTabWidth: CGFloat {
        CGFloat(
            AdaptiveWorkspacePolicy.desktopTabWidth(
                availableWidth: Double(availableWidth),
                tabCount: session.tabs.count,
                pinnedCount: session.tabs.filter(\.isPinned).count
            )
        )
    }

    private func tabWidth(_ tab: BrowserTab) -> CGFloat {
        tab.isPinned ? 52 : regularTabWidth
    }
}

private struct DesktopTabStripItem: View {
    @EnvironmentObject private var session: BrowserSession
    @State private var isDropTargeted = false

    let tab: BrowserTab
    let width: CGFloat
    let onOpenBeside: (String) -> Void
    let onMoveToWindow: (String) -> Void

    var body: some View {
        interactiveTab
            .accessibilityAction(named: "向前移动") {
                session.reorderTab(tab.id, direction: -1)
            }
            .accessibilityAction(named: "向后移动") {
                session.reorderTab(tab.id, direction: 1)
            }
    }

    private var interactiveTab: some View {
        tabSurface
            .contextMenu { tabContextMenu }
            .draggable(tab.id) {
                dragPreview
            }
            .dropDestination(for: String.self) { items, _ in
                guard let sourceID = items.first else { return false }
                return session.moveTab(sourceID, to: tab.id)
            } isTargeted: { targeted in
                isDropTargeted = targeted
            }
    }

    private var tabSurface: some View {
        HStack(spacing: 0) {
            Button {
                session.selectTab(tab.id)
            } label: {
                HStack(spacing: 7) {
                    tabIcon
                    if !tab.isPinned {
                        Text(tab.displayTitle)
                            .font(.system(size: 13, weight: isActive ? .medium : .regular))
                            .foregroundStyle(isActive ? DesignTokens.textPrimary : DesignTokens.textSecondary)
                            .lineLimit(1)
                    }
                }
                .padding(.leading, tab.isPinned ? 0 : 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: tab.isPinned ? .center : .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(tab.displayTitle)
            .accessibilityIdentifier("desktop-tab-\(tab.id)")

            if !tab.isPinned {
                Button {
                    session.closeTab(tab.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DesignTokens.textSecondary)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭 \(tab.displayTitle)")
                .accessibilityIdentifier("desktop-close-tab-\(tab.id)")
                .padding(.trailing, 3)
            }
        }
        .frame(width: width, height: 36)
        .background(isActive ? DesignTokens.pageBackground : Color.clear, in: tabShape)
        .overlay {
            if isDropTargeted {
                tabShape.stroke(DesignTokens.accent, lineWidth: 1.5)
            }
        }
        .contentShape(tabShape)
    }

    private var isActive: Bool {
        tab.id == session.activeTabID
    }

    private var tabShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            cornerRadii: RectangleCornerRadii(
                topLeading: 10,
                bottomLeading: 0,
                bottomTrailing: 0,
                topTrailing: 10
            ),
            style: .continuous
        )
    }

    @ViewBuilder
    private var tabIcon: some View {
        if let image = session.siteIcon(for: tab) {
            SiteIconThumbnail(image: image, size: 15, cornerRadius: 3)
        } else {
            Image(systemName: tab.isPrivate ? "eyeglasses" : "globe")
                .font(.system(size: 12))
                .foregroundStyle(DesignTokens.textSecondary)
                .frame(width: 15, height: 15)
        }
    }

    @ViewBuilder
    private var tabContextMenu: some View {
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
        Button("在右侧打开", systemImage: "rectangle.split.2x1") {
            onOpenBeside(tab.id)
        }
        .disabled(!session.canOpenTabBeside(tab.id))
        Button("移到新窗口", systemImage: "macwindow.badge.plus") {
            onMoveToWindow(tab.id)
        }
        if !tab.isPrivate {
            Button(tab.isPinned ? "取消固定" : "固定标签页", systemImage: tab.isPinned ? "pin.slash" : "pin") {
                session.toggleTabPinned(tab.id)
            }
        }
    }

    private var dragPreview: some View {
        HStack(spacing: 8) {
            tabIcon
            Text(tab.displayTitle)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(DesignTokens.textPrimary)
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(DesignTokens.surfacePanel, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
