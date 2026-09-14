import SwiftUI

struct SiteControlSheet: View {
    @EnvironmentObject private var session: BrowserSession

    var body: some View {
        List {
            Section {
                controlPicker("网络规则", keyPath: \.networkBlocking)
                controlPicker("跟踪器清理", keyPath: \.trackerBlocking)
                controlPicker("页面元素清理", keyPath: \.cosmeticCleanup)
                controlPicker("自动阅读模式", keyPath: \.autoReader)
                controlPicker("深色网页", keyPath: \.darkMode)
                controlPicker("桌面版网站", keyPath: \.desktopUserAgent)
            } header: {
                Text(URLPolicy.displayHost(session.activeTab?.url ?? ""))
            } footer: {
                Text("WebKit 使用合并的网络规则；关闭网络规则或跟踪器清理时，本站的原生规则列表会一并停用。")
            }
        }
        .navigationTitle("站点控制")
        .accessibilityIdentifier("site-control-sheet")
    }

    private func controlPicker(
        _ title: String,
        keyPath: WritableKeyPath<SiteControl, SiteControlMode>
    ) -> some View {
        Picker(title, selection: binding(keyPath)) {
            ForEach(SiteControlMode.allCases) { mode in
                Text(mode.label).tag(mode)
            }
        }
    }

    private func binding(_ keyPath: WritableKeyPath<SiteControl, SiteControlMode>) -> Binding<SiteControlMode> {
        Binding(
            get: { session.currentSiteControl()[keyPath: keyPath] },
            set: { value in
                var control = session.currentSiteControl()
                control[keyPath: keyPath] = value
                session.setCurrentSiteControl(control)
            }
        )
    }
}
