import AppKit
import SwiftUI

/// Safari-style popover for managing Bookmarks and Browsing History anchored beneath the toolbar button.
public struct LibraryManagerView: View {
    @ObservedObject var session: BrowserSession
    @Binding var isPresented: Bool

    @State private var searchText: String = ""
    @State private var editingBookmarkID: String?
    @State private var editTitle: String = ""
    @State private var editURL: String = ""
    @State private var isShowingClearHistoryConfirm: Bool = false

    private var filteredBookmarks: [BookmarkEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty { return session.bookmarks }
        return session.bookmarks.filter {
            $0.title.lowercased().contains(query) || $0.url.lowercased().contains(query)
        }
    }

    private var filteredHistory: [HistoryEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty { return session.history }
        return session.history.filter {
            $0.title.lowercased().contains(query) || $0.url.lowercased().contains(query)
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Top Header: Segmented Picker + Clear Action
            VStack(spacing: 10) {
                ZStack {
                    Picker("", selection: $session.librarySelectedTab) {
                        Text("书签 (\(session.bookmarks.count))").tag(0)
                        Text("历史记录 (\(session.history.count))").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 220)

                    HStack {
                        Spacer()
                        if session.librarySelectedTab == 1 && !session.history.isEmpty {
                            if isShowingClearHistoryConfirm {
                                HStack(spacing: 6) {
                                    Button("确定清空") {
                                        session.clearHistory()
                                        isShowingClearHistoryConfirm = false
                                    }
                                    .buttonStyle(.plain)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.red)

                                    Button("取消") {
                                        isShowingClearHistoryConfirm = false
                                    }
                                    .buttonStyle(.plain)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                }
                            } else {
                                Button(action: {
                                    isShowingClearHistoryConfirm = true
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
                                .help("清空浏览历史")
                            }
                        }
                    }
                }

                // Search bar
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    TextField("在书签与历史中搜索...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))

                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)

            Divider()

            // Content Area
            if session.librarySelectedTab == 0 {
                bookmarksListView
            } else {
                historyListView
            }
        }
        .frame(width: 400, height: 460)
        .onChange(of: session.librarySelectedTab) { _ in
            isShowingClearHistoryConfirm = false
            editingBookmarkID = nil
        }
    }

    // MARK: - Bookmarks List

    @ViewBuilder
    private var bookmarksListView: some View {
        if filteredBookmarks.isEmpty {
            emptyStateView(
                icon: "star",
                title: searchText.isEmpty ? "暂无书签" : "未找到匹配书签",
                subtitle: searchText.isEmpty ? "在浏览网页时按 Cmd+D 或点击地址栏星标即可添加到书签" : "尝试更换搜索关键词"
            )
        } else {
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(filteredBookmarks.enumerated()), id: \.element.id) { index, bookmark in
                        if editingBookmarkID == bookmark.id {
                            inlineEditBookmarkView(for: bookmark)
                        } else {
                            bookmarkRow(bookmark)
                        }

                        if index < filteredBookmarks.count - 1 {
                            Divider()
                                .padding(.leading, 42)
                                .padding(.trailing, 14)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func bookmarkRow(_ bookmark: BookmarkEntry) -> some View {
        HStack(spacing: 10) {
            if let siteIcon = session.siteIcon(for: bookmark.url) {
                SiteIconThumbnail(image: siteIcon, size: 16)
            } else {
                Image(systemName: "star.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.yellow)
                    .frame(width: 16, height: 16)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(bookmark.displayTitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text(bookmark.url)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                Button(action: {
                    editingBookmarkID = bookmark.id
                    editTitle = bookmark.title
                    editURL = bookmark.url
                }) {
                    Image(systemName: "pencil")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("编辑书签")

                Button(action: {
                    session.removeBookmark(id: bookmark.id)
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("删除书签")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            session.navigate(to: bookmark.url)
            isPresented = false
        }
        .contextMenu {
            Button("在当前标签打开") {
                session.navigate(to: bookmark.url)
                isPresented = false
            }
            Button("在新标签页打开") {
                session.createTab(url: bookmark.url, select: true)
                isPresented = false
            }
            Divider()
            Button("拷贝链接") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(bookmark.url, forType: .string)
            }
            Button("编辑...") {
                editingBookmarkID = bookmark.id
                editTitle = bookmark.title
                editURL = bookmark.url
            }
            Button("删除", role: .destructive) {
                session.removeBookmark(id: bookmark.id)
            }
        }
    }

    private func inlineEditBookmarkView(for bookmark: BookmarkEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("书签名称", text: $editTitle)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))

            TextField("网址 URL", text: $editURL)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))

            HStack {
                Spacer()
                Button("取消") {
                    editingBookmarkID = nil
                }
                .controlSize(.small)

                Button("保存") {
                    session.updateBookmark(id: bookmark.id, title: editTitle, url: editURL)
                    editingBookmarkID = nil
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.secondary.opacity(0.08))
    }

    // MARK: - History List

    @ViewBuilder
    private var historyListView: some View {
        if filteredHistory.isEmpty {
            emptyStateView(
                icon: "clock.arrow.circlepath",
                title: searchText.isEmpty ? "暂无浏览历史" : "未找到匹配历史记录",
                subtitle: searchText.isEmpty ? "正常浏览的网页会自动在此按时间倒序记录" : "尝试更换搜索关键词"
            )
        } else {
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(filteredHistory.enumerated()), id: \.element.id) { index, entry in
                        historyRow(entry)

                        if index < filteredHistory.count - 1 {
                            Divider()
                                .padding(.leading, 42)
                                .padding(.trailing, 14)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func historyRow(_ entry: HistoryEntry) -> some View {
        HStack(spacing: 10) {
            if let siteIcon = session.siteIcon(for: entry.url) {
                SiteIconThumbnail(image: siteIcon, size: 16)
            } else {
                Image(systemName: "globe")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .frame(width: 16, height: 16)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayTitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text(entry.url)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            Text(formattedTime(entry.visitedAt))
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            Button(action: {
                session.removeHistoryItem(id: entry.id)
            }) {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("删除此记录")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            session.navigate(to: entry.url)
            isPresented = false
        }
        .contextMenu {
            Button("在当前标签打开") {
                session.navigate(to: entry.url)
                isPresented = false
            }
            Button("在新标签页打开") {
                session.createTab(url: entry.url, select: true)
                isPresented = false
            }
            Divider()
            Button("拷贝链接") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.url, forType: .string)
            }
            Button("删除此记录", role: .destructive) {
                session.removeHistoryItem(id: entry.id)
            }
        }
    }

    private func emptyStateView(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundColor(.secondary.opacity(0.6))

            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.secondary)

            Text(subtitle)
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.8))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func formattedTime(_ timestamp: TimeInterval) -> String {
        let date = Date(timeIntervalSince1970: timestamp)
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return "昨天"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MM-dd"
            return formatter.string(from: date)
        }
    }
}
