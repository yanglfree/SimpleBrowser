import SwiftUI

struct RecentTabsSheet: View {
    @EnvironmentObject private var session: BrowserSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(session.recentTabs) { tab in
                            recentTabButton(tab)
                        }
                        newTabButton
                    }
                    .padding(.horizontal, 20)
                }
                .frame(height: 112)

                Spacer(minLength: 0)
            }
            .padding(.top, 8)
            .background(DesignTokens.pageBackground)
            .navigationTitle("最近标签页")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("全部标签页") {
                        dismiss()
                        DispatchQueue.main.async {
                            session.showsOverview = true
                        }
                    }
                    .accessibilityIdentifier("recent-tabs-all")
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .accessibilityIdentifier("recent-tabs-sheet")
    }

    private func recentTabButton(_ tab: BrowserTab) -> some View {
        let isActive = tab.id == session.activeTabID
        return Button {
            session.selectTab(tab.id)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    if isActive {
                        Circle()
                            .fill(DesignTokens.accent)
                            .frame(width: 7, height: 7)
                    }
                    if let image = session.siteIcon(for: tab) {
                        SiteIconThumbnail(image: image, size: 18, cornerRadius: 4)
                    }
                    Text(tabTitle(tab))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(DesignTokens.textPrimary)
                        .lineLimit(1)
                }
                Text(tab.isPrivate ? "无痕" : tabHost(tab))
                    .font(.system(size: 12))
                    .foregroundStyle(DesignTokens.textSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .frame(width: 184, height: 88, alignment: .leading)
            .background(
                isActive ? DesignTokens.surfaceSubtle : DesignTokens.surfacePanel,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isActive ? DesignTokens.accent : DesignTokens.border, lineWidth: isActive ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("recent-tab-\(tab.id)")
    }

    private var newTabButton: some View {
        Button {
            session.createTab(isPrivate: session.activeTab?.isPrivate == true)
            dismiss()
        } label: {
            VStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(DesignTokens.accent)
                Text("新建标签页")
                    .font(.system(size: 12))
                    .foregroundStyle(DesignTokens.textSecondary)
                    .lineLimit(1)
            }
            .frame(width: 104, height: 88)
            .background(DesignTokens.surfacePanel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(DesignTokens.border, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("recent-tabs-new")
    }

    private func tabTitle(_ tab: BrowserTab) -> String {
        URLPolicy.isHomeURL(tab.url) ? "新建标签页" : tab.displayTitle
    }

    private func tabHost(_ tab: BrowserTab) -> String {
        let host = URLPolicy.displayHost(tab.url)
        return host.isEmpty ? "新建标签页" : host
    }
}
