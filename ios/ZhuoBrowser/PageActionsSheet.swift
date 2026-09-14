import SwiftUI
import Foundation

struct PageActionsSheet: View {
    @EnvironmentObject private var session: BrowserSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("阅读与显示") {
                    actionButton(session.activeTab?.isReader == true ? "退出阅读模式" : "阅读模式") {
                        session.toggleReader()
                    }
                    .disabled(!isBrowsing)
                    actionButton("在页面中查找") { session.beginFind() }
                        .disabled(!isBrowsing)
                    actionButton("网页显示") { session.showsPageSettings = true }
                        .disabled(!isBrowsing)
                    actionButton("内容拦截") { session.showsBlockPanel = true }
                        .disabled(!isBrowsing)
                    actionButton("网站安全") { session.openSecurityPanel() }
                        .disabled(!isBrowsing)
                }

                Section("收藏与文章") {
                    actionButton(session.isCurrentPageSaved() ? "取消书签" : "加入书签") {
                        session.toggleSaved()
                    }
                    .disabled(!isBrowsing)
                    actionButton(session.isCurrentPageSavedForLater() ? "已加入稍后读" : "稍后阅读") {
                        session.saveCurrentPageForLater()
                    }
                    .disabled(!isBrowsing || isPrivate)
                    actionButton(isSavingArticle ? "正在保存文章" : "保存离线文章") {
                        session.captureCurrentArticle()
                    }
                    .disabled(!isBrowsing || isPrivate || isSavingArticle)
                    actionButton("离线文章库") { session.openArticleLibrary() }
                    actionButton("书签与历史") { session.openLibrary(.bookmarks) }
                    actionButton("导航历史") { session.openNavigationHistory() }
                        .disabled(session.activeController == nil)
                }

                Section("分享与工具") {
                    actionButton("分享") { session.shareCurrentPage() }
                        .disabled(!isBrowsing)
                    actionButton(session.isGeneratingScreenshot ? "正在生成长截图" : "分享页面长截图") {
                        Task { await session.shareCurrentScreenshot() }
                    }
                    .disabled(!isBrowsing || session.isGeneratingScreenshot)
                    .accessibilityIdentifier("page-share-screenshot")
                    actionButton("复制链接") { session.copyCurrentLink() }
                        .disabled(!isBrowsing)
                        .accessibilityIdentifier("page-copy-link")
                    actionButton("访问剪贴板链接") { session.visitClipboardLink() }
                        .accessibilityIdentifier("page-visit-clipboard")
                    actionButton("报告页面问题") { session.reportPageIssue() }
                        .disabled(!isBrowsing)
                        .accessibilityIdentifier("page-report-issue")
                    actionButton("下载") { session.showsDownloads = true }
                    actionButton("设置") { session.showsSettings = true }
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
        !(session.activeTab.map { URLPolicy.isHomeURL($0.url) } ?? true)
    }

    private var isPrivate: Bool {
        session.activeTab?.isPrivate == true
    }

    private var isSavingArticle: Bool {
        session.activeTab.map { session.articles.capturingURLs.contains($0.url) } ?? false
    }

    private func actionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title) {
            dismiss()
            DispatchQueue.main.async(execute: action)
        }
    }
}
