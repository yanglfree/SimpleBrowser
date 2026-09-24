import SwiftUI

/// Minimal preferences sheet for ZhuoBrowser Mac.
public struct SettingsView: View {
    @ObservedObject var session: BrowserSession
    @Binding var isPresented: Bool

    @ObservedObject private var settings = BrowserSettings.shared

    public var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("偏好设置")
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider()

            Form {
                // Search Engine
                Section {
                    Picker("默认搜索引擎", selection: $settings.searchEngine) {
                        ForEach(SearchEngine.allCases) { engine in
                            Text(engine.rawValue).tag(engine)
                        }
                    }
                }

                // Memory Saver Budget
                Section {
                    Picker("活跃标签配额 (Live WebViews)", selection: $settings.liveWebViewBudget) {
                        Text("1 个 (极致省内存，后台立即休眠)").tag(1)
                        Text("2 个 (默认推荐，平衡切换速度与内存)").tag(2)
                        Text("3 个 (常驻 3 个活跃页面)").tag(3)
                        Text("4 个 (宽松配额)").tag(4)
                    }
                    .onChange(of: settings.liveWebViewBudget) { _ in
                        session.enforceMemoryBudget()
                    }

                    Text("当后台标签数量超过该配额时，超出部分将自动销毁 WebKit 渲染进程以释放内存，点击该标签时自动无损恢复。")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                // Privacy & Content Blocking
                Section {
                    Toggle("启用原生广告与跟踪拦截 (WKContentRuleList)", isOn: $settings.adBlockEnabled)
                    Toggle("启用页面元素去噪净化 (Cosmetic Cleanup)", isOn: $settings.cosmeticCleanupEnabled)
                }
            }

            Divider()

            HStack {
                Spacer()
                Button("完成") {
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}
