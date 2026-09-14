import SwiftUI
import Foundation

struct PageActionsSheet: View {
    @EnvironmentObject private var session: BrowserSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("浏览") {
                    actionButton("首页", telemetryKey: "home") {
                        session.openInActiveTab(URLPolicy.homeURL)
                    }
                    .disabled(context.isHome)
                    .accessibilityIdentifier("page-go-home")
                    actionButton("新建无痕标签页", telemetryKey: "private_tab") {
                        session.createTab(isPrivate: true)
                    }
                    .accessibilityIdentifier("page-new-private-tab")
                    actionButton(
                        context.isDesktop ? "切换到移动版" : "切换到桌面版",
                        telemetryKey: "desktop"
                    ) {
                        session.applyUserAgentOnce(context.isDesktop ? .mobile : .desktop)
                    }
                    .disabled(context.isHome)
                    .accessibilityIdentifier("page-toggle-desktop")
                    actionButton("网页深色模式", telemetryKey: "web_dark_mode") {
                        session.openSettings(.appearance)
                    }
                    .accessibilityIdentifier("page-web-dark-mode")
                    actionButton("默认搜索引擎", telemetryKey: "search_engine") {
                        session.openSettings(.search)
                    }
                    .accessibilityIdentifier("page-search-engine")
                }

                Section("阅读与显示") {
                    actionButton(
                        session.activeTab?.isReader == true ? "退出阅读模式" : "阅读模式",
                        telemetryKey: "reader"
                    ) {
                        session.toggleReader()
                    }
                    .disabled(!isBrowsing)
                    actionButton("在页面中查找", telemetryKey: "find") { session.beginFind() }
                        .disabled(!isBrowsing)
                    actionButton("网页显示", telemetryKey: "page_settings") { session.showsPageSettings = true }
                        .disabled(!isBrowsing)
                    actionButton("内容拦截", telemetryKey: "blocking") { session.showsBlockPanel = true }
                        .disabled(!isBrowsing)
                    actionButton("网站安全", telemetryKey: "security") { session.openSecurityPanel() }
                        .disabled(!isBrowsing)
                }

                Section("收藏与文章") {
                    actionButton(
                        session.isCurrentPageSaved() ? "取消书签" : "加入书签",
                        telemetryKey: "bookmark"
                    ) {
                        session.toggleSaved()
                    }
                    .disabled(!isBrowsing)
                    actionButton(
                        session.isCurrentPageSavedForLater() ? "已加入稍后读" : "稍后阅读",
                        telemetryKey: "read_later"
                    ) {
                        session.saveCurrentPageForLater()
                    }
                    .disabled(!isBrowsing || isPrivate)
                    actionButton(
                        isSavingArticle ? "正在保存文章" : "保存离线文章",
                        telemetryKey: "article_save"
                    ) {
                        session.captureCurrentArticle()
                    }
                    .disabled(!isBrowsing || isPrivate || isSavingArticle)
                    actionButton("离线文章库", telemetryKey: "article_library") { session.openArticleLibrary() }
                    actionButton("书签与历史", telemetryKey: "library") { session.openLibrary(.bookmarks) }
                    actionButton("导航历史", telemetryKey: "navigation_history") { session.openNavigationHistory() }
                        .disabled(session.activeController == nil)
                    actionButton("最近标签页", telemetryKey: "recent_tabs") {
                        session.showsRecentTabs = true
                    }
                }

                Section("分享与工具") {
                    actionButton("分享", telemetryKey: "share") { session.shareCurrentPage() }
                        .disabled(!isBrowsing)
                    actionButton(
                        session.isGeneratingScreenshot ? "正在生成长截图" : "分享页面长截图",
                        telemetryKey: "long_screenshot"
                    ) {
                        Task { await session.shareCurrentScreenshot() }
                    }
                    .disabled(!isBrowsing || session.isGeneratingScreenshot)
                    .accessibilityIdentifier("page-share-screenshot")
                    actionButton("复制链接", telemetryKey: "copy_link") { session.copyCurrentLink() }
                        .disabled(!isBrowsing)
                        .accessibilityIdentifier("page-copy-link")
                    actionButton("访问剪贴板链接", telemetryKey: "clipboard_visit") { session.visitClipboardLink() }
                        .accessibilityIdentifier("page-visit-clipboard")
                    actionButton("报告页面问题", telemetryKey: "report_issue") { session.reportPageIssue() }
                        .disabled(!isBrowsing)
                        .accessibilityIdentifier("page-report-issue")
                    actionButton("下载", telemetryKey: "downloads") { session.showsDownloads = true }
                    actionButton("设置", telemetryKey: "settings") { session.openSettings() }
                }
            }
            .scrollContentBackground(.hidden)
            .background(DesignTokens.pageBackground)
            .navigationTitle("页面工具")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .accessibilityIdentifier("page-actions-sheet")
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

    private func actionButton(
        _ title: String,
        telemetryKey: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(title) {
            session.recordActionUsage(telemetryKey)
            dismiss()
            DispatchQueue.main.async(execute: action)
        }
    }
}
