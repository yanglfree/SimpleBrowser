import SwiftUI

/// Visual indicator showing live webviews vs hibernated tabs.
public struct MemorySaverBadge: View {
    @ObservedObject var session: BrowserSession
    @State private var isShowingPopover: Bool = false

    private var totalTabs: Int {
        session.tabs.count
    }

    private var hibernatedTabs: Int {
        session.tabs.filter(\.isHibernated).count
    }

    private var activeTabs: Int {
        session.activeLiveControllersCount
    }

    public var body: some View {
        Button(action: {
            isShowingPopover.toggle()
        }) {
            HStack(spacing: 5) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 7, height: 7)

                Image(systemName: "leaf.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.green)

                Text("\(activeTabs)/\(totalTabs)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .help("内存卫士状态：点击查看标签休眠与内存优化详情")
        .popover(isPresented: $isShowingPopover) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "bolt.shield.fill")
                        .foregroundColor(.green)
                    Text("内存卫士 (Memory Saver)")
                        .font(.system(size: 13, weight: .bold))
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("当前总标签数:")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(totalTabs)")
                            .fontWeight(.semibold)
                    }

                    HStack {
                        Text("活跃 WebKit 进程:")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(activeTabs)")
                            .foregroundColor(.green)
                            .fontWeight(.semibold)
                    }

                    HStack {
                        Text("已休眠冻结标签:")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(hibernatedTabs)")
                            .foregroundColor(.blue)
                            .fontWeight(.semibold)
                    }

                    HStack {
                        Text("活跃进程配额:")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(session.settings.liveWebViewBudget)")
                            .fontWeight(.semibold)
                    }
                }
                .font(.system(size: 12))

                Divider()

                Text("超出配额的后台标签会自动释放 WKWebView 实例及底层 WebContent 渲染进程，保留滚动和浏览状态，为您节省 70%~90% 的内存占用。")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(width: 260)
        }
    }
}
