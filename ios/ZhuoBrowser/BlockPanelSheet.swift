import SwiftUI

struct BlockPanelSheet: View {
    @EnvironmentObject private var session: BrowserSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("本页可观察清理")
                                .font(.headline)
                            Text(URLPolicy.displayHost(session.activeTab?.url ?? ""))
                                .font(.caption)
                                .foregroundStyle(DesignTokens.textSecondary)
                        }
                        Spacer()
                        Text("\(pageStats.total)")
                            .font(.system(size: 34, weight: .semibold, design: .rounded))
                            .foregroundStyle(DesignTokens.accent)
                    }
                    statRow("广告元素", value: pageStats.ads, icon: "rectangle.slash")
                    statRow("跟踪器", value: pageStats.trackers, icon: "scope")
                    statRow("弹窗", value: pageStats.popups, icon: "macwindow.badge.plus")
                    statRow("Cookie 提示", value: pageStats.cookieBanners, icon: "hand.raised")
                } footer: {
                    Text("这里仅统计 WebKit 页面脚本实际清理到的元素，不包含原生网络规则在请求层拦截的数量。")
                }

                Section("当前站点") {
                    Toggle("启用本站拦截", isOn: siteBlockingBinding)
                    .tint(DesignTokens.accent)
                    NavigationLink("详细控制") {
                        SiteControlSheet()
                            .environmentObject(session)
                    }
                    HStack {
                        Text("累计可观察清理")
                        Spacer()
                        Text("\(siteStats.total)")
                            .foregroundStyle(DesignTokens.textSecondary)
                    }
                }

                if !events.isEmpty {
                    Section("本页事件") {
                        ForEach(events) { event in
                            HStack {
                                Text(event.category.label)
                                Spacer()
                                Text("×\(event.count)")
                                    .foregroundStyle(DesignTokens.textSecondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("内容拦截")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .accessibilityIdentifier("block-panel-sheet")
        }
    }

    private var pageStats: BlockStats { session.observedStatsForActiveTab() }
    private var siteStats: BlockStats { session.observedStatsForCurrentSite() }
    private var events: [BlockEvent] { session.observedEventsForActiveTab() }

    private var siteBlockingBinding: Binding<Bool> {
        Binding(
            get: { !session.isCurrentHostAllowed() },
            set: { enabled in
                if enabled == session.isCurrentHostAllowed() {
                    session.toggleCurrentHostAllowed()
                }
            }
        )
    }

    private func statRow(_ title: String, value: Int, icon: String) -> some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer()
            Text("\(value)")
                .foregroundStyle(DesignTokens.textSecondary)
        }
    }
}
