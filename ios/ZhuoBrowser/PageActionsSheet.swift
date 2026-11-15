import SwiftUI
import Foundation

private struct ActionGridTile: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let telemetryKey: String
    let isActive: Bool
    let isDisabled: Bool
    let accessibilityID: String
    let action: () -> Void
}

struct PageActionsSheet: View {
    @EnvironmentObject private var session: BrowserSession
    @Environment(\.dismiss) private var dismiss
    @State private var currentPage = 0

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(DesignTokens.handle)
                .frame(width: 36, height: 4)
                .padding(.top, 10)
                .padding(.bottom, 12)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 14) {
                    quickStrip

                    TabView(selection: $currentPage) {
                        actionGrid(primaryTiles)
                            .tag(0)
                        actionGrid(secondaryTiles)
                            .tag(1)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(height: currentPage == 0 ? 184 : 264)
                    .animation(.easeInOut(duration: 0.2), value: currentPage)

                    HStack(spacing: 6) {
                        ForEach(0..<2, id: \.self) { index in
                            Capsule()
                                .fill(index == currentPage ? DesignTokens.accentStrong : DesignTokens.handle)
                                .frame(width: index == currentPage ? 16 : 6, height: 6)
                                .onTapGesture {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        currentPage = index
                                    }
                                }
                        }
                    }

                    cumulativeBlockingBanner
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(DesignTokens.surfacePanel)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("page-actions-sheet")
    }

    private var quickStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                quickPill(
                    title: "首页",
                    symbol: "house",
                    telemetryKey: "home",
                    disabled: context.isHome,
                    accessibilityID: "page-go-home"
                ) {
                    session.openInActiveTab(URLPolicy.homeURL)
                }

                quickPill(
                    title: "无痕标签",
                    symbol: "eye.slash",
                    telemetryKey: "private_tab",
                    disabled: false,
                    accessibilityID: "page-new-private-tab"
                ) {
                    session.createTab(isPrivate: true)
                }

                quickPill(
                    title: "复制链接",
                    symbol: "doc.on.doc",
                    telemetryKey: "copy_link",
                    disabled: !isBrowsing,
                    accessibilityID: "page-copy-link"
                ) {
                    session.copyCurrentLink()
                }

                quickPill(
                    title: "剪贴板访问",
                    symbol: "arrow.right.doc.on.clipboard",
                    telemetryKey: "clipboard_visit",
                    disabled: false,
                    accessibilityID: "page-visit-clipboard"
                ) {
                    session.visitClipboardLink()
                }

                quickPill(
                    title: "分享",
                    symbol: "square.and.arrow.up",
                    telemetryKey: "share",
                    disabled: !isBrowsing,
                    accessibilityID: "page-share"
                ) {
                    session.shareCurrentPage()
                }
            }
        }
    }

    private func actionGrid(_ tiles: [ActionGridTile]) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)
        return LazyVGrid(columns: columns, spacing: 12) {
            ForEach(tiles) { tile in
                Button {
                    session.recordActionUsage(tile.telemetryKey)
                    dismiss()
                    DispatchQueue.main.async(execute: tile.action)
                } label: {
                    VStack(spacing: 6) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(tile.isActive ? DesignTokens.accentStrong.opacity(0.14) : DesignTokens.surfaceSubtle)
                                .frame(width: 48, height: 48)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(tile.isActive ? DesignTokens.accentStrong.opacity(0.5) : Color.clear, lineWidth: 1)
                                )
                            Image(systemName: tile.symbol)
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(
                                    tile.isDisabled
                                        ? DesignTokens.textSecondary.opacity(0.45)
                                        : (tile.isActive ? DesignTokens.accentStrong : DesignTokens.textPrimary)
                                )
                        }
                        Text(tile.title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(tile.isDisabled ? DesignTokens.textSecondary.opacity(0.55) : DesignTokens.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(tile.isDisabled)
                .accessibilityIdentifier(tile.accessibilityID)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func quickPill(
        title: String,
        symbol: String,
        telemetryKey: String,
        disabled: Bool,
        accessibilityID: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            session.recordActionUsage(telemetryKey)
            dismiss()
            DispatchQueue.main.async(execute: action)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .medium))
                Text(title)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(disabled ? DesignTokens.textSecondary.opacity(0.5) : DesignTokens.textPrimary)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(DesignTokens.surfaceSubtle, in: Capsule())
        }
        .disabled(disabled)
        .accessibilityIdentifier(accessibilityID)
    }

    private var cumulativeBlockingBanner: some View {
        let cumulative = session.observedCumulativeStats()
        let tabTotal = session.tabBlockStats[session.activeTabID]?.total ?? 0
        return Button {
            session.recordActionUsage("blocking")
            dismiss()
            DispatchQueue.main.async {
                if isBrowsing {
                    session.showsBlockPanel = true
                } else {
                    session.openSettings(.privacy)
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "shield.lefthook.filled")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DesignTokens.accentStrong)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isBrowsing ? "本页拦截 \(tabTotal) 次 · 累计拦截 \(cumulative.total) 次" : "累计拦截 \(cumulative.total) 次")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DesignTokens.textPrimary)
                    Text(isBrowsing ? "查看内容拦截与站点例外" : "管理广告、弹窗与跟踪拦截")
                        .font(.system(size: 11))
                        .foregroundStyle(DesignTokens.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DesignTokens.textSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(DesignTokens.surfaceSubtle, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .accessibilityIdentifier("page-blocking-summary")
    }

    private var primaryTiles: [ActionGridTile] {
        [
            ActionGridTile(
                id: "bookmark",
                title: session.isCurrentPageSaved() ? "已加书签" : "加入书签",
                symbol: session.isCurrentPageSaved() ? "star.fill" : "star",
                telemetryKey: "bookmark",
                isActive: session.isCurrentPageSaved(),
                isDisabled: !isBrowsing,
                accessibilityID: "page-toggle-bookmark",
                action: { session.toggleSaved() }
            ),
            ActionGridTile(
                id: "reader",
                title: session.activeTab?.isReader == true ? "退出阅读" : "阅读模式",
                symbol: "doc.plaintext",
                telemetryKey: "reader",
                isActive: session.activeTab?.isReader == true,
                isDisabled: !isBrowsing,
                accessibilityID: "page-toggle-reader",
                action: { session.toggleReader() }
            ),
            ActionGridTile(
                id: "blocking",
                title: "内容拦截",
                symbol: "shield.lefthook.filled",
                telemetryKey: "blocking",
                isActive: false,
                isDisabled: !isBrowsing,
                accessibilityID: "page-blocking",
                action: { session.showsBlockPanel = true }
            ),
            ActionGridTile(
                id: "security",
                title: "网站安全",
                symbol: "lock.shield",
                telemetryKey: "security",
                isActive: false,
                isDisabled: !isBrowsing,
                accessibilityID: "page-security",
                action: { session.openSecurityPanel() }
            ),
            ActionGridTile(
                id: "read_later",
                title: session.isCurrentPageSavedForLater() ? "已稍后读" : "稍后阅读",
                symbol: session.isCurrentPageSavedForLater() ? "bookmark.fill" : "bookmark",
                telemetryKey: "read_later",
                isActive: session.isCurrentPageSavedForLater(),
                isDisabled: !isBrowsing || isPrivate,
                accessibilityID: "page-read-later",
                action: { session.saveCurrentPageForLater() }
            ),
            ActionGridTile(
                id: "article_save",
                title: isSavingArticle ? "保存中…" : "离线保存",
                symbol: "arrow.down.doc",
                telemetryKey: "article_save",
                isActive: false,
                isDisabled: !isBrowsing || isPrivate || isSavingArticle,
                accessibilityID: "page-save-article",
                action: { session.captureCurrentArticle() }
            ),
            ActionGridTile(
                id: "find",
                title: "页内查找",
                symbol: "magnifyingglass",
                telemetryKey: "find",
                isActive: false,
                isDisabled: !isBrowsing,
                accessibilityID: "page-find",
                action: { session.beginFind() }
            ),
            ActionGridTile(
                id: "long_screenshot",
                title: session.isGeneratingScreenshot ? "生成中…" : "页面长截图",
                symbol: "camera.viewfinder",
                telemetryKey: "long_screenshot",
                isActive: false,
                isDisabled: !isBrowsing || session.isGeneratingScreenshot,
                accessibilityID: "page-share-screenshot",
                action: { Task { await session.shareCurrentScreenshot() } }
            )
        ]
    }

    private var secondaryTiles: [ActionGridTile] {
        [
            ActionGridTile(
                id: "desktop",
                title: context.isDesktop ? "移动版" : "桌面版",
                symbol: context.isDesktop ? "iphone" : "desktopcomputer",
                telemetryKey: "desktop",
                isActive: context.isDesktop,
                isDisabled: context.isHome,
                accessibilityID: "page-toggle-desktop",
                action: { session.applyUserAgentOnce(context.isDesktop ? .mobile : .desktop) }
            ),
            ActionGridTile(
                id: "page_settings",
                title: "网页显示",
                symbol: "textformat.size",
                telemetryKey: "page_settings",
                isActive: false,
                isDisabled: !isBrowsing,
                accessibilityID: "page-display-settings",
                action: { session.showsPageSettings = true }
            ),
            ActionGridTile(
                id: "web_dark_mode",
                title: "网页深色",
                symbol: "moon.stars",
                telemetryKey: "web_dark_mode",
                isActive: false,
                isDisabled: false,
                accessibilityID: "page-web-dark-mode",
                action: { session.openSettings(.appearance) }
            ),
            ActionGridTile(
                id: "search_engine",
                title: "搜索引擎",
                symbol: "sparkle.magnifyingglass",
                telemetryKey: "search_engine",
                isActive: false,
                isDisabled: false,
                accessibilityID: "page-search-engine",
                action: { session.openSettings(.search) }
            ),
            ActionGridTile(
                id: "library",
                title: "书签历史",
                symbol: "books.vertical",
                telemetryKey: "library",
                isActive: false,
                isDisabled: false,
                accessibilityID: "page-library",
                action: { session.openLibrary(.bookmarks) }
            ),
            ActionGridTile(
                id: "article_library",
                title: "文章库",
                symbol: "tray.full",
                telemetryKey: "article_library",
                isActive: false,
                isDisabled: false,
                accessibilityID: "page-article-library",
                action: { session.openArticleLibrary() }
            ),
            ActionGridTile(
                id: "recent_tabs",
                title: "最近标签",
                symbol: "square.stack",
                telemetryKey: "recent_tabs",
                isActive: false,
                isDisabled: false,
                accessibilityID: "page-recent-tabs",
                action: { session.showsRecentTabs = true }
            ),
            ActionGridTile(
                id: "navigation_history",
                title: "导航历史",
                symbol: "clock.arrow.circlepath",
                telemetryKey: "navigation_history",
                isActive: false,
                isDisabled: session.activeController == nil,
                accessibilityID: "page-navigation-history",
                action: { session.openNavigationHistory() }
            ),
            ActionGridTile(
                id: "downloads",
                title: "下载管理",
                symbol: "arrow.down.circle",
                telemetryKey: "downloads",
                isActive: false,
                isDisabled: false,
                accessibilityID: "page-downloads",
                action: { session.showsDownloads = true }
            ),
            ActionGridTile(
                id: "report_issue",
                title: "问题诊断",
                symbol: "exclamationmark.bubble",
                telemetryKey: "report_issue",
                isActive: false,
                isDisabled: !isBrowsing,
                accessibilityID: "page-report-issue",
                action: { session.reportPageIssue() }
            ),
            ActionGridTile(
                id: "settings",
                title: "设置",
                symbol: "gearshape",
                telemetryKey: "settings",
                isActive: false,
                isDisabled: false,
                accessibilityID: "page-settings",
                action: { session.openSettings() }
            )
        ]
    }

    private var isBrowsing: Bool {
        context.isBrowsing
    }

    private var isPrivate: Bool {
        context.isPrivate
    }

    private var context: PageActionContext {
        PageActionContext(
            url: session.activeTab?.url ?? URLPolicy.homeURL,
            isPrivate: session.activeTab?.isPrivate == true,
            isDesktop: session.activeTab?.isDesktop == true
        )
    }

    private var isSavingArticle: Bool {
        session.activeTab.map { session.articles.capturingURLs.contains($0.url) } ?? false
    }
}
