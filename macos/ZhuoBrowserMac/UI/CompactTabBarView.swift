import SwiftUI

/// Compact horizontal tab bar with hibernation badges and close buttons.
public struct CompactTabBarView: View {
    @ObservedObject var session: BrowserSession

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(session.tabs) { tab in
                    tabItemView(for: tab)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
        }
        .background(Color(NSColor.windowBackgroundColor).opacity(0.8))
        .overlay(
            Divider(),
            alignment: .bottom
        )
    }

    @ViewBuilder
    private func tabItemView(for tab: BrowserTab) -> some View {
        let isActive = tab.id == session.activeTabID

        HStack(spacing: 6) {
            // Status: Loading or Hibernated
            if tab.isLoading {
                ProgressView()
                    .controlSize(.mini)
            } else if tab.isHibernated {
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.blue.opacity(0.8))
                    .help("此标签已休眠冻结，释放了系统内存。点击即可瞬间唤醒。")
            } else {
                Image(systemName: tab.isPrivate ? "lock.shield" : "globe")
                    .font(.system(size: 11))
                    .foregroundColor(isActive ? .primary : .secondary)
            }

            // Title
            Text(tab.displayTitle)
                .font(.system(size: 12, weight: isActive ? .medium : .regular))
                .foregroundColor(isActive ? .primary : .secondary)
                .lineLimit(1)
                .frame(maxWidth: 160, alignment: .leading)

            // Close Tab Button
            Button(action: {
                session.closeTab(id: tab.id)
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.plain)
            .help("关闭标签页 (Cmd+W)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive ? Color(NSColor.controlBackgroundColor) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isActive ? Color.secondary.opacity(0.15) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            session.selectTab(id: tab.id)
        }
    }
}
