import SwiftUI

struct DownloadSheet: View {
    @EnvironmentObject private var session: BrowserSession
    @Environment(\.dismiss) private var dismiss
    @State private var shareItems: [Any] = []
    @State private var showsShare = false

    var body: some View {
        NavigationStack {
            Group {
                if session.downloads.tasks.isEmpty {
                    Text("暂无下载")
                        .font(.system(size: 15))
                        .foregroundStyle(DesignTokens.textSecondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(session.downloads.tasks) { task in
                        Button {
                            if let file = session.downloads.fileURL(for: task) {
                                shareItems = [file]
                                showsShare = true
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(task.fileName)
                                    .foregroundStyle(DesignTokens.textPrimary)
                                    .lineLimit(1)
                                Text(statusText(task))
                                    .font(.system(size: 12))
                                    .foregroundStyle(DesignTokens.textSecondary)
                            }
                        }
                        .disabled(task.status != .completed)
                        .accessibilityIdentifier("download-row-\(task.id)")
                    }
                    .listStyle(.plain)
                }
            }
            .background(DesignTokens.pageBackground)
            .navigationTitle("下载")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                        .accessibilityIdentifier("downloads-done")
                }
            }
        }
        .sheet(isPresented: $showsShare) {
            ShareSheet(items: shareItems)
        }
        .accessibilityIdentifier("download-sheet")
    }

    private func statusText(_ task: DownloadTask) -> String {
        switch task.status {
        case .downloading: return "下载中"
        case .completed: return "已完成，点按分享或打开"
        case .failed: return task.error.isEmpty ? "失败" : task.error
        }
    }
}
