import AppKit
import SwiftUI

/// Compact horizontal tab bar with hibernation badges, close buttons, and responsive double-click new tab creation.
public struct CompactTabBarView: View {
    @ObservedObject var session: BrowserSession

    public var body: some View {
        GeometryReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(session.tabs) { tab in
                        TabItemView(
                            tab: tab,
                            siteIcon: session.siteIcon(for: tab),
                            isActive: tab.id == session.activeTabID,
                            onSelect: {
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
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.9).combined(with: .opacity),
                            removal: .scale(scale: 0.8).combined(with: .opacity)
                        ))
                    }

                    // Interactive empty space after tabs: double clicking creates a new tab
                    Spacer(minLength: 40)
                        .frame(height: 28)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                _ = session.createTab()
                            }
                        }
                }
                .frame(minWidth: max(0, proxy.size.width - 20), alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
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
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        HStack(spacing: 6) {
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
            Text(tab.displayTitle)
                .font(.system(size: 12, weight: isActive ? .medium : .regular))
                .foregroundColor(isActive ? .primary : .secondary)
                .lineLimit(1)
                .frame(maxWidth: 160, alignment: .leading)

            // Close tab button with hover state
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
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
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
