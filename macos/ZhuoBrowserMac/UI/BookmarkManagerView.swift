import AppKit
import SwiftUI

/// Sidebar selection filter in the full Bookmark Manager.
public enum BookmarkSidebarFilter: Equatable, Hashable {
    case all
    case startPage
    case ungrouped
    case folder(String)
}

/// Full-featured modern browser Bookmark Manager with two-pane folder sidebar,
/// search, sorting, inline creation/editing, folder organization, batch move/delete, and HTML import/export.
public struct BookmarkManagerView: View {
    @ObservedObject var session: BrowserSession
    @Binding var isPresented: Bool

    @State private var selectedFilter: BookmarkSidebarFilter = .all
    @State private var searchText: String = ""
    @State private var sortOrder: BookmarkSortOrder = .manual

    // Folder creation & renaming
    @State private var isCreatingFolder: Bool = false
    @State private var newFolderName: String = ""
    @State private var renamingFolderID: String?
    @State private var renameFolderText: String = ""
    @State private var deletingFolderTarget: BookmarkFolder?

    // Bookmark creation & inline editing
    @State private var isAddingBookmark: Bool = false
    @State private var addTitle: String = ""
    @State private var addURL: String = ""
    @State private var addFolderID: String? = nil
    @State private var addPinToStartPage: Bool = true

    @State private var editingBookmarkID: String?
    @State private var editTitle: String = ""
    @State private var editURL: String = ""
    @State private var editFolderID: String? = nil
    @State private var editPinToStartPage: Bool = false

    // Batch selection mode
    @State private var isBatchMode: Bool = false
    @State private var selectedBookmarkIDs: Set<String> = []

    // Import / Export feedback
    @State private var statusBannerMessage: String?

    public init(session: BrowserSession, isPresented: Binding<Bool>) {
        self.session = session
        self._isPresented = isPresented
    }

    private var activeFolder: BookmarkFolder? {
        if case .folder(let folderID) = selectedFilter {
            return session.folder(forID: folderID)
        }
        return nil
    }

    private var displayedBookmarks: [BookmarkEntry] {
        let base: [BookmarkEntry]
        switch selectedFilter {
        case .all:
            base = session.bookmarks
        case .startPage:
            base = session.bookmarks.filter { $0.folderID == nil && $0.isPinnedToStartPage }
        case .ungrouped:
            base = session.ungroupedBookmarks
        case .folder(let folderID):
            base = session.bookmarks(inFolder: folderID)
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered: [BookmarkEntry]
        if query.isEmpty {
            filtered = base
        } else {
            filtered = base.filter { item in
                let folderName = session.folderName(for: item.folderID).lowercased()
                return item.title.lowercased().contains(query)
                    || item.url.lowercased().contains(query)
                    || folderName.contains(query)
            }
        }

        return LibraryPolicy.sortBookmarks(filtered, by: sortOrder)
    }

    public var body: some View {
        HStack(spacing: 0) {
            // Left Sidebar: Smart Views & Folders
            sidebarView
                .frame(width: 225)
                .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Right Content Area: Toolbar, Batch Bar, Add/Edit Cards, Bookmarks List
            VStack(spacing: 0) {
                contentHeaderBar

                Divider()

                if isBatchMode {
                    batchActionBar
                    Divider()
                }

                if isAddingBookmark {
                    addBookmarkCard
                    Divider()
                }

                if let banner = statusBannerMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 12))
                        Text(banner)
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        Button(action: { statusBannerMessage = nil }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.green.opacity(0.1))
                    Divider()
                }

                bookmarksTableContent
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .frame(width: 860, height: 580)
        .onAppear {
            if let targetFolderID = session.bookmarkManagerSelectedFolderID {
                selectedFilter = .folder(targetFolderID)
                session.bookmarkManagerSelectedFolderID = nil
            }
        }
        .onChange(of: selectedFilter) { newValue in
            editingBookmarkID = nil
            selectedBookmarkIDs.removeAll()
            if case .folder(let fid) = newValue {
                addFolderID = fid
                addPinToStartPage = false
            } else {
                addFolderID = nil
                addPinToStartPage = true
            }
        }
        .alert(
            "删除书签分组「\(deletingFolderTarget?.name ?? "")」？",
            isPresented: Binding(
                get: { deletingFolderTarget != nil },
                set: { if !$0 { deletingFolderTarget = nil } }
            )
        ) {
            Button("仅删除分组（保留书签至未分组）") {
                if let folder = deletingFolderTarget {
                    session.removeBookmarkFolder(id: folder.id, deleteContainedBookmarks: false)
                    if selectedFilter == .folder(folder.id) {
                        selectedFilter = .all
                    }
                }
                deletingFolderTarget = nil
            }
            Button("删除分组及组内所有书签", role: .destructive) {
                if let folder = deletingFolderTarget {
                    session.removeBookmarkFolder(id: folder.id, deleteContainedBookmarks: true)
                    if selectedFilter == .folder(folder.id) {
                        selectedFilter = .all
                    }
                }
                deletingFolderTarget = nil
            }
            Button("取消", role: .cancel) {
                deletingFolderTarget = nil
            }
        } message: {
            Text("你可以选择将组内的书签移至「未分组」，或连同组内书签一并永久删除。")
        }
    }

    // MARK: - Left Sidebar

    private var sidebarView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // App / Window Title
            HStack(spacing: 8) {
                Image(systemName: "book.closed.fill")
                    .foregroundColor(.accentColor)
                    .font(.system(size: 14))
                Text("书签管理器")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 14) {
                    // 1. Smart Views
                    VStack(alignment: .leading, spacing: 3) {
                        Text("书签视图")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.bottom, 2)

                        sidebarRow(
                            title: "所有书签",
                            icon: "books.vertical.fill",
                            iconColor: .accentColor,
                            count: session.bookmarks.count,
                            isSelected: selectedFilter == .all
                        ) {
                            selectedFilter = .all
                        }

                        sidebarRow(
                            title: "主页个人收藏",
                            icon: "star.square.fill",
                            iconColor: .yellow,
                            count: session.startPagePinnedBookmarks.count,
                            isSelected: selectedFilter == .startPage
                        ) {
                            selectedFilter = .startPage
                        }

                        sidebarRow(
                            title: "未分组书签",
                            icon: "tray.fill",
                            iconColor: .secondary,
                            count: session.ungroupedBookmarks.count,
                            isSelected: selectedFilter == .ungrouped
                        ) {
                            selectedFilter = .ungrouped
                        }
                    }

                    Divider()
                        .padding(.horizontal, 8)

                    // 2. Custom & Preset Folders
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("书签分组 (\(session.bookmarkFolders.count))")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)
                            Spacer()
                            Button(action: {
                                isCreatingFolder = true
                                newFolderName = ""
                            }) {
                                HStack(spacing: 3) {
                                    Image(systemName: "folder.badge.plus")
                                        .font(.system(size: 11))
                                    Text("新建")
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .foregroundColor(.accentColor)
                            }
                            .buttonStyle(.plain)
                            .help("新建书签分组")
                        }
                        .padding(.horizontal, 10)
                        .padding(.bottom, 2)

                        if isCreatingFolder {
                            VStack(spacing: 6) {
                                TextField("输入新分组名称...", text: $newFolderName)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 12))
                                    .onSubmit {
                                        commitCreateFolder()
                                    }

                                HStack(spacing: 6) {
                                    Spacer()
                                    Button("取消") {
                                        isCreatingFolder = false
                                        newFolderName = ""
                                    }
                                    .controlSize(.mini)

                                    Button("创建") {
                                        commitCreateFolder()
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.mini)
                                    .disabled(newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                }
                            }
                            .padding(8)
                            .background(Color.secondary.opacity(0.08))
                            .cornerRadius(8)
                            .padding(.horizontal, 6)
                        }

                        ForEach(Array(session.bookmarkFolders.enumerated()), id: \.element.id) { index, folder in
                            if renamingFolderID == folder.id {
                                folderRenameInlineView(folder: folder)
                            } else {
                                folderSidebarRow(folder: folder, index: index)
                            }
                        }
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 6)
            }

            Divider()

            // Bottom Import / Export Bar
            HStack(spacing: 8) {
                Button(action: {
                    session.importBookmarksFromPanel { count in
                        showStatusBanner("已成功导入 \(count) 条书签")
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 11))
                        Text("导入书签")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .help("从标准 HTML 书签文件导入书签与分组")

                Button(action: {
                    session.exportBookmarksToPanel { ok in
                        if ok {
                            showStatusBanner("书签已导出为 HTML 文件")
                        }
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 11))
                        Text("导出书签")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .help("将所有分组与书签导出为标准 HTML 文件")
            }
            .padding(10)
        }
    }

    private func sidebarRow(
        title: String,
        icon: String,
        iconColor: Color,
        count: Int,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(isSelected ? .white : iconColor)
                    .frame(width: 18)

                Text(title)
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .white : .primary)
                    .lineLimit(1)

                Spacer()

                Text("\(count)")
                    .font(.system(size: 11))
                    .foregroundColor(isSelected ? .white.opacity(0.85) : .secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(
                        Capsule()
                            .fill(isSelected ? Color.white.opacity(0.2) : Color.secondary.opacity(0.12))
                    )
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? Color.accentColor : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func folderSidebarRow(folder: BookmarkFolder, index: Int) -> some View {
        let isSelected = selectedFilter == .folder(folder.id)
        let count = session.bookmarks(inFolder: folder.id).count

        return sidebarRow(
            title: folder.name,
            icon: "folder.fill",
            iconColor: .accentColor,
            count: count,
            isSelected: isSelected
        ) {
            selectedFilter = .folder(folder.id)
        }
        .contextMenu {
            Button("在此分组新建书签...") {
                selectedFilter = .folder(folder.id)
                openAddBookmarkForm(defaultFolderID: folder.id)
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

            Button("上移分组") {
                session.moveBookmarkFolder(id: folder.id, direction: -1)
            }
            .disabled(index == 0)

            Button("下移分组") {
                session.moveBookmarkFolder(id: folder.id, direction: 1)
            }
            .disabled(index >= session.bookmarkFolders.count - 1)

            Divider()

            Button("删除分组...", role: .destructive) {
                deletingFolderTarget = folder
            }
        }
    }

    private func folderRenameInlineView(folder: BookmarkFolder) -> some View {
        VStack(spacing: 6) {
            TextField("分组名称", text: $renameFolderText)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .onSubmit {
                    commitRenameFolder(folder.id)
                }

            HStack(spacing: 6) {
                Spacer()
                Button("取消") {
                    renamingFolderID = nil
                }
                .controlSize(.mini)

                Button("保存") {
                    commitRenameFolder(folder.id)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(8)
        .padding(.horizontal, 4)
    }

    // MARK: - Right Content Header Bar

    private var contentHeaderBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                // Current category / folder title
                HStack(spacing: 7) {
                    Image(systemName: currentHeaderIcon)
                        .foregroundColor(.accentColor)
                        .font(.system(size: 15))

                    Text(currentHeaderTitle)
                        .font(.system(size: 15, weight: .bold))
                        .lineLimit(1)

                    Text("(\(displayedBookmarks.count))")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                // Folder-specific quick buttons
                if let folder = activeFolder {
                    HStack(spacing: 6) {
                        Button(action: {
                            renamingFolderID = folder.id
                            renameFolderText = folder.name
                        }) {
                            Label("重命名", systemImage: "pencil")
                                .font(.system(size: 11))
                        }
                        .controlSize(.small)

                        Button(action: {
                            session.openAllBookmarks(inFolder: folder.id)
                            isPresented = false
                        }) {
                            Label("全部打开", systemImage: "arrow.up.right.square")
                                .font(.system(size: 11))
                        }
                        .controlSize(.small)
                        .disabled(displayedBookmarks.isEmpty)

                        Button(role: .destructive, action: {
                            deletingFolderTarget = folder
                        }) {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                                .foregroundColor(.red)
                        }
                        .controlSize(.small)
                        .help("删除此分组")
                    }
                }

                Spacer()

                // Sort Picker
                Menu {
                    ForEach(BookmarkSortOrder.allCases) { order in
                        Button(action: { sortOrder = order }) {
                            HStack {
                                Text(order.rawValue)
                                if sortOrder == order {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 11))
                        Text(sortOrder.rawValue)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(6)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                // Batch Mode Toggle
                Button(action: {
                    isBatchMode.toggle()
                    if !isBatchMode {
                        selectedBookmarkIDs.removeAll()
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: isBatchMode ? "checkmark.circle.fill" : "checkmark.circle")
                            .font(.system(size: 11))
                        Text(isBatchMode ? "退出批量" : "批量管理")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(isBatchMode ? .accentColor : .primary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(isBatchMode ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.1))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)

                // Add Bookmark Button
                Button(action: {
                    if isAddingBookmark {
                        isAddingBookmark = false
                    } else {
                        openAddBookmarkForm(defaultFolderID: activeFolder?.id)
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                        Text("新建书签")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.accentColor)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)

                // Close Manager Button
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("关闭书签管理器")
            }

            // Search Bar
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                TextField("在当前视图搜索书签名称、网址或分组...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))

                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(7)
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var currentHeaderTitle: String {
        switch selectedFilter {
        case .all:
            return "所有书签"
        case .startPage:
            return "主页个人收藏"
        case .ungrouped:
            return "未分组书签"
        case .folder(let fid):
            return session.folderName(for: fid)
        }
    }

    private var currentHeaderIcon: String {
        switch selectedFilter {
        case .all:
            return "books.vertical.fill"
        case .startPage:
            return "star.square.fill"
        case .ungrouped:
            return "tray.fill"
        case .folder:
            return "folder.fill"
        }
    }

    // MARK: - Batch Action Bar

    private var batchActionBar: some View {
        HStack(spacing: 10) {
            Text("已选择 \(selectedBookmarkIDs.count) 项")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.primary)

            Button(selectedBookmarkIDs.count == displayedBookmarks.count && !displayedBookmarks.isEmpty ? "取消全选" : "全选当前列表") {
                if selectedBookmarkIDs.count == displayedBookmarks.count {
                    selectedBookmarkIDs.removeAll()
                } else {
                    selectedBookmarkIDs = Set(displayedBookmarks.map(\.id))
                }
            }
            .font(.system(size: 11))
            .controlSize(.small)

            Spacer()

            // Batch Move Menu
            Menu {
                Button("未分组 (移出分组)") {
                    let count = selectedBookmarkIDs.count
                    session.moveBookmarks(ids: selectedBookmarkIDs, toFolderID: nil)
                    selectedBookmarkIDs.removeAll()
                    showStatusBanner("已将 \(count) 条书签移至「未分组」")
                }
                Divider()
                ForEach(session.bookmarkFolders) { folder in
                    Button("📁 \(folder.name)") {
                        let count = selectedBookmarkIDs.count
                        session.moveBookmarks(ids: selectedBookmarkIDs, toFolderID: folder.id)
                        selectedBookmarkIDs.removeAll()
                        showStatusBanner("已将 \(count) 条书签移动到「\(folder.name)」")
                    }
                }
            } label: {
                Label("移动到分组...", systemImage: "folder")
                    .font(.system(size: 11, weight: .medium))
            }
            .controlSize(.small)
            .disabled(selectedBookmarkIDs.isEmpty)

            Button(action: {
                for id in selectedBookmarkIDs {
                    if let bm = session.bookmark(forID: id) {
                        _ = session.createTab(url: bm.url, select: true)
                    }
                }
                isPresented = false
            }) {
                Label("在新标签页打开", systemImage: "plus.square.on.square")
                    .font(.system(size: 11))
            }
            .controlSize(.small)
            .disabled(selectedBookmarkIDs.isEmpty)

            Button(role: .destructive, action: {
                let count = selectedBookmarkIDs.count
                session.removeBookmarks(ids: selectedBookmarkIDs)
                selectedBookmarkIDs.removeAll()
                showStatusBanner("已批量删除 \(count) 条书签")
            }) {
                Label("批量删除", systemImage: "trash")
                    .font(.system(size: 11))
                    .foregroundColor(.red)
            }
            .controlSize(.small)
            .disabled(selectedBookmarkIDs.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.08))
    }

    // MARK: - Add Bookmark Card

    private var addBookmarkCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("新建书签", systemImage: "plus.circle.fill")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundColor(.accentColor)
                Spacer()
                if let tab = session.activeTab, !tab.isHome, !tab.url.isEmpty {
                    Button("填入当前浏览页") {
                        addTitle = tab.displayTitle
                        addURL = tab.url
                    }
                    .font(.system(size: 11))
                    .controlSize(.small)
                }
            }

            HStack(spacing: 10) {
                TextField("书签名称 (例如：GitHub)", text: $addTitle)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))

                TextField("网址 URL (例如：https://github.com)", text: $addURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
            }

            HStack(spacing: 14) {
                HStack(spacing: 6) {
                    Text("所属分组：")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)

                    Picker("", selection: $addFolderID) {
                        Text("未分组 (根目录)").tag(String?.none)
                        Divider()
                        ForEach(session.bookmarkFolders) { folder in
                            Text("📁 \(folder.name)").tag(String?.some(folder.id))
                        }
                    }
                    .labelsHidden()
                    .frame(width: 180)
                }

                if addFolderID == nil {
                    Toggle("显示在主页个人收藏", isOn: $addPinToStartPage)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 12))
                }

                Spacer()

                Button("取消") {
                    isAddingBookmark = false
                }
                .controlSize(.small)

                Button("保存书签") {
                    commitAddBookmark()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(addURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.accentColor.opacity(0.06))
    }

    // MARK: - Bookmarks Table Content

    @ViewBuilder
    private var bookmarksTableContent: some View {
        if displayedBookmarks.isEmpty {
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: searchText.isEmpty ? "bookmark.slash" : "magnifyingglass")
                    .font(.system(size: 36))
                    .foregroundColor(.secondary.opacity(0.5))

                Text(searchText.isEmpty ? "此分组下暂无书签" : "未找到匹配的书签")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)

                Text(searchText.isEmpty ? "点击右上角「新建书签」或将其他书签移动到此分组" : "请尝试更换搜索关键词或切换到「所有书签」")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary.opacity(0.8))

                if searchText.isEmpty {
                    Button(action: {
                        openAddBookmarkForm(defaultFolderID: activeFolder?.id)
                    }) {
                        Label("添加第一条书签", systemImage: "plus")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .padding(.top, 4)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(displayedBookmarks.enumerated()), id: \.element.id) { index, bookmark in
                        if editingBookmarkID == bookmark.id {
                            inlineEditCard(for: bookmark)
                        } else {
                            bookmarkManagerRow(bookmark)
                        }

                        if index < displayedBookmarks.count - 1 {
                            Divider()
                                .padding(.leading, isBatchMode ? 72 : 48)
                                .padding(.trailing, 16)
                        }
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }

    private func bookmarkManagerRow(_ bookmark: BookmarkEntry) -> some View {
        let isSelected = selectedBookmarkIDs.contains(bookmark.id)

        return HStack(spacing: 12) {
            if isBatchMode {
                Button(action: {
                    if isSelected {
                        selectedBookmarkIDs.remove(bookmark.id)
                    } else {
                        selectedBookmarkIDs.insert(bookmark.id)
                    }
                }) {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .font(.system(size: 14))
                        .foregroundColor(isSelected ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
            }

            // Icon (Favicon or Preset Image or Colored Monogram)
            bookmarkIconView(for: bookmark)

            // Title & URL
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(bookmark.displayTitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    if bookmark.folderID == nil && bookmark.isPinnedToStartPage {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.yellow)
                            .help("已固定在主页个人收藏")
                    }
                }

                Text(bookmark.url)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            // Interactive Folder Tag Pill (1-click move to another folder!)
            Menu {
                Text("移动到分组")
                Divider()
                Button(action: {
                    session.moveBookmark(id: bookmark.id, toFolderID: nil)
                    showStatusBanner("已将「\(bookmark.displayTitle)」移至未分组")
                }) {
                    HStack {
                        Text("未分组 (主页根目录)")
                        if bookmark.folderID == nil {
                            Image(systemName: "checkmark")
                        }
                    }
                }

                Divider()

                ForEach(session.bookmarkFolders) { folder in
                    Button(action: {
                        session.moveBookmark(id: bookmark.id, toFolderID: folder.id)
                        showStatusBanner("已将「\(bookmark.displayTitle)」移动到「\(folder.name)」")
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
                HStack(spacing: 4) {
                    Image(systemName: bookmark.folderID == nil ? "tray" : "folder.fill")
                        .font(.system(size: 10))
                    Text(session.folderName(for: bookmark.folderID))
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundColor(bookmark.folderID == nil ? .secondary : .accentColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(bookmark.folderID == nil ? Color.secondary.opacity(0.1) : Color.accentColor.opacity(0.12))
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("点击将此书签移动到其他分组")

            // Row Action Buttons
            HStack(spacing: 8) {
                Button(action: {
                    beginEditing(bookmark)
                }) {
                    Image(systemName: "pencil")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help("编辑书签名称、网址或所属分组")

                Button(action: {
                    session.removeBookmark(id: bookmark.id)
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help("删除书签")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            if isBatchMode {
                if isSelected {
                    selectedBookmarkIDs.remove(bookmark.id)
                } else {
                    selectedBookmarkIDs.insert(bookmark.id)
                }
            } else {
                session.navigate(to: bookmark.url)
                isPresented = false
            }
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
                Button("未分组 (主页根目录)") {
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

    @ViewBuilder
    private func bookmarkIconView(for bookmark: BookmarkEntry) -> some View {
        if let siteIcon = session.siteIcon(for: bookmark.url) {
            SiteIconThumbnail(image: siteIcon, size: 22)
        } else if !bookmark.iconName.isEmpty, let assetIcon = FavoritesManager.shared.iconImage(named: bookmark.iconName) {
            Image(nsImage: assetIcon)
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color(bookmarkHex: bookmark.colorHex) ?? Color.accentColor)
                .frame(width: 22, height: 22)
                .overlay(
                    Text(bookmark.resolvedIconLetter)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                )
        }
    }

    private func inlineEditCard(for bookmark: BookmarkEntry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                TextField("书签名称", text: $editTitle)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))

                TextField("网址 URL", text: $editURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
            }

            HStack(spacing: 14) {
                HStack(spacing: 6) {
                    Text("所属分组：")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)

                    Picker("", selection: $editFolderID) {
                        Text("未分组 (根目录)").tag(String?.none)
                        Divider()
                        ForEach(session.bookmarkFolders) { folder in
                            Text("📁 \(folder.name)").tag(String?.some(folder.id))
                        }
                    }
                    .labelsHidden()
                    .frame(width: 180)
                }

                if editFolderID == nil {
                    Toggle("显示在主页个人收藏", isOn: $editPinToStartPage)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 12))
                }

                Spacer()

                Button("删除", role: .destructive) {
                    session.removeBookmark(id: bookmark.id)
                    editingBookmarkID = nil
                }
                .controlSize(.small)

                Button("取消") {
                    editingBookmarkID = nil
                }
                .controlSize(.small)

                Button("保存修改") {
                    session.updateBookmark(
                        id: bookmark.id,
                        title: editTitle,
                        url: editURL,
                        folderID: editFolderID,
                        isPinnedToStartPage: editFolderID == nil ? editPinToStartPage : false
                    )
                    editingBookmarkID = nil
                    showStatusBanner("已保存书签修改")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.accentColor.opacity(0.08))
    }

    // MARK: - Helpers

    private func openAddBookmarkForm(defaultFolderID: String?) {
        addFolderID = defaultFolderID
        addPinToStartPage = (defaultFolderID == nil)
        if let tab = session.activeTab, !tab.isHome, !tab.url.isEmpty {
            addTitle = tab.displayTitle
            addURL = tab.url
        } else {
            addTitle = ""
            addURL = ""
        }
        isAddingBookmark = true
    }

    private func commitAddBookmark() {
        let trimmedURL = addURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else { return }
        _ = session.addBookmark(
            url: trimmedURL,
            title: addTitle,
            folderID: addFolderID,
            isPinnedToStartPage: addFolderID == nil ? addPinToStartPage : false
        )
        isAddingBookmark = false
        addTitle = ""
        addURL = ""
        showStatusBanner("已添加新书签")
    }

    private func beginEditing(_ bookmark: BookmarkEntry) {
        editingBookmarkID = bookmark.id
        editTitle = bookmark.title
        editURL = bookmark.url
        editFolderID = bookmark.folderID
        editPinToStartPage = bookmark.isPinnedToStartPage
    }

    private func commitCreateFolder() {
        let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if let created = session.createBookmarkFolder(name: name) {
            selectedFilter = .folder(created.id)
            showStatusBanner("已创建分组「\(created.name)」")
        }
        isCreatingFolder = false
        newFolderName = ""
    }

    private func commitRenameFolder(_ id: String) {
        let name = renameFolderText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            session.renameBookmarkFolder(id: id, newName: name)
        }
        renamingFolderID = nil
    }

    private func showStatusBanner(_ text: String) {
        statusBannerMessage = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
            if statusBannerMessage == text {
                statusBannerMessage = nil
            }
        }
    }
}

extension Color {
    init?(bookmarkHex: String) {
        var hexSanitized = bookmarkHex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b)
    }
}
