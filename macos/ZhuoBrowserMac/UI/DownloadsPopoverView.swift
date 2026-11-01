import AppKit
import SwiftUI

/// Safari-style popover anchored beneath the top-right toolbar Downloads button.
public struct DownloadsPopoverView: View {
    @ObservedObject var downloadManager: DownloadManager
    @ObservedObject var session: BrowserSession

    private var listHeight: CGFloat {
        if downloadManager.items.isEmpty {
            return 160
        }
        let rowHeight: CGFloat = 54
        return min(max(CGFloat(downloadManager.items.count) * rowHeight + 8, 120), 420)
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Safari-style Header: Centered "下载" + Right "清除" pill button
            ZStack {
                Text("下载")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)

                HStack {
                    Spacer()
                    if downloadManager.hasClearableItems {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                downloadManager.clearCompletedDownloads()
                            }
                        }) {
                            Text("清除")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.primary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 3.5)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(Color.secondary.opacity(0.16))
                                )
                        }
                        .buttonStyle(.plain)
                        .help("清除已完成的下载记录")
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            if downloadManager.items.isEmpty {
                emptyStateView
                    .frame(height: listHeight)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(downloadManager.items.enumerated()), id: \.element.id) { index, item in
                            DownloadItemRowView(
                                item: item,
                                downloadManager: downloadManager,
                                session: session
                            )

                            if index < downloadManager.items.count - 1 {
                                Divider()
                                    .padding(.leading, 58)
                                    .padding(.trailing, 14)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(height: listHeight)
            }
        }
        .frame(width: 336)
    }

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 30))
                .foregroundColor(.secondary.opacity(0.5))
            Text("暂无下载记录")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

private struct DownloadItemRowView: View {
    let item: DownloadItem
    @ObservedObject var downloadManager: DownloadManager
    @ObservedObject var session: BrowserSession
    @State private var isHovered: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: downloadManager.icon(for: item))
                .resizable()
                .scaledToFit()
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.filename)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if item.state == .downloading {
                    ProgressView(value: item.progress ?? 0.08, total: 1.0)
                        .progressViewStyle(.linear)
                        .controlSize(.small)
                        .tint(.accentColor)
                }

                Text(subtitleText)
                    .font(.system(size: 11))
                    .foregroundColor(item.state == .failed ? .orange : .secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            trailingActionButton
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isHovered ? Color.secondary.opacity(0.08) : Color.clear)
                .padding(.horizontal, 6)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture(count: 2) {
            if item.state == .completed {
                downloadManager.openDownloadedFile(item)
            }
        }
        .contextMenu {
            if item.state == .completed {
                Button("打开") {
                    downloadManager.openDownloadedFile(item)
                }
                .disabled(!item.fileExistsOnDisk)

                Button("在访达中显示") {
                    downloadManager.revealInFinder(item)
                }
                Divider()
            } else if item.state == .downloading {
                Button("取消下载") {
                    downloadManager.cancelDownload(id: item.id)
                }
                Divider()
            } else {
                Button("重新下载") {
                    downloadManager.retryDownload(id: item.id, in: session.activeController?.webView)
                }
                Divider()
            }

            if !item.sourceURL.isEmpty {
                Button("拷贝下载链接") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item.sourceURL, forType: .string)
                }
            }

            Button("从列表中移除", role: .destructive) {
                downloadManager.removeDownload(id: item.id)
            }
        }
    }

    private var subtitleText: String {
        if item.state == .completed && !item.destinationPath.isEmpty && !item.fileExistsOnDisk {
            return "\(item.statusText) · 已从磁盘移除"
        }
        return item.statusText
    }

    @ViewBuilder
    private var trailingActionButton: some View {
        switch item.state {
        case .downloading:
            Button(action: {
                downloadManager.cancelDownload(id: item.id)
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundColor(.secondary.opacity(0.75))
            }
            .buttonStyle(.plain)
            .help("取消下载")

        case .completed:
            Button(action: {
                downloadManager.revealInFinder(item)
            }) {
                Image(systemName: "magnifyingglass.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary.opacity(0.75))
            }
            .buttonStyle(.plain)
            .help("在访达中显示")

        case .failed, .cancelled:
            Button(action: {
                downloadManager.retryDownload(id: item.id, in: session.activeController?.webView)
            }) {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary.opacity(0.75))
            }
            .buttonStyle(.plain)
            .help("重新下载")
        }
    }
}
