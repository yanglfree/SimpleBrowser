import SwiftUI

struct PageDisplaySettingsSheet: View {
    @EnvironmentObject private var session: BrowserSession
    @Environment(\.dismiss) private var dismiss

    private var url: String {
        session.activeTab?.url ?? ""
    }

    private var host: String {
        WebAppearancePolicy.host(for: url)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("仅本次") {
                    HStack(spacing: 12) {
                        Button("移动版") {
                            session.applyUserAgentOnce(.mobile)
                            dismiss()
                        }
                        .buttonStyle(.bordered)
                        .tint(DesignTokens.accent)
                        .frame(maxWidth: .infinity)

                        Button("桌面版") {
                            session.applyUserAgentOnce(.desktop)
                            dismiss()
                        }
                        .buttonStyle(.bordered)
                        .tint(DesignTokens.accent)
                        .frame(maxWidth: .infinity)
                    }
                    .accessibilityIdentifier("page-display-ua-once")
                }

                Section("始终用于此网站") {
                    Picker("网站版本", selection: siteUserAgentBinding) {
                        ForEach(UserAgentPreference.allCases) { preference in
                            Text(preference.label).tag(preference)
                        }
                    }
                    .accessibilityIdentifier("page-display-site-ua")

                    Picker("页面缩放", selection: siteZoomBinding) {
                        ForEach(WebAppearancePolicy.supportedZoomPercents, id: \.self) { percent in
                            Text("\(percent)%").tag(percent)
                        }
                    }
                    .accessibilityIdentifier("page-display-zoom")

                    Toggle("此网站不使用网页深色模式", isOn: darkModeExclusionBinding)
                        .tint(DesignTokens.accent)
                        .accessibilityIdentifier("page-display-dark-exclusion")
                }

                Section("所有网站") {
                    Picker("默认网站版本", selection: globalUserAgentBinding) {
                        ForEach(UserAgentPreference.allCases) { preference in
                            Text(preference.label).tag(preference)
                        }
                    }
                    .accessibilityIdentifier("page-display-global-ua")

                    Button("重置网站版本设置") {
                        session.resetUserAgentPreferences()
                    }
                    .accessibilityIdentifier("page-display-reset-ua")
                }
            }
            .scrollContentBackground(.hidden)
            .background(DesignTokens.pageBackground)
            .navigationTitle(host.isEmpty ? "网页显示" : host)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .accessibilityIdentifier("page-display-sheet")
    }

    private var siteUserAgentBinding: Binding<UserAgentPreference> {
        Binding(
            get: { session.siteUserAgentPreference(for: url) },
            set: { session.setSiteUserAgentPreference($0) }
        )
    }

    private var globalUserAgentBinding: Binding<UserAgentPreference> {
        Binding(
            get: { session.settings.defaultUserAgentPreference },
            set: { session.setDefaultUserAgentPreference($0) }
        )
    }

    private var siteZoomBinding: Binding<Int> {
        Binding(
            get: { session.zoomPercent(for: url) },
            set: { session.setCurrentSiteZoom($0) }
        )
    }

    private var darkModeExclusionBinding: Binding<Bool> {
        Binding(
            get: { session.isWebDarkModeExcluded(for: url) },
            set: { session.setCurrentSiteDarkModeExcluded($0) }
        )
    }
}
