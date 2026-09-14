import SwiftUI
import UniformTypeIdentifiers

private struct BookmarkTransferMessage: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

struct SettingsSheet: View {
    @EnvironmentObject private var session: BrowserSession
    @Environment(\.dismiss) private var dismiss
    @State private var isImportingBookmarks = false
    @State private var isExportingBookmarks = false
    @State private var exportDocument: BookmarkHTMLDocument?
    @State private var transferMessage: BookmarkTransferMessage?
    @State private var showsClearBrowsingData = false

    var body: some View {
        NavigationStack {
            List {
                Section("卓阅 Pro") {
                    Button {
                        session.showsSettings = false
                        DispatchQueue.main.async {
                            session.showsProPaywall = true
                        }
                    } label: {
                        HStack {
                            Label(session.pro.isPro ? "Pro 已激活" : "升级卓阅 Pro", systemImage: "crown.fill")
                            Spacer()
                            if session.pro.isPro {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundStyle(DesignTokens.accent)
                            }
                        }
                    }
                    .accessibilityIdentifier("settings-pro")
                    Link("联系支持", destination: URL(string: "mailto:youdroid2048@gmail.com")!)
                        .accessibilityIdentifier("settings-support")
                }

                Section("外观") {
                    Picker("应用外观", selection: appearanceBinding) {
                        ForEach(AppearanceMode.allCases) { appearance in
                            Text(appearance.label).tag(appearance)
                        }
                    }
                    .accessibilityIdentifier("settings-appearance")
                    Picker("网页外观", selection: webDarkModeBinding) {
                        ForEach(WebDarkModePreference.allCases) { preference in
                            Text(preference.label).tag(preference)
                        }
                    }
                    .accessibilityIdentifier("settings-web-appearance")
                    Picker("网页最小字号", selection: minimumFontSizeBinding) {
                        ForEach([12, 14, 16, 18], id: \.self) { size in
                            Text("\(size) pt").tag(size)
                        }
                    }
                    .accessibilityIdentifier("settings-minimum-font-size")
                }

                Section("搜索引擎") {
                    ForEach(SearchEngine.allCases) { engine in
                        Button {
                            session.setSearchEngine(engine)
                        } label: {
                            HStack {
                                Text(engine.label)
                                    .foregroundStyle(DesignTokens.textPrimary)
                                Spacer()
                                if session.settings.searchEngine == engine {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(DesignTokens.accent)
                                }
                            }
                        }
                        .accessibilityIdentifier("search-engine-\(engine.rawValue)")
                    }
                }

                Section("内容拦截") {
                    Toggle(isOn: blockAdsBinding) {
                        Text("拦截广告与跟踪器")
                    }
                    .tint(DesignTokens.accent)
                    .accessibilityIdentifier("settings-block-ads")
                    Picker("规则强度", selection: ruleStrengthBinding) {
                        ForEach(RuleStrength.allCases) { strength in
                            Text(strength.label).tag(strength)
                        }
                    }
                    .disabled(!session.settings.blockAds)
                    .accessibilityIdentifier("settings-rule-strength")
                    Button {
                        session.reloadBundledRules()
                    } label: {
                        HStack {
                            Text("重新加载内置规则")
                            Spacer()
                            if session.isRulesUpdating {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(session.isRulesUpdating)
                    .accessibilityIdentifier("settings-reload-rules")
                    if session.settings.rulesLastUpdatedAt > 0 {
                        Text("上次加载：\(Self.ruleDateFormatter.string(from: Date(timeIntervalSince1970: session.settings.rulesLastUpdatedAt)))")
                            .font(.caption)
                            .foregroundStyle(DesignTokens.textSecondary)
                    }
                    if !session.sitePermissions.isEmpty {
                        ForEach(session.sitePermissions) { entry in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.origin)
                                    .foregroundStyle(DesignTokens.textPrimary)
                                    .lineLimit(1)
                                Text(permissionSummary(entry))
                                    .font(.system(size: 12))
                                    .foregroundStyle(DesignTokens.textSecondary)
                            }
                            .accessibilityIdentifier("site-permission-\(entry.origin)")
                        }
                        .onDelete { offsets in
                            let origins = offsets.compactMap {
                                session.sitePermissions.indices.contains($0) ? session.sitePermissions[$0].origin : nil
                            }
                            origins.forEach { session.removeSitePermission($0) }
                        }
                    }
                    if !session.allowedHosts.isEmpty {
                        ForEach(session.allowedHosts, id: \.self) { host in
                            HStack {
                                Text(host)
                                    .foregroundStyle(DesignTokens.textPrimary)
                                Spacer()
                                Button("恢复拦截") {
                                    session.removeAllowedHost(host)
                                }
                                .font(.system(size: 13))
                                .foregroundStyle(DesignTokens.accent)
                            }
                            .accessibilityIdentifier("allowed-host-\(host)")
                        }
                    }
                }

                Section("地址栏") {
                    Toggle(isOn: searchSuggestionsBinding) {
                        Text("显示搜索建议")
                    }
                    .tint(DesignTokens.accent)
                    .accessibilityIdentifier("settings-search-suggestions")
                }

                Section("起始页") {
                    Toggle("显示快捷站点", isOn: quickSitesEnabledBinding)
                        .tint(DesignTokens.accent)
                        .accessibilityIdentifier("settings-quick-sites")
                    Stepper(value: quickSiteLimitBinding, in: 4...8) {
                        Text("显示数量：\(session.settings.quickSiteLimit)")
                    }
                    .disabled(!session.settings.quickSitesEnabled)
                    .accessibilityIdentifier("settings-quick-site-limit")
                    Picker("首页背景", selection: homeBackgroundBinding) {
                        ForEach(HomeBackgroundStyle.allCases) { style in
                            Text(style.label).tag(style)
                        }
                    }
                    .accessibilityIdentifier("settings-home-background")
                    NavigationLink("管理快捷站点") {
                        QuickSiteManagerView()
                            .environmentObject(session)
                    }
                    .accessibilityIdentifier("settings-manage-quick-sites")
                }

                Section("标签页") {
                    Picker("自动归档", selection: tabExpiryBinding) {
                        ForEach(TabExpiry.allCases) { expiry in
                            Text(expiry.label).tag(expiry)
                        }
                    }
                    .accessibilityIdentifier("settings-tab-expiry")
                    Picker("活动网页数量", selection: liveWebViewLimitBinding) {
                        ForEach([1, 2, 4, 6], id: \.self) { value in
                            Text("\(value) 个").tag(value)
                        }
                    }
                    .accessibilityIdentifier("settings-live-webview-limit")
                    Picker("标签页提醒", selection: tabSoftLimitBinding) {
                        ForEach([8, 12, 20, 40], id: \.self) { value in
                            Text("\(value) 个").tag(value)
                        }
                    }
                    .accessibilityIdentifier("settings-tab-soft-limit")
                }

                Section("书签与历史") {
                    Button("书签与历史") {
                        session.showsSettings = false
                        DispatchQueue.main.async {
                            session.openLibrary(.bookmarks)
                        }
                    }
                    .accessibilityIdentifier("settings-library")
                    Picker("历史保留时长", selection: historyRetentionBinding) {
                        ForEach(HistoryRetention.allCases) { retention in
                            Text(retention.label).tag(retention)
                        }
                    }
                    .accessibilityIdentifier("settings-history-retention")
                    Button("导入 HTML 书签") {
                        isImportingBookmarks = true
                    }
                    .accessibilityIdentifier("settings-import-bookmarks")
                    Button("导出 HTML 书签") {
                        exportDocument = BookmarkHTMLDocument(html: session.bookmarkExportHTML())
                        isExportingBookmarks = true
                    }
                    .accessibilityIdentifier("settings-export-bookmarks")
                }

                Section("下载") {
                    Button("下载内容") {
                        session.showsSettings = false
                        DispatchQueue.main.async {
                            session.showsDownloads = true
                        }
                    }
                    .accessibilityIdentifier("settings-downloads")
                    Picker("同时下载", selection: downloadConcurrencyBinding) {
                        ForEach(1...6, id: \.self) { value in
                            Text("\(value) 个").tag(value)
                        }
                    }
                    .accessibilityIdentifier("settings-download-concurrency")
                    Picker("大文件提醒", selection: largeDownloadThresholdBinding) {
                        ForEach([10, 25, 50, 100, 250], id: \.self) { value in
                            Text("\(value) MB").tag(value)
                        }
                    }
                    .accessibilityIdentifier("settings-large-download-threshold")
                    Toggle("仅 Wi-Fi 下载", isOn: wifiOnlyDownloadsBinding)
                        .tint(DesignTokens.accent)
                        .accessibilityIdentifier("settings-wifi-only-downloads")
                    Toggle("下载完成提醒", isOn: downloadNotificationsBinding)
                        .tint(DesignTokens.accent)
                        .accessibilityIdentifier("settings-download-notifications")
                }

                Section("隐私") {
                    Toggle("关闭标签时清除 Cookie", isOn: clearCookiesOnTabCloseBinding)
                        .tint(DesignTokens.accent)
                        .accessibilityIdentifier("settings-clear-cookies-on-close")
                    Button("清除浏览数据", role: .destructive) {
                        showsClearBrowsingData = true
                    }
                    .accessibilityIdentifier("settings-clear-data")
                }
            }
            .scrollContentBackground(.hidden)
            .background(DesignTokens.pageBackground)
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                        .accessibilityIdentifier("settings-done")
                }
            }
        }
        .fileImporter(
            isPresented: $isImportingBookmarks,
            allowedContentTypes: [.html]
        ) { result in
            handleBookmarkImport(result)
        }
        .fileExporter(
            isPresented: $isExportingBookmarks,
            document: exportDocument,
            contentType: .html,
            defaultFilename: "browser-bookmarks"
        ) { result in
            switch result {
            case .success:
                transferMessage = BookmarkTransferMessage(title: "书签已导出", message: "HTML 文件已保存。")
            case .failure(let error):
                transferMessage = BookmarkTransferMessage(title: "无法导出书签", message: error.localizedDescription)
            }
        }
        .alert(item: $transferMessage) { message in
            Alert(title: Text(message.title), message: Text(message.message), dismissButton: .default(Text("好")))
        }
        .sheet(isPresented: $showsClearBrowsingData) {
            ClearBrowsingDataSheet()
                .environmentObject(session)
        }
        .accessibilityIdentifier("settings-sheet")
    }

    private func handleBookmarkImport(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            let count = try session.importBookmarks(BookmarkTransfer.readImportData(from: url))
            transferMessage = BookmarkTransferMessage(
                title: "导入完成",
                message: "已导入 \(count) 个新书签。"
            )
        } catch let error as CocoaError where error.code == .userCancelled {
            return
        } catch {
            transferMessage = BookmarkTransferMessage(title: "无法导入书签", message: error.localizedDescription)
        }
    }

    private func permissionSummary(_ entry: SitePermission) -> String {
        SitePermissionKind.allCases.compactMap { kind in
            let decision = entry.decision(for: kind)
            guard decision != .prompt else {
                return nil
            }
            return "\(kind.label)\(decision == .allow ? "允许" : "拒绝")"
        }.joined(separator: " · ")
    }

    private var searchSuggestionsBinding: Binding<Bool> {
        Binding(
            get: { session.settings.searchSuggestionsEnabled },
            set: { session.setSearchSuggestionsEnabled($0) }
        )
    }

    private var blockAdsBinding: Binding<Bool> {
        Binding(
            get: { session.settings.blockAds },
            set: { session.setBlockAds($0) }
        )
    }

    private var ruleStrengthBinding: Binding<RuleStrength> {
        Binding(
            get: { session.settings.ruleStrength },
            set: { session.setRuleStrength($0) }
        )
    }

    private static let ruleDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    private var appearanceBinding: Binding<AppearanceMode> {
        Binding(
            get: { session.settings.appearance },
            set: { session.setAppearance($0) }
        )
    }

    private var webDarkModeBinding: Binding<WebDarkModePreference> {
        Binding(
            get: { session.settings.webDarkMode },
            set: { session.setWebDarkMode($0) }
        )
    }

    private var minimumFontSizeBinding: Binding<Int> {
        Binding(
            get: { session.settings.minimumFontSize },
            set: { session.setMinimumFontSize($0) }
        )
    }

    private var quickSitesEnabledBinding: Binding<Bool> {
        Binding(
            get: { session.settings.quickSitesEnabled },
            set: { session.setQuickSitesEnabled($0) }
        )
    }

    private var quickSiteLimitBinding: Binding<Int> {
        Binding(
            get: { session.settings.quickSiteLimit },
            set: { session.setQuickSiteLimit($0) }
        )
    }

    private var homeBackgroundBinding: Binding<HomeBackgroundStyle> {
        Binding(
            get: { session.settings.homeBackgroundStyle },
            set: { session.setHomeBackgroundStyle($0) }
        )
    }

    private var tabExpiryBinding: Binding<TabExpiry> {
        Binding(
            get: { session.settings.tabExpiry },
            set: { session.setTabExpiry($0) }
        )
    }

    private var liveWebViewLimitBinding: Binding<Int> {
        Binding(
            get: { session.settings.liveWebViewLimit },
            set: { session.setLiveWebViewLimit($0) }
        )
    }

    private var tabSoftLimitBinding: Binding<Int> {
        Binding(
            get: { session.settings.tabSoftLimit },
            set: { session.setTabSoftLimit($0) }
        )
    }

    private var historyRetentionBinding: Binding<HistoryRetention> {
        Binding(
            get: { session.settings.historyRetention },
            set: { session.setHistoryRetention($0) }
        )
    }

    private var downloadConcurrencyBinding: Binding<Int> {
        Binding(
            get: { session.settings.downloadConcurrency },
            set: { session.setDownloadConcurrency($0) }
        )
    }

    private var largeDownloadThresholdBinding: Binding<Int> {
        Binding(
            get: { session.settings.largeDownloadThresholdMB },
            set: { session.setLargeDownloadThresholdMB($0) }
        )
    }

    private var wifiOnlyDownloadsBinding: Binding<Bool> {
        Binding(
            get: { session.settings.wifiOnlyDownloads },
            set: { session.setWifiOnlyDownloads($0) }
        )
    }

    private var downloadNotificationsBinding: Binding<Bool> {
        Binding(
            get: { session.settings.downloadNotificationsEnabled },
            set: { session.setDownloadNotificationsEnabled($0) }
        )
    }

    private var clearCookiesOnTabCloseBinding: Binding<Bool> {
        Binding(
            get: { session.settings.clearCookiesOnTabClose },
            set: { session.setClearCookiesOnTabClose($0) }
        )
    }
}
