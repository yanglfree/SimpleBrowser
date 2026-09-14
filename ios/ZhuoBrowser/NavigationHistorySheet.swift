import SwiftUI

struct NavigationHistorySheet: View {
    @EnvironmentObject private var session: BrowserSession

    var body: some View {
        NavigationStack {
            List {
                historySection(title: "返回", direction: .back)
                historySection(title: "前进", direction: .forward)
            }
            .overlay {
                if session.navigationHistoryEntries.isEmpty {
                    ContentUnavailableView("暂无导航历史", systemImage: "clock.arrow.circlepath")
                }
            }
            .navigationTitle("导航历史")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { session.showsNavigationHistory = false }
                        .accessibilityIdentifier("navigation-history-done")
                }
            }
        }
    }

    @ViewBuilder
    private func historySection(title: String, direction: NavigationHistoryDirection) -> some View {
        let entries = session.navigationHistoryEntries.filter { $0.direction == direction }
        if !entries.isEmpty {
            Section(title) {
                ForEach(entries) { entry in
                    Button {
                        session.navigateHistory(to: entry.offset)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.title)
                                .foregroundStyle(DesignTokens.textPrimary)
                                .lineLimit(1)
                            Text(entry.url)
                                .font(.caption)
                                .foregroundStyle(DesignTokens.textSecondary)
                                .lineLimit(1)
                        }
                    }
                    .accessibilityIdentifier("navigation-history-\(entry.direction.rawValue)-\(abs(entry.offset))")
                }
            }
        }
    }
}
