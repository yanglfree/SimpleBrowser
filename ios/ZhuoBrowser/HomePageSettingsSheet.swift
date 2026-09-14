import SwiftUI

struct HomePageSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: BrowserSession
    let onOpenBackgroundPicker: () -> Void
    let onOpenSettings: (SettingsSection?) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("起始页") {
                    Toggle("显示快捷站点", isOn: quickSitesEnabledBinding)
                        .tint(DesignTokens.accent)
                        .accessibilityIdentifier("home-settings-quick-sites")
                    Stepper(
                        value: quickSiteLimitBinding,
                        in: 4...8,
                        step: 2
                    ) {
                        Text("快捷站点数量：\(session.settings.quickSiteLimit)")
                    }
                    .disabled(!session.settings.quickSitesEnabled)
                    .accessibilityIdentifier("home-settings-quick-site-limit")
                    Toggle("显示首页背景", isOn: homeBackgroundEnabledBinding)
                        .tint(DesignTokens.accent)
                        .accessibilityIdentifier("home-settings-background-enabled")
                    Button {
                        route(to: onOpenBackgroundPicker)
                    } label: {
                        HStack {
                            Text("选择首页背景")
                            Spacer()
                            Text(backgroundLabel)
                                .foregroundStyle(DesignTokens.textSecondary)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(DesignTokens.textSecondary)
                        }
                    }
                    .accessibilityIdentifier("home-settings-background-picker")
                }

                Section("外观与设置") {
                    Button {
                        route { onOpenSettings(.appearance) }
                    } label: {
                        HStack {
                            Text("页面主题")
                            Spacer()
                            Text(session.settings.appearance.label)
                                .foregroundStyle(DesignTokens.textSecondary)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(DesignTokens.textSecondary)
                        }
                    }
                    .accessibilityIdentifier("home-settings-appearance")
                    Button("更多设置") {
                        route { onOpenSettings(nil) }
                    }
                    .accessibilityIdentifier("home-settings-more")
                }
            }
            .scrollContentBackground(.hidden)
            .background(DesignTokens.pageBackground)
            .navigationTitle("页面设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .accessibilityIdentifier("home-page-settings")
    }

    private var backgroundLabel: String {
        session.settings.homeBackgroundEnabled
            ? session.settings.homeBackgroundStyle.label
            : "关闭"
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

    private var homeBackgroundEnabledBinding: Binding<Bool> {
        Binding(
            get: { session.settings.homeBackgroundEnabled },
            set: { session.setHomeBackgroundEnabled($0) }
        )
    }

    private func route(to action: @escaping () -> Void) {
        dismiss()
        DispatchQueue.main.async(execute: action)
    }
}
