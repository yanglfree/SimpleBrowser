import QuickLook
import SwiftUI

private struct DownloadPreview: Identifiable {
    let url: URL
    var id: String { url.path }
}

struct DownloadSheet: View {
    @EnvironmentObject private var session: BrowserSession
    @Environment(\.dismiss) private var dismiss
    @State private var shareItems: [Any] = []
    @State private var showsShare = false
    @State private var preview: DownloadPreview?

    var body: some View {
        NavigationStack {
            Group {
                if session.downloads.tasks.isEmpty {
                    ContentUnavailableView("暂无下载", systemImage: "arrow.down.circle")
                } else {
                    List(session.downloads.tasks) { task in
                        DownloadTaskRow(
                            task: task,
                            onPause: { session.downloads.pause(task.id) },
                            onResume: { session.downloads.resume(task.id) },
                            onRetry: { session.retryDownload(task.id) },
                            onCancel: { session.downloads.cancel(task.id) },
                            onOpen: { open(task) },
                            onShare: { share(task) }
                        )
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("删除记录", role: .destructive) {
                                session.downloads.remove(task.id, deleteFile: false)
                            }
                            if task.status == .completed {
                                Button("删除文件", role: .destructive) {
                                    session.downloads.remove(task.id, deleteFile: true)
                                }
                            }
                        }
                        .contextMenu {
                            if task.status == .completed {
                                Button("打开") { open(task) }
                                Button("分享") { share(task) }
                                Button("删除文件", role: .destructive) {
                                    session.downloads.remove(task.id, deleteFile: true)
                                }
                            }
                            Button("删除记录", role: .destructive) {
                                session.downloads.remove(task.id, deleteFile: false)
                            }
                        }
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
        .sheet(item: $preview) { item in
            QuickLookPreview(url: item.url)
        }
        .accessibilityIdentifier("download-sheet")
    }

    private func open(_ task: DownloadTask) {
        guard let file = session.downloads.fileURL(for: task) else { return }
        preview = DownloadPreview(url: file)
    }

    private func share(_ task: DownloadTask) {
        guard let file = session.downloads.fileURL(for: task) else { return }
        shareItems = [file]
        showsShare = true
    }
}

private struct DownloadTaskRow: View {
    let task: DownloadTask
    let onPause: () -> Void
    let onResume: () -> Void
    let onRetry: () -> Void
    let onCancel: () -> Void
    let onOpen: () -> Void
    let onShare: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(task.fileName)
                    .foregroundStyle(DesignTokens.textPrimary)
                    .lineLimit(1)
                Spacer()
                Text(statusLabel)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(statusColor)
            }

            ProgressView(value: progress)
                .tint(DesignTokens.accent)
                .accessibilityIdentifier("download-progress-\(task.id)")

            HStack(spacing: 14) {
                Text(progressLabel)
                    .font(.system(size: 12))
                    .foregroundStyle(DesignTokens.textSecondary)
                Spacer()
                actionButtons
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var actionButtons: some View {
        switch task.status {
        case .downloading:
            action("暂停", action: onPause)
            action("取消", role: .destructive, action: onCancel)
        case .pending:
            action("取消", role: .destructive, action: onCancel)
        case .paused:
            action("继续", action: onResume)
            action("取消", role: .destructive, action: onCancel)
        case .failed, .canceled:
            action("重试", action: onRetry)
        case .completed:
            action("打开", action: onOpen)
            action("分享", action: onShare)
        }
    }

    private func action(_ title: String, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        Button(title, role: role, action: action)
            .font(.system(size: 12, weight: .medium))
            .buttonStyle(.borderless)
            .accessibilityIdentifier("download-\(title)-\(task.id)")
    }

    private var progress: Double {
        min(1, max(0, task.progress))
    }

    private var statusLabel: String {
        switch task.status {
        case .pending: return "等待中"
        case .downloading: return "下载中"
        case .paused: return "已暂停"
        case .completed: return "已完成"
        case .failed: return "失败"
        case .canceled: return "已取消"
        }
    }

    private var statusColor: Color {
        task.status == .failed ? DesignTokens.textSecondary : DesignTokens.accent
    }

    private var progressLabel: String {
        if task.status == .completed { return "下载完成" }
        if task.status == .failed { return errorLabel }
        if task.totalBytes > 0 {
            return "\(byteLabel(task.receivedBytes)) / \(byteLabel(task.totalBytes)) · \(Int(progress * 100))%"
        }
        return task.status == .pending ? "等待下载" : "大小未知"
    }

    private var errorLabel: String {
        switch task.error {
        case "missing": return "文件已被移动或删除"
        case "interrupted": return "上次下载被中断"
        case "resume_unavailable": return "当前网页不可用，请打开任意网页后重试"
        default: return task.error.isEmpty ? "下载失败" : task.error
        }
    }

    private func byteLabel(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(0, bytes), countStyle: .file)
    }
}

private struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}
