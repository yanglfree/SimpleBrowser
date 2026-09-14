import SwiftUI

struct BlockEventSheet: View {
    let events: [BlockEvent]

    var body: some View {
        Group {
            if events.isEmpty {
                ContentUnavailableView(
                    "暂无清理事件",
                    systemImage: "checkmark.shield",
                    description: Text("打开网页并触发页面内容清理后，事件会显示在这里。")
                )
                .accessibilityIdentifier("block-events-empty")
            } else {
                List(events) { event in
                    eventRow(event)
                }
                .listStyle(.plain)
                .safeAreaInset(edge: .bottom) {
                    Text("仅列出 WebKit 页面脚本实际观察到的清理；原生网络规则不会向应用回传请求级命中详情。")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(.regularMaterial)
                }
            }
        }
        .background(DesignTokens.pageBackground)
        .navigationTitle("清理事件")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("block-event-sheet")
    }

    private func eventRow(_ event: BlockEvent) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(event.category.label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DesignTokens.accent)
                Text("WebKit 页面清理")
                    .font(.system(size: 12))
                    .foregroundStyle(DesignTokens.textSecondary)
                Spacer()
                Text(event.occurredAt, style: .time)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(DesignTokens.textSecondary)
            }
            Text(eventHost(event))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(DesignTokens.textPrimary)
                .lineLimit(1)
            Text("已清理 \(event.count) 个页面元素")
                .font(.system(size: 12))
                .foregroundStyle(DesignTokens.textSecondary)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("block-event-\(event.id)")
    }

    private func eventHost(_ event: BlockEvent) -> String {
        let host = URLPolicy.displayHost(event.pageURL)
        return host.isEmpty ? "当前页面" : host
    }
}
