import SwiftUI

/// Status indicator for the tab residency mode plus live diagnostics.
///
/// After the tab-switching fix the default is "everything resident": the badge shows
/// how many pages are resident, and the popover exposes reuse/rebuild counters so the
/// "no reload on switch" contract is verifiable at a glance.
public struct MemorySaverBadge: View {
    @ObservedObject var session: BrowserSession
    @ObservedObject private var settings = BrowserSettings.shared
    @State private var isShowingPopover: Bool = false

    private var totalTabs: Int {
        session.tabs.count
    }

    private var frozenTabs: Int {
        session.frozenTabCount
    }

    private var liveTabs: Int {
        session.activeLiveControllersCount
    }

    private var isResidentMode: Bool {
        !settings.tabHibernationEnabled
    }

    private var statusColor: Color {
        if !isResidentMode { return .blue }
        switch session.memoryPressure {
        case .nominal: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }

    private var modeIcon: String {
        isResidentMode ? "square.stack.3d.up.fill" : "leaf.fill"
    }

    private var modeTitle: String {
        isResidentMode ? "全部常驻" : "省内存"
    }

    public var body: some View {
        Button(action: {
            isShowingPopover.toggle()
        }) {
            HStack(spacing: 5) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)

                Image(systemName: modeIcon)
                    .font(.system(size: 10))
                    .foregroundColor(statusColor)

                Text("\(liveTabs)/\(totalTabs)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .help("标签驻留状态：\(modeTitle)，点击查看切换诊断")
        .popover(isPresented: $isShowingPopover) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: modeIcon)
                        .foregroundColor(statusColor)
                    Text("标签驻留与切换诊断")
                        .font(.system(size: 13, weight: .bold))
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    row(label: "当前模式", value: modeTitle, color: statusColor)
                    row(label: "总标签数", value: "\(totalTabs)", color: .primary)
                    row(label: "常驻渲染进程", value: "\(liveTabs)", color: .green)
                    row(label: "已冻结", value: "\(frozenTabs)", color: frozenTabs > 0 ? .purple : .secondary)
                    row(label: "系统内存压力", value: session.memoryPressure.displayName, color: statusColor)
                }
                .font(.system(size: 12))

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    row(label: "切换复用页面", value: "\(session.liveReuseCount) 次", color: .green)
                    row(
                        label: "页面重建",
                        value: "\(session.pageRebuildCount) 次",
                        color: session.pageRebuildCount > 0 ? .orange : .secondary
                    )
                }
                .font(.system(size: 12))

                Divider()

                Text(isResidentMode
                     ? "全部标签常驻：切换标签仅重新挂载已有页面，不发起任何加载。每个标签约占 80–250MB 内存，这是换取瞬时切换的代价。"
                     : "省内存模式：超出上限的后台标签会被冻结，切回时需要重建页面。可在「偏好设置 → 标签切换与内存」中关闭。")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(width: 285)
        }
    }

    private func row(label: String, value: String, color: Color) -> some View {
        HStack {
            Text("\(label):")
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .foregroundColor(color)
                .fontWeight(.semibold)
        }
    }
}
