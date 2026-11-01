import AppKit
import SwiftUI

/// Section displaying curated and user-customized favorites matching macOS Safari's home page design,
/// with full support for adding, editing, deleting, grouping, and moving bookmarks across folders.
public struct FavoritesSectionView: View {
    @ObservedObject var session: BrowserSession
    let hasWallpaper: Bool

    @ObservedObject private var favoritesManager = FavoritesManager.shared
    @State private var activeFolderID: String?
    @State private var editingRootBookmarkID: String?
    @State private var isShowingAddBookmarkPopover: Bool = false
    @State private var isShowingNewFolderPopover: Bool = false
    @State private var containerWidth: CGFloat = 1000

    // Quick Add / Edit states on Start Page
    @State private var formTitle: String = ""
    @State private var formURL: String = ""
    @State private var formFolderID: String? = nil
    @State private var newFolderName: String = ""

    public init(session: BrowserSession, hasWallpaper: Bool) {
        self.session = session
        self.hasWallpaper = hasWallpaper
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section Header: "个人收藏" + Quick Management Controls
            HStack(alignment: .center, spacing: 10) {
                Text("个人收藏")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(hasWallpaper ? .white : Color(nsColor: .labelColor))
                    .shadow(color: hasWallpaper ? Color.black.opacity(0.4) : SwiftUI.Color.clear, radius: 3, y: 1)
                    .padding(.leading, 2)

                Spacer()

                // + 添加书签
                Button(action: {
                    formTitle = ""
                    formURL = ""
                    formFolderID = nil
                    isShowingAddBookmarkPopover = true
                }) {
                    headerPillLabel(icon: "plus", title: "添加书签")
                }
                .buttonStyle(.plain)
                .popover(isPresented: $isShowingAddBookmarkPopover, arrowEdge: .bottom) {
                    startPageAddBookmarkPopover
                }

                // + 新建分组
                Button(action: {
                    newFolderName = ""
                    isShowingNewFolderPopover = true
                }) {
                    headerPillLabel(icon: "folder.badge.plus", title: "新建分组")
                }
                .buttonStyle(.plain)
                .popover(isPresented: $isShowingNewFolderPopover, arrowEdge: .bottom) {
                    startPageNewFolderPopover
                }

                // 书签管理
                Button(action: {
                    session.openBookmarkManager()
                }) {
                    headerPillLabel(icon: "slider.horizontal.3", title: "管理书签")
                }
                .buttonStyle(.plain)
            }

            // Grid of Favorite Items (12 columns on wide windows, adaptive wrapping on narrow windows)
            Group {
                if containerWidth >= 930 {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.fixed(60), spacing: 18, alignment: .top), count: 12),
                        alignment: .leading,
                        spacing: 18
                    ) {
                        ForEach(favoritesManager.items) { item in
                            favoriteTile(for: item)
                        }
                    }
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 64, maximum: 76), spacing: 14, alignment: .top)],
                        alignment: .leading,
                        spacing: 18
                    ) {
                        ForEach(favoritesManager.items) { item in
                            favoriteTile(for: item)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: 940)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: FavoritesWidthPreferenceKey.self, value: proxy.size.width)
            }
        )
        .onPreferenceChange(FavoritesWidthPreferenceKey.self) { newWidth in
            containerWidth = newWidth
        }
    }

    private func headerPillLabel(icon: String, title: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10.5, weight: .semibold))
            Text(title)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundColor(hasWallpaper ? .white : .primary.opacity(0.85))
        .padding(.horizontal, 9)
        .padding(.vertical, 4.5)
        .background(
            Group {
                if hasWallpaper {
                    Capsule().fill(.ultraThinMaterial)
                } else {
                    Capsule().fill(Color.secondary.opacity(0.1))
                }
            }
        )
        .overlay(
            Capsule()
                .stroke(hasWallpaper ? Color.white.opacity(0.25) : Color.secondary.opacity(0.18), lineWidth: 0.8)
        )
    }

    @ViewBuilder
    private func favoriteTile(for item: FavoriteItem) -> some View {
        let isFolderPopoverShown = Binding<Bool>(
            get: { item.isFolder && activeFolderID == item.id },
            set: { shown in
                if !shown && activeFolderID == item.id {
                    activeFolderID = nil
                }
            }
        )

        let isEditPopoverShown = Binding<Bool>(
            get: { !item.isFolder && editingRootBookmarkID == item.id },
            set: { shown in
                if !shown && editingRootBookmarkID == item.id {
                    editingRootBookmarkID = nil
                }
            }
        )

        let resolvedSiteIcon: NSImage? = (item.iconName.isEmpty && !item.isFolder)
            ? session.siteIcon(for: item.url)
            : nil

        FavoriteTileItemView(
            session: session,
            item: item,
            siteIcon: resolvedSiteIcon,
            hasWallpaper: hasWallpaper,
            onOpen: {
                handleOpen(item)
            },
            onOpenInNewTab: {
                handleOpenInNewTab(item)
            },
            onEdit: {
                if item.isFolder {
                    activeFolderID = item.id
                } else if let bm = session.bookmark(forID: item.id) {
                    formTitle = bm.title
                    formURL = bm.url
                    formFolderID = bm.folderID
                    editingRootBookmarkID = item.id
                }
            }
        )
        .popover(isPresented: isFolderPopoverShown, arrowEdge: .bottom) {
            if let liveFolder = favoritesManager.items.first(where: { $0.id == item.id && $0.isFolder }) {
                FavoriteFolderPopoverView(
                    session: session,
                    folder: liveFolder,
                    onSelectChild: { child in
                        activeFolderID = nil
                        session.navigate(to: child.url)
                    },
                    onOpenAll: {
                        activeFolderID = nil
                        for child in liveFolder.children {
                            _ = session.createTab(url: child.url)
                        }
                    },
                    onDismiss: {
                        activeFolderID = nil
                    }
                )
            }
        }
        .popover(isPresented: isEditPopoverShown, arrowEdge: .bottom) {
            rootBookmarkEditPopover(for: item)
        }
    }

    // MARK: - Start Page Popovers (Add Bookmark / New Folder / Edit Root Bookmark)

    private var startPageAddBookmarkPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("添加书签到个人收藏")
                .font(.system(size: 13, weight: .bold))

            TextField("名称 (如 GitHub)", text: $formTitle)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))

            TextField("网址 URL (如 https://github.com)", text: $formURL)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))

            HStack {
                Text("所属分组:")
                    .font(.system(size: 11.5))
                    .foregroundColor(.secondary)
                Picker("", selection: $formFolderID) {
                    Text("主页个人收藏 (根目录)").tag(String?.none)
                    Divider()
                    ForEach(session.bookmarkFolders) { folder in
                        Text("📁 \(folder.name)").tag(String?.some(folder.id))
                    }
                }
                .labelsHidden()
            }

            HStack {
                Spacer()
                Button("取消") {
                    isShowingAddBookmarkPopover = false
                }
                .controlSize(.small)

                Button("添加") {
                    let cleanURL = formURL.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !cleanURL.isEmpty else { return }
                    _ = session.addBookmark(
                        url: cleanURL,
                        title: formTitle,
                        folderID: formFolderID,
                        isPinnedToStartPage: formFolderID == nil
                    )
                    isShowingAddBookmarkPopover = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(formURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(14)
        .frame(width: 290)
    }

    private var startPageNewFolderPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("新建书签分组")
                .font(.system(size: 13, weight: .bold))

            TextField("分组名称 (如 AI 工具、阅读列表)", text: $newFolderName)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .onSubmit {
                    createFolderFromPopover()
                }

            HStack {
                Spacer()
                Button("取消") {
                    isShowingNewFolderPopover = false
                }
                .controlSize(.small)

                Button("创建分组") {
                    createFolderFromPopover()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(14)
        .frame(width: 260)
    }

    private func rootBookmarkEditPopover(for item: FavoriteItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("编辑书签")
                .font(.system(size: 13, weight: .bold))

            TextField("书签名称", text: $formTitle)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))

            TextField("网址 URL", text: $formURL)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))

            HStack {
                Text("移动到分组:")
                    .font(.system(size: 11.5))
                    .foregroundColor(.secondary)
                Picker("", selection: $formFolderID) {
                    Text("主页个人收藏 (根目录)").tag(String?.none)
                    Divider()
                    ForEach(session.bookmarkFolders) { folder in
                        Text("📁 \(folder.name)").tag(String?.some(folder.id))
                    }
                }
                .labelsHidden()
            }

            HStack {
                Button("删除", role: .destructive) {
                    session.removeBookmark(id: item.id)
                    editingRootBookmarkID = nil
                }
                .controlSize(.small)

                Spacer()

                Button("取消") {
                    editingRootBookmarkID = nil
                }
                .controlSize(.small)

                Button("保存") {
                    session.updateBookmark(
                        id: item.id,
                        title: formTitle,
                        url: formURL,
                        folderID: formFolderID,
                        isPinnedToStartPage: formFolderID == nil
                    )
                    editingRootBookmarkID = nil
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(14)
        .frame(width: 290)
    }

    private func createFolderFromPopover() {
        let trimmed = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        _ = session.createBookmarkFolder(name: trimmed)
        isShowingNewFolderPopover = false
    }

    private func handleOpen(_ item: FavoriteItem) {
        if item.isFolder {
            activeFolderID = item.id
        } else if !item.url.isEmpty {
            session.navigate(to: item.url)
        }
    }

    private func handleOpenInNewTab(_ item: FavoriteItem) {
        if item.isFolder {
            for child in item.children {
                _ = session.createTab(url: child.url)
            }
        } else if !item.url.isEmpty {
            _ = session.createTab(url: item.url)
        }
    }
}

/// Single favorite tile with icon, title label, and full context menu for editing, moving, and deleting.
private struct FavoriteTileItemView: View {
    let session: BrowserSession
    let item: FavoriteItem
    let siteIcon: NSImage?
    let hasWallpaper: Bool
    let onOpen: () -> Void
    let onOpenInNewTab: () -> Void
    let onEdit: () -> Void

    @State private var isHovered: Bool = false
    @State private var isPressed: Bool = false

    var body: some View {
        Button(action: onOpen) {
            VStack(spacing: 6) {
                // Icon Tile
                ZStack {
                    if let image = FavoritesManager.shared.iconImage(named: item.iconName) {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 60, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 13.5, style: .continuous))
                    } else if item.isFolder {
                        customFolderTileIcon
                    } else if let siteIcon {
                        RoundedRectangle(cornerRadius: 13.5, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                            .frame(width: 60, height: 60)
                            .overlay(
                                SiteIconThumbnail(image: siteIcon, size: 32)
                            )
                    } else {
                        // Fallback colored letter monogram tile
                        RoundedRectangle(cornerRadius: 13.5, style: .continuous)
                            .fill(Color(bookmarkHex: LibraryPolicy.colorHex(for: item.fullTitle)) ?? Color.accentColor)
                            .frame(width: 60, height: 60)
                            .overlay(
                                Text(String(item.title.prefix(1)).uppercased())
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundColor(.white)
                            )
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 13.5, style: .continuous)
                        .stroke(
                            isHovered ? Color.accentColor : (hasWallpaper ? Color.white.opacity(0.25) : Color.black.opacity(0.06)),
                            lineWidth: isHovered ? 1.5 : 0.5
                        )
                )
                .shadow(
                    color: Color.black.opacity(isHovered ? 0.24 : (hasWallpaper ? 0.22 : 0.08)),
                    radius: isHovered ? 7 : 3,
                    y: isHovered ? 3 : 1
                )
                .scaleEffect(isPressed ? 0.94 : (isHovered ? 1.06 : 1.0))
                .animation(.spring(response: 0.24, dampingFraction: 0.72), value: isHovered)

                // Title label below tile
                Text(item.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(hasWallpaper ? Color.white.opacity(0.92) : Color.primary.opacity(0.88))
                    .shadow(color: hasWallpaper ? Color.black.opacity(0.4) : SwiftUI.Color.clear, radius: 2, y: 1)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(width: 74, height: 28, alignment: .top)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .contextMenu {
            if item.isFolder {
                Button("打开分组") {
                    onOpen()
                }
                if !item.children.isEmpty {
                    Button("在新标签页中打开全部 (\(item.children.count))") {
                        onOpenInNewTab()
                    }
                }
                Divider()
                Button("在书签管理器中管理此分组...") {
                    session.openBookmarkManager(selectingFolderID: item.id)
                }
                Divider()
                Button("删除分组（保留书签至主页）") {
                    session.removeBookmarkFolder(id: item.id, deleteContainedBookmarks: false)
                }
                Button("删除分组及组内所有书签", role: .destructive) {
                    session.removeBookmarkFolder(id: item.id, deleteContainedBookmarks: true)
                }
            } else {
                Button("打开") {
                    onOpen()
                }
                Button("在新标签页中打开") {
                    onOpenInNewTab()
                }
                Divider()
                Button("编辑书签...") {
                    onEdit()
                }
                Menu("移动到分组") {
                    ForEach(session.bookmarkFolders) { folder in
                        Button("📁 \(folder.name)") {
                            session.moveBookmark(id: item.id, toFolderID: folder.id)
                        }
                    }
                }
                Button("复制链接") {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(item.url, forType: .string)
                }
                Divider()
                Button("从主页移除（保留在书签库）") {
                    session.togglePinBookmarkToStartPage(id: item.id)
                }
                Button("删除书签", role: .destructive) {
                    session.removeBookmark(id: item.id)
                }
            }
        }
        .help(item.fullTitle)
    }

    private var customFolderTileIcon: some View {
        RoundedRectangle(cornerRadius: 13.5, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color(red: 0.23, green: 0.27, blue: 0.34), Color(red: 0.16, green: 0.19, blue: 0.25)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 60, height: 60)
            .overlay(
                VStack(spacing: 4) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.white.opacity(0.9))
                    Text("\(item.children.count)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.75))
                }
            )
    }
}

/// Interactive popover displayed when clicking a favorite folder on the Start Page.
/// Supports adding, editing, deleting, moving bookmarks to other folders, and renaming the folder.
private struct FavoriteFolderPopoverView: View {
    @ObservedObject var session: BrowserSession
    let folder: FavoriteItem
    let onSelectChild: (FavoriteChild) -> Void
    let onOpenAll: () -> Void
    let onDismiss: () -> Void

    @State private var isRenamingFolder: Bool = false
    @State private var folderNameDraft: String = ""

    @State private var isAddingBookmark: Bool = false
    @State private var newTitle: String = ""
    @State private var newURL: String = ""

    @State private var editingChildID: String?
    @State private var editTitle: String = ""
    @State private var editURL: String = ""
    @State private var editFolderID: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(spacing: 8) {
                if isRenamingFolder {
                    HStack(spacing: 6) {
                        TextField("分组名称", text: $folderNameDraft)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                            .onSubmit {
                                commitFolderRename()
                            }

                        Button("保存") {
                            commitFolderRename()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.mini)

                        Button("取消") {
                            isRenamingFolder = false
                        }
                        .controlSize(.mini)
                    }
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "folder.fill")
                            .foregroundColor(.accentColor)
                            .font(.system(size: 13))

                        Text(folder.title)
                            .font(.system(size: 14, weight: .bold))
                            .lineLimit(1)

                        Text("(\(folder.children.count))")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)

                        Button(action: {
                            folderNameDraft = folder.title
                            isRenamingFolder = true
                        }) {
                            Image(systemName: "pencil")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("重命名分组")

                        Spacer()

                        Button(action: {
                            isAddingBookmark.toggle()
                            newTitle = ""
                            newURL = ""
                        }) {
                            HStack(spacing: 3) {
                                Image(systemName: "plus")
                                    .font(.system(size: 10, weight: .bold))
                                Text("添加")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.accentColor.opacity(0.12))
                            .cornerRadius(5)
                        }
                        .buttonStyle(.plain)
                        .help("在此分组添加书签")

                        Button(action: {
                            let targetID = folder.id
                            onDismiss()
                            session.openBookmarkManager(selectingFolderID: targetID)
                        }) {
                            Text("管理")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.secondary.opacity(0.12))
                                .cornerRadius(5)
                        }
                        .buttonStyle(.plain)
                        .help("在书签管理器中查看")
                    }
                }

                if isAddingBookmark {
                    VStack(spacing: 6) {
                        TextField("书签名称", text: $newTitle)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11.5))

                        TextField("网址 URL (如 https://example.com)", text: $newURL)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11.5))

                        HStack {
                            Spacer()
                            Button("取消") {
                                isAddingBookmark = false
                            }
                            .controlSize(.mini)

                            Button("添加到此分组") {
                                let cleanURL = newURL.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !cleanURL.isEmpty else { return }
                                _ = session.addBookmark(
                                    url: cleanURL,
                                    title: newTitle,
                                    folderID: folder.id,
                                    isPinnedToStartPage: false
                                )
                                isAddingBookmark = false
                                newTitle = ""
                                newURL = ""
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.mini)
                            .disabled(newURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    .padding(8)
                    .background(Color.accentColor.opacity(0.06))
                    .cornerRadius(7)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            // List of items in folder
            if folder.children.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "bookmark.slash")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("此分组内暂无书签")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(folder.children) { child in
                            if editingChildID == child.id {
                                folderChildEditView(for: child)
                            } else {
                                folderChildRowView(for: child)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
                .frame(maxHeight: 290)
            }

            Divider()

            // Footer
            HStack {
                Menu {
                    Button("仅删除分组（保留书签至主页）") {
                        let fid = folder.id
                        onDismiss()
                        session.removeBookmarkFolder(id: fid, deleteContainedBookmarks: false)
                    }
                    Button("删除分组及组内所有书签", role: .destructive) {
                        let fid = folder.id
                        onDismiss()
                        session.removeBookmarkFolder(id: fid, deleteContainedBookmarks: true)
                    }
                } label: {
                    Text("删除分组")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Spacer()

                Button("全部在新标签页中打开") {
                    onOpenAll()
                }
                .font(.system(size: 11, weight: .medium))
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
                .disabled(folder.children.isEmpty)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .frame(width: 340)
    }

    private func folderChildRowView(for child: FavoriteChild) -> some View {
        HStack(spacing: 10) {
            Button(action: { onSelectChild(child) }) {
                HStack(spacing: 10) {
                    if let siteIcon = session.siteIcon(for: child.url) {
                        SiteIconThumbnail(image: siteIcon, size: 22)
                    } else {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color(bookmarkHex: child.colorHex) ?? Color.gray)
                            .frame(width: 22, height: 22)
                            .overlay(
                                Text(child.iconLetter)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                            )
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(child.title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        if let host = URL(string: child.url)?.host {
                            Text(host)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Action Controls: Move to Folder, Edit, Delete
            HStack(spacing: 6) {
                Menu {
                    Button("移出分组到主页") {
                        session.moveBookmark(id: child.id, toFolderID: nil)
                    }
                    Divider()
                    ForEach(session.bookmarkFolders) { targetFolder in
                        Button(action: {
                            session.moveBookmark(id: child.id, toFolderID: targetFolder.id)
                        }) {
                            HStack {
                                Text("📁 \(targetFolder.name)")
                                if targetFolder.id == folder.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("移动到其他分组")

                Button(action: {
                    editingChildID = child.id
                    editTitle = child.title
                    editURL = child.url
                    editFolderID = folder.id
                }) {
                    Image(systemName: "pencil")
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("编辑书签")

                Button(action: {
                    session.removeBookmark(id: child.id)
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("删除书签")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(FolderItemRowHoverBackground())
        .contextMenu {
            Button("打开") {
                onSelectChild(child)
            }
            Button("在新标签页中打开") {
                _ = session.createTab(url: child.url, select: true)
            }
            Divider()
            Menu("移动到分组") {
                Button("移出分组到主页") {
                    session.moveBookmark(id: child.id, toFolderID: nil)
                }
                Divider()
                ForEach(session.bookmarkFolders) { targetFolder in
                    Button("📁 \(targetFolder.name)") {
                        session.moveBookmark(id: child.id, toFolderID: targetFolder.id)
                    }
                }
            }
            Button("编辑书签...") {
                editingChildID = child.id
                editTitle = child.title
                editURL = child.url
                editFolderID = folder.id
            }
            Button("复制链接") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(child.url, forType: .string)
            }
            Divider()
            Button("删除书签", role: .destructive) {
                session.removeBookmark(id: child.id)
            }
        }
    }

    private func folderChildEditView(for child: FavoriteChild) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("书签名称", text: $editTitle)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11.5))

            TextField("网址 URL", text: $editURL)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11.5))

            HStack(spacing: 6) {
                Text("分组:")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Picker("", selection: $editFolderID) {
                    Text("主页根目录").tag(String?.none)
                    Divider()
                    ForEach(session.bookmarkFolders) { targetFolder in
                        Text("📁 \(targetFolder.name)").tag(String?.some(targetFolder.id))
                    }
                }
                .labelsHidden()
                .frame(width: 130)

                Spacer()

                Button("取消") {
                    editingChildID = nil
                }
                .controlSize(.mini)

                Button("保存") {
                    session.updateBookmark(
                        id: child.id,
                        title: editTitle,
                        url: editURL,
                        folderID: editFolderID,
                        isPinnedToStartPage: editFolderID == nil
                    )
                    editingChildID = nil
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(6)
        .padding(.horizontal, 6)
    }

    private func commitFolderRename() {
        let trimmed = folderNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            session.renameBookmarkFolder(id: folder.id, newName: trimmed)
        }
        isRenamingFolder = false
    }
}

private struct FolderItemRowHoverBackground: View {
    @State private var isHovered = false

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(isHovered ? Color.accentColor.opacity(0.1) : SwiftUI.Color.clear)
            .padding(.horizontal, 4)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

private struct FavoritesWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 1000
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
