import AppKit
import SwiftUI

/// Calculates dynamic tab width in desktop browser style (Chrome / Edge / Safari).
/// - Parameters:
///   - availableWidth: Width available inside the tab bar container (excluding outer padding).
///   - tabCount: Number of open tabs.
///   - minWidth: Minimum allowed tab width to prevent unclickable slivers (default: 52px).
///   - maxWidth: Maximum allowed tab width when there are few tabs (default: 240px).
///   - gap: Spacing between adjacent tabs (default: 4px).
///   - trailingReserved: Minimum width reserved at the end for double-clicking / new tab creation (default: 36px).
/// - Returns: Clamped target tab width.
public func compactTabWidth(
    availableWidth: CGFloat,
    tabCount: Int,
    minWidth: CGFloat = 52,
    maxWidth: CGFloat = 240,
    gap: CGFloat = 4,
    trailingReserved: CGFloat = 36
) -> CGFloat {
    guard tabCount > 0 else { return maxWidth }
    let safeAvailable = max(0, availableWidth)
    let totalGaps = CGFloat(max(0, tabCount - 1)) * gap
    let usableWidth = safeAvailable - trailingReserved - totalGaps
    guard usableWidth > 0 else { return minWidth }
    let calculated = usableWidth / CGFloat(tabCount)
    return min(maxWidth, max(minWidth, calculated))
}

/// Compact horizontal tab bar with hibernation badges, close buttons, and responsive double-click new tab creation.
public struct CompactTabBarView: View {
    @ObservedObject var session: BrowserSession

    public static let defaultMaxTabWidth: CGFloat = 240
    public static let defaultMinTabWidth: CGFloat = 52
    public static let defaultTabGap: CGFloat = 4
    public static let horizontalPadding: CGFloat = 20
    public static let trailingReservedWidth: CGFloat = 36

    public var body: some View {
        GeometryReader { proxy in
            let tabWidth = compactTabWidth(
                availableWidth: proxy.size.width - Self.horizontalPadding,
                tabCount: session.tabs.count,
                minWidth: Self.defaultMinTabWidth,
                maxWidth: Self.defaultMaxTabWidth,
                gap: Self.defaultTabGap,
                trailingReserved: Self.trailingReservedWidth
            )

            ScrollViewReader { scrollProxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Self.defaultTabGap) {
                        ForEach(session.tabs) { tab in
                            TabItemView(
                                tab: tab,
                                siteIcon: session.siteIcon(for: tab),
                                isActive: tab.id == session.activeTabID,
                                tabWidth: tabWidth,
                                onSelect: {
                                    NSApp.keyWindow?.makeFirstResponder(nil)
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        session.selectTab(id: tab.id)
                                    }
                                },
                                onClose: {
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                                        session.closeTab(id: tab.id)
                                    }
                                }
                            )
                            .id(tab.id)
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.9).combined(with: .opacity),
                                removal: .scale(scale: 0.8).combined(with: .opacity)
                            ))
                        }

                        // Interactive empty space after tabs: native double clicking creates a new tab
                        // without bubble-up to NSWindow's titlebar actions or forcing heavy spring animations.
                        TabBarDoubleClickBackground {
                            _ = session.createTab()
                        }
                        .frame(minWidth: Self.trailingReservedWidth, maxWidth: .infinity)
                        .frame(height: 28)
                    }
                    .frame(minWidth: max(0, proxy.size.width - Self.horizontalPadding), alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                }
                .onChange(of: session.activeTabID) { activeID in
                    guard let activeID else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        scrollProxy.scrollTo(activeID, anchor: .center)
                    }
                }
            }
        }
        .frame(height: 36)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(
            Divider(),
            alignment: .bottom
        )
    }
}

/// Single tab item with hover effects, smooth transitions, and distinct hibernated badges.
private struct TabItemView: View {
    let tab: BrowserTab
    let siteIcon: NSImage?
    let isActive: Bool
    let tabWidth: CGFloat
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovered: Bool = false

    /// When tab is narrow (< 80px), only show close button if active or hovered,
    /// so inactive tabs don't waste precious space on close buttons.
    private var showsCloseButton: Bool {
        tabWidth >= 80 || isActive || isHovered
    }

    /// When tab is extremely narrow (< 56px) and showing close button, omit title to prevent overlapping.
    private var showsTitle: Bool {
        tabWidth >= 56 || !showsCloseButton
    }

    var body: some View {
        HStack(spacing: 5) {
            // Status indicator: Loading, Frozen, Possibly-stale, or Normal
            if tab.isLoading {
                ProgressView()
                    .controlSize(.mini)
                    .frame(width: 14, height: 14)
            } else if tab.isHibernated {
                if let siteIcon {
                    SiteIconThumbnail(image: siteIcon, size: 14)
                        .opacity(0.65)
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "moon.zzz.fill")
                                .font(.system(size: 6))
                                .foregroundColor(.blue)
                                .offset(x: 2, y: 2)
                        }
                        .help("此标签已冻结并释放渲染进程，页面快照已保留。点击即可瞬时恢复，无需重新加载。")
                } else {
                    Image(systemName: "moon.zzz.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.blue.opacity(0.85))
                        .frame(width: 14, height: 14)
                        .help("此标签已冻结并释放渲染进程，页面快照已保留。点击即可瞬时恢复，无需重新加载。")
                }
            } else if tab.isSnapshotStale {
                if let siteIcon {
                    SiteIconThumbnail(image: siteIcon, size: 14)
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 6))
                                .foregroundColor(.orange)
                                .offset(x: 2, y: 2)
                        }
                        .help("此页面由较旧的快照恢复，内容可能已过期。按 Cmd+R 可刷新最新内容。")
                } else {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                        .frame(width: 14, height: 14)
                        .help("此页面由较旧的快照恢复，内容可能已过期。按 Cmd+R 可刷新最新内容。")
                }
            } else if tab.isPrivate {
                Image(systemName: "lock.shield")
                    .font(.system(size: 11))
                    .foregroundColor(isActive ? .primary : .secondary)
                    .frame(width: 14, height: 14)
            } else if let siteIcon {
                SiteIconThumbnail(image: siteIcon, size: 14)
            } else {
                Image(systemName: "globe")
                    .font(.system(size: 11))
                    .foregroundColor(isActive ? .primary : .secondary)
                    .frame(width: 14, height: 14)
            }

            // Tab title
            if showsTitle {
                Text(tab.displayTitle)
                    .font(.system(size: 12, weight: isActive ? .medium : .regular))
                    .foregroundColor(isActive ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Close tab button with hover state
            if showsCloseButton {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(isHovered || isActive ? .primary.opacity(0.8) : .secondary.opacity(0.5))
                        .frame(width: 16, height: 16)
                        .background(isHovered ? Color.secondary.opacity(0.15) : Color(nsColor: .clear))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("关闭标签页 (Cmd+W)")
                .transition(.opacity)
            }
        }
        .padding(.horizontal, tabWidth < 70 ? 6 : 8)
        .padding(.vertical, 5)
        .frame(width: tabWidth, height: 28)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive ? Color(nsColor: .controlBackgroundColor) : (isHovered ? Color.secondary.opacity(0.08) : Color(nsColor: .clear)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isActive ? Color.secondary.opacity(0.2) : Color(nsColor: .clear), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            onSelect()
        }
    }
}

/// Transparent AppKit view providing instant double-click new tab creation while consuming
/// mouse events to prevent bubble-up to NSWindow's titlebar zoom/drag behavior.
public struct TabBarDoubleClickBackground: NSViewRepresentable {
    public let onDoubleClick: () -> Void

    public init(onDoubleClick: @escaping () -> Void) {
        self.onDoubleClick = onDoubleClick
    }

    public func makeNSView(context: Context) -> TabBarDoubleClickNSView {
        let view = TabBarDoubleClickNSView()
        view.onDoubleClick = onDoubleClick
        return view
    }

    public func updateNSView(_ nsView: TabBarDoubleClickNSView, context: Context) {
        nsView.onDoubleClick = onDoubleClick
    }
}

public final class TabBarDoubleClickNSView: NSView {
    public var onDoubleClick: (() -> Void)?
    private var lastTriggerTime: TimeInterval = 0

    public override var mouseDownCanMoveWindow: Bool {
        false
    }

    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    public override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            let now = ProcessInfo.processInfo.systemUptime
            if now - lastTriggerTime > 0.25 {
                lastTriggerTime = now
                onDoubleClick?()
            }
        }
        // Deliberately consume the event without calling super, preventing NSWindow
        // from interpreting double-clicks as system titlebar zoom or background drag.
    }
}
