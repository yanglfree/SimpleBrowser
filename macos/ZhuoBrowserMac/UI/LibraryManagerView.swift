import AppKit
import SwiftUI

/// Filter state inside the Library Popover's Bookmarks tab.
private enum PopoverBookmarkFilter: Equatable {
    case all
    case ungrouped
    case folder(String)
}

/// Safari-style popover for managing Bookmarks (with folders, inline edit, move to folder, and full manager entry)
/// and Browsing History anchored beneath the toolbar button.
public struct LibraryManagerView: View {
    @ObservedObject var session: BrowserSession
    @Binding var isPresented: Bool

    @State private var searchText: String = ""
    @State private var bookmarkFilter: PopoverBookmarkFilter = .all
    @State private var collapsedFolderIDs: Set<String> = []

    // Inline bookmark editing
    @State private var editingBookmarkID: String?
    @State private var editTitle: String = ""
    @State private var editURL: String = ""
    @State private var editFolderID: String? = nil
    @State private var editPinToStartPage: Bool = false

    // Inline bookmark adding
    @State private var isAddingBookmark: Bool = false
    @State private var newBookmarkTitle: String = ""
    @State private var newBookmarkURL: String = ""
    @State private var newBookmarkFolderID: String? = nil

    // Inline folder creation & renaming
    @State private var isCreatingFolder: Bool = false
    @State private var newFolderName: String = ""
    @State private var renamingFolderID: String?
    @State private var renameFolderText: String = ""

    @State private var isShowingClearHistoryConfirm: Bool = false

    private var activeFilterFolderID: String? {
        if case .folder(let fid) = bookmarkFilter {
            return fid
        }
        return nil
    }

    private var filteredBookmarks: [BookmarkEntry] {
        let base: [BookmarkEntry]
        switch bookmarkFilter {
        case .all:
            base = session.bookmarks
        case .ungrouped:
            base = session.ungroupedBookmarks
        case .folder(let folderID):
            base = session.bookmarks(inFolder: folderID)
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty { return base }
        return base.filter { item in
            let folderName = session.folderName(for: item.folderID).lowercased()
            return item.title.lowercased().contains(query)
                || item.url.lowercased().contains(query)
                || folderName.contains(query)
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
            // Top Header: Segmented Picker + Contextual Actions
            VStack(spacing: 9) {
                HStack(spacing: 8) {
                    Picker("", selection: $session.librarySelectedTab) {
                        Text("书签 (\(session.bookmarks.count))").tag(0)
                        Text("历史记录 (\(session.history.count))").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 210)

                    Spacer()

                    if session.librarySelectedTab == 0 {
                        bookmarksHeaderActions
                    } else if !session.history.isEmpty {
                        historyHeaderActions
                    }
                }

                // Search bar
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    TextField(
                        session.librarySelectedTab == 0 ? "搜索书签名称、网址或分组..." : "在浏览历史中搜索...",
                        text: $searchText
                    )
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

                // Folder Filter Pills (when on Bookmarks tab)
                if session.librarySelectedTab == 0 {
                    folderFilterBar
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)

            Divider()

            // Inline Folder Creation Bar
            if session.librarySelectedTab == 0 && isCreatingFolder {
                inlineCreateFolderBar
                Divider()
            }

            // Inline Folder Rename Bar
            if session.librarySelectedTab == 0, let fid = renamingFolderID, let folder = session.folder(forID: fid) {
                inlineRenameFolderBar(for: folder)
                Divider()
            }

            // Inline Add Bookmark Form
            if session.librarySelectedTab == 0 && isAddingBookmark {
                inlineAddBookmarkBar
                Divider()
            }

            // Content Area
            if session.librarySelectedTab == 0 {
                bookmarksListView
            } else {
                historyListView
            }
        }
        .frame(width: 430, height: 520)
        .onChange(of: session.librarySelectedTab) { _ in
            isShowingClearHistoryConfirm = false
            editingBookmarkID = nil
            isAddingBookmark = false
            isCreatingFolder = false
            renamingFolderID = nil
        }
    }

    // MARK: - Header Actions

    private var bookmarksHeaderActions: some View {
        HStack(spacing: 6) {
            Button(action: {
                isCreatingFolder.toggle()
                isAddingBookmark = false
                newFolderName = ""
            }) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 12))
                    .foregroundColor(isCreatingFolder ? .accentColor : .primary)
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isCreatingFolder ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.12))
                    )
            }
            .buttonStyle(.plain)
            .help("新建书签分组")

            Button(action: {
                if isAddingBookmark {
                    isAddingBookmark = false
                } else {
                    openInlineAddBookmark(defaultFolderID: activeFilterFolderID)
                }
            }) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isAddingBookmark ? .accentColor : .primary)
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isAddingBookmark ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.12))
                    )
            }
            .buttonStyle(.plain)
            .help("添加新书签")

            Button(action: {
                session.openBookmarkManager(selectingFolderID: activeFilterFolderID)
            }) {
                HStack(spacing: 3) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 10.5))
                    Text("管理")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(.accentColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                )
            }
            .buttonStyle(.plain)
            .help("打开完整书签管理器 (支持批量管理、排序与导入导出)")
        }
    }

    @ViewBuilder
    private var historyHeaderActions: some View {
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

    // MARK: - Folder Filter Bar

    private var folderFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                filterChip(
                    title: "全部 (\(session.bookmarks.count))",
                    icon: "books.vertical.fill",
                    isSelected: bookmarkFilter == .all
                ) {
                    bookmarkFilter = .all
                }

                filterChip(
                    title: "未分组 (\(session.ungroupedBookmarks.count))",
                    icon: "tray.fill",
                    isSelected: bookmarkFilter == .ungrouped
                ) {
                    bookmarkFilter = .ungrouped
                }

                ForEach(session.bookmarkFolders) { folder in
                    let count = session.bookmarks(inFolder: folder.id).count
                    filterChip(
                        title: "\(folder.name) (\(count))",
                        icon: "folder.fill",
                        isSelected: bookmarkFilter == .folder(folder.id)
                    ) {
                        bookmarkFilter = .folder(folder.id)
                    }
                    .contextMenu {
                        Button("在此分组添加书签...") {
                            bookmarkFilter = .folder(folder.id)
                            openInlineAddBookmark(defaultFolderID: folder.id)
                        }
                        Button("在新标签页中打开全部 (\(count))") {
                            session.openAllBookmarks(inFolder: folder.id)
                            isPresented = false
                        }
                        .disabled(count == 0)

                        Divider()

                        Button("重命名分组...") {
                            renamingFolderID = folder.id
                            renameFolderText = folder.name
                        }

                        Button("在书签管理器中查看...") {
                            session.openBookmarkManager(selectingFolderID: folder.id)
                        }

                        Divider()

                        Button("删除分组（保留书签至未分组）", role: .destructive) {
                            if bookmarkFilter == .folder(folder.id) {
                                bookmarkFilter = .all
                            }
                            session.removeBookmarkFolder(id: folder.id, deleteContainedBookmarks: false)
                        }

                        Button("删除分组及组内所有书签", role: .destructive) {
                            if bookmarkFilter == .folder(folder.id) {
                                bookmarkFilter = .all
                            }
                            session.removeBookmarkFolder(id: folder.id, deleteContainedBookmarks: true)
                        }
                    }
                }
            }
            .padding(.vertical, 1)
        }
    }

    private func filterChip(
        title: String,
        icon: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(title)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
            }
            .foregroundColor(isSelected ? .white : .primary)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Inline Create / Rename Folder & Add Bookmark Bars

    private var inlineCreateFolderBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder.badge.plus")
                .foregroundColor(.accentColor)
                .font(.system(size: 12))

            TextField("输入新分组名称...", text: $newFolderName)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .onSubmit {
                    commitCreateFolder()
                }

            Button("取消") {
                isCreatingFolder = false
                newFolderName = ""
            }
            .controlSize(.small)

            Button("创建") {
                commitCreateFolder()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.06))
    }

    private func inlineRenameFolderBar(for folder: BookmarkFolder) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "pencil")
                .foregroundColor(.accentColor)
                .font(.system(size: 12))

            TextField("重命名分组", text: $renameFolderText)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .onSubmit {
                    session.renameBookmarkFolder(id: folder.id, newName: renameFolderText)
                    renamingFolderID = nil
                }

            Button("取消") {
                renamingFolderID = nil
            }
            .controlSize(.small)

            Button("保存") {
                session.renameBookmarkFolder(id: folder.id, newName: renameFolderText)
                renamingFolderID = nil
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(renameFolderText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.06))
    }

    private var inlineAddBookmarkBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("添加新书签")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(.accentColor)
                Spacer()
                if let tab = session.activeTab, !tab.isHome, !tab.url.isEmpty {
                    Button("使用当前页") {
                        newBookmarkTitle = tab.displayTitle
                        newBookmarkURL = tab.url
                    }
                    .font(.system(size: 10.5))
                    .controlSize(.mini)
                }
            }

            TextField("书签名称", text: $newBookmarkTitle)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))

            TextField("网址 URL (如 https://example.com)", text: $newBookmarkURL)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))

            HStack(spacing: 8) {
                Text("分组:")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Picker("", selection: $newBookmarkFolderID) {
                    Text("未分组 (主页)").tag(String?.none)
                    Divider()
                    ForEach(session.bookmarkFolders) { folder in
                        Text("📁 \(folder.name)").tag(String?.some(folder.id))
                    }
                }
                .labelsHidden()
                .frame(width: 145)

                Spacer()

                Button("取消") {
                    isAddingBookmark = false
                }
                .controlSize(.small)

                Button("添加") {
                    let cleanURL = newBookmarkURL.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !cleanURL.isEmpty else { return }
                    _ = session.addBookmark(
                        url: cleanURL,
                        title: newBookmarkTitle,
                        folderID: newBookmarkFolderID,
                        isPinnedToStartPage: newBookmarkFolderID == nil
                    )
                    isAddingBookmark = false
                    newBookmarkTitle = ""
                    newBookmarkURL = ""
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(newBookmarkURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.accentColor.opacity(0.06))
    }

    // MARK: - Bookmarks List

    @ViewBuilder
    private var bookmarksListView: some View {
        let isSearching = !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if bookmarkFilter == .all && !isSearching {
            if session.bookmarks.isEmpty && session.bookmarkFolders.isEmpty {
                emptyStateView(
                    icon: "star",
                    title: "暂无书签",
                    subtitle: "在浏览网页时按 Cmd+D 或点击地址栏星标即可添加到书签"
                )
            } else {
                groupedBookmarksScrollView
            }
        } else {
            VStack(spacing: 0) {
                if case .folder(let fid) = bookmarkFilter, let folder = session.folder(forID: fid) {
                    selectedFolderSubheader(for: folder)
                    Divider()
                }

                if filteredBookmarks.isEmpty {
                    emptyStateView(
                        icon: "star",
                        title: isSearching ? "未找到匹配书签" : "此分组暂无书签",
                        subtitle: isSearching ? "尝试更换搜索关键词" : "点击上方「+」按钮添加书签，或将其他书签移动到此分组"
                    )
                } else {
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(filteredBookmarks.enumerated()), id: \.element.id) { index, bookmark in
                                if editingBookmarkID == bookmark.id {
                                    inlineEditBookmarkView(for: bookmark)
                                } else {
                                    bookmarkRow(bookmark, showFolderBadge: isSearching || bookmarkFilter == .all)
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
        }
    }

    private var groupedBookmarksScrollView: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(spacing: 0) {
                // 1. Folder Sections
                ForEach(session.bookmarkFolders) { folder in
                    let items = session.bookmarks(inFolder: folder.id)
                    let isCollapsed = collapsedFolderIDs.contains(folder.id)

                    folderSectionHeader(folder: folder, count: items.count, isCollapsed: isCollapsed)

                    if !isCollapsed {
                        if items.isEmpty {
                            HStack {
                                Text("分组内暂无书签")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Button("添加书签") {
                                    openInlineAddBookmark(defaultFolderID: folder.id)
                                }
                                .font(.system(size: 11))
                                .buttonStyle(.plain)
                                .foregroundColor(.accentColor)
                            }
                            .padding(.horizontal, 28)
                            .padding(.vertical, 8)
                        } else {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, bookmark in
                                if editingBookmarkID == bookmark.id {
                                    inlineEditBookmarkView(for: bookmark)
                                } else {
                                    bookmarkRow(bookmark, showFolderBadge: false)
                                }

                                if index < items.count - 1 {
                                    Divider()
                                        .padding(.leading, 42)
                                        .padding(.trailing, 14)
                                }
                            }
                        }
                    }

                    Divider()
                }

                // 2. Ungrouped / Root Bookmarks Section
                let ungrouped = session.ungroupedBookmarks
                if !ungrouped.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "star.square.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.yellow)
                        Text("未分组 / 主页收藏")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                        Text("(\(ungrouped.count))")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary.opacity(0.8))
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color.secondary.opacity(0.05))

                    ForEach(Array(ungrouped.enumerated()), id: \.element.id) { index, bookmark in
                        if editingBookmarkID == bookmark.id {
                            inlineEditBookmarkView(for: bookmark)
                        } else {
                            bookmarkRow(bookmark, showFolderBadge: false)
                        }

                        if index < ungrouped.count - 1 {
                            Divider()
                                .padding(.leading, 42)
                                .padding(.trailing, 14)
                        }
                    }
                }
            }
            .padding(.bottom, 6)
        }
    }

    private func folderSectionHeader(folder: BookmarkFolder, count: Int, isCollapsed: Bool) -> some View {
        HStack(spacing: 8) {
            Button(action: {
                if isCollapsed {
                    collapsedFolderIDs.remove(folder.id)
                } else {
                    collapsedFolderIDs.insert(folder.id)
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 12)

                    Image(systemName: "folder.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.accentColor)

                    Text(folder.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)

                    Text("(\(count))")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()

            HStack(spacing: 8) {
                Button(action: {
                    openInlineAddBookmark(defaultFolderID: folder.id)
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("在此分组添加书签")

                Button(action: {
                    renamingFolderID = folder.id
                    renameFolderText = folder.name
                }) {
                    Image(systemName: "pencil")
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("重命名分组")

                if count > 0 {
                    Button(action: {
                        session.openAllBookmarks(inFolder: folder.id)
                        isPresented = false
                    }) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("在新标签页中打开全部 (\(count))")
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Color.secondary.opacity(0.06))
        .contextMenu {
            Button("在此分组添加书签...") {
                openInlineAddBookmark(defaultFolderID: folder.id)
            }
            Button("在新标签页中打开全部 (\(count))") {
                session.openAllBookmarks(inFolder: folder.id)
                isPresented = false
            }
            .disabled(count == 0)
            Divider()
            Button("重命名分组...") {
                renamingFolderID = folder.id
                renameFolderText = folder.name
            }
            Button("在书签管理器中打开...") {
                session.openBookmarkManager(selectingFolderID: folder.id)
            }
            Divider()
            Button("删除分组（保留书签至未分组）", role: .destructive) {
                session.removeBookmarkFolder(id: folder.id, deleteContainedBookmarks: false)
            }
            Button("删除分组及组内所有书签", role: .destructive) {
                session.removeBookmarkFolder(id: folder.id, deleteContainedBookmarks: true)
            }
        }
    }

    private func selectedFolderSubheader(for folder: BookmarkFolder) -> some View {
        let count = session.bookmarks(inFolder: folder.id).count
        return HStack(spacing: 8) {
            Image(systemName: "folder.fill")
                .font(.system(size: 12))
                .foregroundColor(.accentColor)

            Text(folder.name)
                .font(.system(size: 12, weight: .bold))

            Text("· \(count) 个书签")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            Spacer()

            Button("添加") {
                openInlineAddBookmark(defaultFolderID: folder.id)
            }
            .font(.system(size: 11))
            .controlSize(.mini)

            Button("重命名") {
                renamingFolderID = folder.id
                renameFolderText = folder.name
            }
            .font(.system(size: 11))
            .controlSize(.mini)

            Button("全部打开") {
                session.openAllBookmarks(inFolder: folder.id)
                isPresented = false
            }
            .font(.system(size: 11))
            .controlSize(.mini)
            .disabled(count == 0)

            Menu {
                Button("仅删除分组（保留书签至未分组）") {
                    bookmarkFilter = .all
                    session.removeBookmarkFolder(id: folder.id, deleteContainedBookmarks: false)
                }
                Button("删除分组及组内所有书签", role: .destructive) {
                    bookmarkFilter = .all
                    session.removeBookmarkFolder(id: folder.id, deleteContainedBookmarks: true)
                }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundColor(.red)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Color.accentColor.opacity(0.06))
    }

    // MARK: - Bookmark Row & Inline Edit

    private func bookmarkRow(_ bookmark: BookmarkEntry, showFolderBadge: Bool) -> some View {
        HStack(spacing: 10) {
            if let siteIcon = session.siteIcon(for: bookmark.url) {
                SiteIconThumbnail(image: siteIcon, size: 18)
            } else if !bookmark.iconName.isEmpty, let assetIcon = FavoritesManager.shared.iconImage(named: bookmark.iconName) {
                Image(nsImage: assetIcon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color(bookmarkHex: bookmark.colorHex) ?? Color.accentColor)
                    .frame(width: 18, height: 18)
                    .overlay(
                        Text(bookmark.resolvedIconLetter)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                    )
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(bookmark.displayTitle)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    if showFolderBadge, let fid = bookmark.folderID {
                        Text(session.folderName(for: fid))
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                Capsule().fill(Color.accentColor.opacity(0.12))
                            )
                    }
                }

                Text(bookmark.url)
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 6)

            HStack(spacing: 7) {
                // Quick Move to Folder Menu
                Menu {
                    Text("移动到分组")
                    Divider()
                    Button(action: {
                        session.moveBookmark(id: bookmark.id, toFolderID: nil)
                    }) {
                        HStack {
                            Text("未分组 (主页)")
                            if bookmark.folderID == nil {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    Divider()
                    ForEach(session.bookmarkFolders) { folder in
                        Button(action: {
                            session.moveBookmark(id: bookmark.id, toFolderID: folder.id)
                        }) {
                            HStack {
                                Text("📁 \(folder.name)")
                                if bookmark.folderID == folder.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("移动到指定分组")

                Button(action: {
                    beginEditing(bookmark)
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
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .onTapGesture {
            session.navigate(to: bookmark.url)
            isPresented = false
        }
        .contextMenu {
            Button("在当前标签页打开") {
                session.navigate(to: bookmark.url)
                isPresented = false
            }
            Button("在新标签页中打开") {
                _ = session.createTab(url: bookmark.url, select: true)
                isPresented = false
            }
            Divider()
            Menu("移动到分组") {
                Button("未分组 (主页)") {
                    session.moveBookmark(id: bookmark.id, toFolderID: nil)
                }
                Divider()
                ForEach(session.bookmarkFolders) { folder in
                    Button("📁 \(folder.name)") {
                        session.moveBookmark(id: bookmark.id, toFolderID: folder.id)
                    }
                }
            }
            if bookmark.folderID == nil {
                Button(bookmark.isPinnedToStartPage ? "从主页个人收藏移除" : "显示在主页个人收藏") {
                    session.togglePinBookmarkToStartPage(id: bookmark.id)
                }
            }
            Button("编辑书签...") {
                beginEditing(bookmark)
            }
            Button("拷贝链接") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(bookmark.url, forType: .string)
            }
            Divider()
            Button("删除书签", role: .destructive) {
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

            HStack(spacing: 8) {
                Text("分组:")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Picker("", selection: $editFolderID) {
                    Text("未分组 (主页)").tag(String?.none)
                    Divider()
                    ForEach(session.bookmarkFolders) { folder in
                        Text("📁 \(folder.name)").tag(String?.some(folder.id))
                    }
                }
                .labelsHidden()
                .frame(width: 145)

                if editFolderID == nil {
                    Toggle("主页显示", isOn: $editPinToStartPage)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 11))
                }

                Spacer()

                Button("取消") {
                    editingBookmarkID = nil
                }
                .controlSize(.small)

                Button("保存") {
                    session.updateBookmark(
                        id: bookmark.id,
                        title: editTitle,
                        url: editURL,
                        folderID: editFolderID,
                        isPinnedToStartPage: editFolderID == nil ? editPinToStartPage : false
                    )
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
            Button("在当前标签页打开") {
                session.navigate(to: entry.url)
                isPresented = false
            }
            Button("在新标签页中打开") {
                _ = session.createTab(url: entry.url, select: true)
                isPresented = false
            }
            Divider()
            Button("收藏到书签") {
                _ = session.addBookmark(url: entry.url, title: entry.displayTitle, folderID: nil, isPinnedToStartPage: true)
            }
            Button("拷贝链接") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.url, forType: .string)
            }
            Button("删除此记录", role: .destructive) {
                session.removeHistoryItem(id: entry.id)
            }
        }
    }

    // MARK: - Helpers

    private func beginEditing(_ bookmark: BookmarkEntry) {
        editingBookmarkID = bookmark.id
        editTitle = bookmark.title
        editURL = bookmark.url
        editFolderID = bookmark.folderID
        editPinToStartPage = bookmark.isPinnedToStartPage
    }

    private func openInlineAddBookmark(defaultFolderID: String?) {
        isCreatingFolder = false
        newBookmarkFolderID = defaultFolderID
        if let tab = session.activeTab, !tab.isHome, !tab.url.isEmpty {
            newBookmarkTitle = tab.displayTitle
            newBookmarkURL = tab.url
        } else {
            newBookmarkTitle = ""
            newBookmarkURL = ""
        }
        isAddingBookmark = true
    }

    private func commitCreateFolder() {
        let trimmed = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let folder = session.createBookmarkFolder(name: trimmed) {
            bookmarkFilter = .folder(folder.id)
        }
        isCreatingFolder = false
        newFolderName = ""
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
