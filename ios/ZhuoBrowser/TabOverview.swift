import SwiftUI

struct TabOverview: View {
    @EnvironmentObject private var session: BrowserSession

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(session.tabs.count) 个标签页")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(DesignTokens.textPrimary)
                Spacer()
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
                LazyVGrid(columns: columns, spacing: 12) {
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
        .background(DesignTokens.pageBackground)
        .accessibilityIdentifier("tab-overview")
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
                    Text(URLPolicy.isHomeURL(tab.url) ? "起始页" : tab.url)
                        .font(.system(size: 11))
                        .foregroundStyle(DesignTokens.textSecondary)
                        .lineLimit(2)
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
