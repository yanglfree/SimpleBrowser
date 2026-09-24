import AppKit
import SwiftUI

/// Clean macOS sheet for managing Bookmarks and Browsing History.
public struct LibraryManagerView: View {
    @ObservedObject var session: BrowserSession
    @Binding var isPresented: Bool

    @State private var searchText: String = ""
    @State private var editingBookmark: BookmarkEntry?
    @State private var editTitle: String = ""
    @State private var editURL: String = ""
    @State private var isShowingClearHistoryAlert: Bool = false

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
            // Header: Tabs + Search + Done
            HStack(spacing: 12) {
                Picker("", selection: $session.librarySelectedTab) {
                    Text("书签 (\(session.bookmarks.count))").tag(0)
                    Text("历史记录 (\(session.history.count))").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 220)

                // Search field
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
                .padding(.vertical, 4)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )

                Spacer()

                if session.librarySelectedTab == 1 && !session.history.isEmpty {
                    Button("清空历史") {
                        isShowingClearHistoryAlert = true
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(.red)
                }

                Button("完成") {
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Content Area
            if session.librarySelectedTab == 0 {
                bookmarksListView
            } else {
                historyListView
            }
        }
        .frame(width: 580, height: 460)
        .sheet(item: $editingBookmark) { bookmark in
            editBookmarkSheet(for: bookmark)
        }
        .alert("确定清空全部浏览历史？", isPresented: $isShowingClearHistoryAlert) {
            Button("清空", role: .destructive) {
                session.clearHistory()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作将删除所有本地历史记录，无法撤销。")
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
            List {
                ForEach(filteredBookmarks) { bookmark in
                    HStack(spacing: 10) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.yellow)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(bookmark.displayTitle)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.primary)
                                .lineLimit(1)

                            Text(bookmark.url)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        // Action Buttons
                        HStack(spacing: 8) {
                            Button(action: {
                                editingBookmark = bookmark
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
                    .padding(.vertical, 4)
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
                            editingBookmark = bookmark
                            editTitle = bookmark.title
                            editURL = bookmark.url
                        }
                        Button("删除", role: .destructive) {
                            session.removeBookmark(id: bookmark.id)
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
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
            List {
                ForEach(filteredHistory) { entry in
                    HStack(spacing: 10) {
                        Image(systemName: "globe")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.displayTitle)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.primary)
                                .lineLimit(1)

                            Text(entry.url)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        if entry.visitCount > 1 {
                            Text("\(entry.visitCount) 次访问")
                                .font(.system(size: 10, weight: .medium))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.12))
                                .cornerRadius(4)
                                .foregroundColor(.secondary)
                        }

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
                    .padding(.vertical, 4)
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
            }
            .listStyle(.inset)
        }
    }

    // MARK: - Edit Bookmark Sheet

    private func editBookmarkSheet(for bookmark: BookmarkEntry) -> some View {
        VStack(spacing: 16) {
            Text("编辑书签")
                .font(.system(size: 14, weight: .bold))

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("名称")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    TextField("书签名称", text: $editTitle)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("网址")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    TextField("网址 URL", text: $editURL)
                        .textFieldStyle(.roundedBorder)
                }
            }

            HStack {
                Button("取消") {
                    editingBookmark = nil
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("保存") {
                    session.updateBookmark(id: bookmark.id, title: editTitle, url: editURL)
                    editingBookmark = nil
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    private func emptyStateView(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 36))
                .foregroundColor(.secondary.opacity(0.6))

            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.secondary)

            Text(subtitle)
                .font(.system(size: 12))
                .foregroundColor(.secondary.opacity(0.8))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
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
