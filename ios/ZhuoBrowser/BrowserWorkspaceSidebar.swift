import SwiftUI

enum BrowserSidebarPanel: String, CaseIterable, Identifiable {
    case tabs
    case bookmarks
    case history
    case downloads
    case articles
    case blocking

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tabs: return "标签页"
        case .bookmarks: return "书签"
        case .history: return "历史"
        case .downloads: return "下载"
        case .articles: return "文章"
        case .blocking: return "拦截"
        }
    }

    var symbol: String {
        switch self {
        case .tabs: return "square.on.square"
        case .bookmarks: return "bookmark"
        case .history: return "clock"
        case .downloads: return "arrow.down.circle"
        case .articles: return "doc.richtext"
        case .blocking: return "shield.lefthalf.filled"
        }
    }
}

struct BrowserWorkspaceSidebar: View {
    @EnvironmentObject private var session: BrowserSession
    @Binding var panel: BrowserSidebarPanel
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 3) {
                ForEach(BrowserSidebarPanel.allCases) { item in
                    Button {
                        panel = item
                    } label: {
                        Image(systemName: item.symbol)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(item == panel ? DesignTokens.accent : DesignTokens.textSecondary)
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .background(item == panel ? DesignTokens.surfaceSubtle : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.title)
                    .accessibilityIdentifier("sidebar-\(item.rawValue)")
                }

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DesignTokens.textSecondary)
                        .frame(width: 34, height: 36)
                }
                .accessibilityLabel("关闭侧栏")
                .accessibilityIdentifier("sidebar-close")
            }
            .padding(10)

            Divider()

            panelContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(DesignTokens.pageBackground)
        .overlay(alignment: .leading) {
            Rectangle().fill(DesignTokens.border).frame(width: 1)
        }
        .accessibilityIdentifier("browser-sidebar")
    }

    @ViewBuilder
    private var panelContent: some View {
        switch panel {
        case .tabs:
            tabsPanel
        case .bookmarks:
            bookmarksPanel
        case .history:
            historyPanel
        case .downloads:
            destinationPanel(
                title: "下载",
                detail: session.downloads.tasks.isEmpty ? "暂无下载" : "\(session.downloads.tasks.count) 个下载任务",
                symbol: "arrow.down.circle"
            ) { session.showsDownloads = true }
        case .articles:
            articlesPanel
        case .blocking:
            blockingPanel
        }
    }

    private var tabsPanel: some View {
        VStack(spacing: 0) {
            sidebarHeader("标签页", count: session.tabs.count) {
                session.createTab(isPrivate: session.activeTab?.isPrivate == true)
            }
            List {
                ForEach(session.tabs) { tab in
                    HStack(spacing: 10) {
                        Button {
                            session.selectTab(tab.id)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: tab.isPrivate ? "eyeglasses" : "globe")
                                    .foregroundStyle(tab.id == session.activeTabID ? DesignTokens.accent : DesignTokens.textSecondary)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(tab.displayTitle).lineLimit(1)
                                    Text(URLPolicy.isHomeURL(tab.url) ? "起始页" : URLPolicy.displayHost(tab.url))
                                        .font(.caption)
                                        .foregroundStyle(DesignTokens.textSecondary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 4)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("sidebar-tab-\(tab.id)")

                        Button {
                            session.closeTab(tab.id)
                        } label: {
                            Image(systemName: "xmark").frame(width: 28, height: 28)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("关闭 \(tab.displayTitle)")
                    }
                    .listRowBackground(tab.id == session.activeTabID ? DesignTokens.surfaceSubtle : Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private var bookmarksPanel: some View {
        VStack(spacing: 0) {
            sidebarHeader("书签", count: visibleSavedItems.count)
            if visibleSavedItems.isEmpty {
                emptyState("还没有书签", symbol: "bookmark")
            } else {
                List(visibleSavedItems) { item in
                    Button {
                        session.openInActiveTab(item.url)
                    } label: {
                        sidebarRow(item.title, subtitle: URLPolicy.displayHost(item.url), symbol: "bookmark")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("sidebar-bookmark-\(item.id)")
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private var historyPanel: some View {
        VStack(spacing: 0) {
            sidebarHeader("历史", count: visibleHistory.count)
            if visibleHistory.isEmpty {
                emptyState("还没有历史记录", symbol: "clock")
            } else {
                List(visibleHistory) { entry in
                    Button {
                        session.openInActiveTab(entry.url)
                    } label: {
                        sidebarRow(entry.title, subtitle: URLPolicy.displayHost(entry.url), symbol: "clock")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("sidebar-history-\(entry.id)")
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private var articlesPanel: some View {
        VStack(spacing: 0) {
            sidebarHeader("离线文章", count: session.articles.articles.count)
            if session.articles.articles.isEmpty {
                emptyState("还没有离线文章", symbol: "doc.richtext")
            } else {
                List(session.articles.articles.prefix(30)) { article in
                    Button {
                        session.openArticleLibrary(selecting: article.id)
                    } label: {
                        sidebarRow(
                            article.title.isEmpty ? URLPolicy.displayHost(article.sourceUrl) : article.title,
                            subtitle: URLPolicy.displayHost(article.sourceUrl),
                            symbol: "doc.richtext"
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("sidebar-article-\(article.id)")
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }

            Button("打开文章工作台") { session.openArticleLibrary() }
                .buttonStyle(.borderedProminent)
                .tint(DesignTokens.accent)
                .padding(14)
                .accessibilityIdentifier("sidebar-open-articles")
        }
    }

    private var blockingPanel: some View {
        let page = session.observedStatsForActiveTab()
        return VStack(alignment: .leading, spacing: 14) {
            Text(URLPolicy.displayHost(session.activeTab?.url ?? ""))
                .font(.subheadline)
                .foregroundStyle(DesignTokens.textSecondary)
            Text("\(page.total)")
                .font(.system(size: 48, weight: .medium, design: .rounded))
            Text("本页可观察清理")
                .foregroundStyle(DesignTokens.textSecondary)
            Divider()
            Button("查看详细控制") { session.showsBlockPanel = true }
                .buttonStyle(.borderedProminent)
                .tint(DesignTokens.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(24)
    }

    private var visibleSavedItems: [SavedItem] {
        session.activeTab?.isPrivate == true ? [] : Array(session.savedItems.prefix(50))
    }

    private var visibleHistory: [HistoryEntry] {
        session.activeTab?.isPrivate == true
            ? []
            : Array(session.history.sorted { $0.visitedAt > $1.visitedAt }.prefix(50))
    }

    private func sidebarHeader(_ title: String, count: Int, action: (() -> Void)? = nil) -> some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
            Text("\(count)").font(.caption).foregroundStyle(DesignTokens.textSecondary)
            if let action {
                Button(action: action) { Image(systemName: "plus") }
                    .accessibilityLabel("新建标签页")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
    }

    private func sidebarHeader(_ title: String, count: Int) -> some View {
        sidebarHeader(title, count: count, action: nil)
    }

    private func sidebarRow(_ title: String, subtitle: String, symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(DesignTokens.textSecondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(DesignTokens.textSecondary).lineLimit(1)
            }
        }
        .contentShape(Rectangle())
    }

    private func destinationPanel(title: String, detail: String, symbol: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 34)).foregroundStyle(DesignTokens.textSecondary)
            Text(title).font(.headline)
            Text(detail).font(.subheadline).foregroundStyle(DesignTokens.textSecondary)
            Button("打开") { action() }
                .buttonStyle(.borderedProminent)
                .tint(DesignTokens.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func emptyState(_ title: String, symbol: String) -> some View {
        ContentUnavailableView(title, systemImage: symbol)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
