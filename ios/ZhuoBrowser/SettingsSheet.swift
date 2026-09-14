import SwiftUI

struct SettingsSheet: View {
    @EnvironmentObject private var session: BrowserSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("外观") {
                    Picker("应用外观", selection: appearanceBinding) {
                        ForEach(AppearanceMode.allCases) { appearance in
                            Text(appearance.label).tag(appearance)
                        }
                    }
                    .accessibilityIdentifier("settings-appearance")
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

                Section("书签与历史") {
                    Button("书签与历史") {
                        session.showsSettings = false
                        DispatchQueue.main.async {
                            session.openLibrary(.bookmarks)
                        }
                    }
                    .accessibilityIdentifier("settings-library")
                }

                Section("下载") {
                    Button("下载内容") {
                        session.showsSettings = false
                        DispatchQueue.main.async {
                            session.showsDownloads = true
                        }
                    }
                    .accessibilityIdentifier("settings-downloads")
                }

                Section("隐私") {
                    Button("清除浏览数据", role: .destructive) {
                        session.clearBrowsingData()
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
        .accessibilityIdentifier("settings-sheet")
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

    private var appearanceBinding: Binding<AppearanceMode> {
        Binding(
            get: { session.settings.appearance },
            set: { session.setAppearance($0) }
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
}
