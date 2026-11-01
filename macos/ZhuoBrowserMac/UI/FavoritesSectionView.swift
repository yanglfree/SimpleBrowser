import AppKit
import SwiftUI

/// Section displaying curated/user favorites matching macOS Safari's home page design.
public struct FavoritesSectionView: View {
    @ObservedObject var session: BrowserSession
    let hasWallpaper: Bool

    @ObservedObject private var favoritesManager = FavoritesManager.shared
    @State private var activeFolder: FavoriteItem?
    @State private var containerWidth: CGFloat = 1000

    public init(session: BrowserSession, hasWallpaper: Bool) {
        self.session = session
        self.hasWallpaper = hasWallpaper
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section Header: "个人收藏"
            Text("个人收藏")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(hasWallpaper ? .white : Color(nsColor: .labelColor))
                .shadow(color: hasWallpaper ? Color.black.opacity(0.4) : SwiftUI.Color.clear, radius: 3, y: 1)
                .padding(.leading, 2)

            // Grid of Favorite Items (12 columns on wide windows, adaptive wrapping on narrow windows)
            Group {
                if containerWidth >= 930 {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.fixed(60), spacing: 18, alignment: .top), count: 12),
                        alignment: .leading,
                        spacing: 18
                    ) {
                        ForEach(favoritesManager.items) { item in
                            FavoriteTileItemView(
                                item: item,
                                hasWallpaper: hasWallpaper,
                                onOpen: {
                                    handleOpen(item)
                                },
                                onOpenInNewTab: {
                                    handleOpenInNewTab(item)
                                }
                            )
                        }
                    }
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 64, maximum: 76), spacing: 14, alignment: .top)],
                        alignment: .leading,
                        spacing: 18
                    ) {
                        ForEach(favoritesManager.items) { item in
                            FavoriteTileItemView(
                                item: item,
                                hasWallpaper: hasWallpaper,
                                onOpen: {
                                    handleOpen(item)
                                },
                                onOpenInNewTab: {
                                    handleOpenInNewTab(item)
                                }
                            )
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
        .popover(item: $activeFolder) { folder in
            FavoriteFolderPopoverView(
                folder: folder,
                onSelectChild: { child in
                    activeFolder = nil
                    session.navigate(to: child.url)
                },
                onOpenAll: {
                    activeFolder = nil
                    for child in folder.children {
                        _ = session.createTab(url: child.url)
                    }
                }
            )
        }
    }

    private func handleOpen(_ item: FavoriteItem) {
        if item.isFolder {
            activeFolder = item
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

/// Single favorite tile with icon and title label.
private struct FavoriteTileItemView: View {
    let item: FavoriteItem
    let hasWallpaper: Bool
    let onOpen: () -> Void
    let onOpenInNewTab: () -> Void

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
                    } else {
                        // Fallback letter monogram tile
                        RoundedRectangle(cornerRadius: 13.5, style: .continuous)
                            .fill(Color.gray.opacity(0.35))
                            .frame(width: 60, height: 60)
                            .overlay(
                                Text(String(item.title.prefix(1)))
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
                Button("打开文件夹") {
                    onOpen()
                }
                if !item.children.isEmpty {
                    Button("在新标签页中打开全部 (\(item.children.count))") {
                        onOpenInNewTab()
                    }
                }
            } else {
                Button("打开") {
                    onOpen()
                }
                Button("在新标签页中打开") {
                    onOpenInNewTab()
                }
                Divider()
                Button("复制链接") {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(item.url, forType: .string)
                }
            }
        }
        .help(item.fullTitle)
    }
}

/// Popover displayed when clicking a favorite folder.
private struct FavoriteFolderPopoverView: View {
    let folder: FavoriteItem
    let onSelectChild: (FavoriteChild) -> Void
    let onOpenAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text(folder.title)
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                Text("\(folder.children.count) 个书签")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            // List of items in folder
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(folder.children) { child in
                        Button(action: { onSelectChild(child) }) {
                            HStack(spacing: 10) {
                                // Small monogram / badge
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(Color(hex: child.colorHex) ?? Color.gray)
                                    .frame(width: 22, height: 22)
                                    .overlay(
                                        Text(child.iconLetter)
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundColor(.white)
                                    )

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

                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(FolderItemHoverButtonStyle())
                    }
                }
                .padding(.vertical, 6)
            }
            .frame(maxHeight: 260)

            Divider()

            // Footer
            HStack {
                Spacer()
                Button("全部在新标签页中打开") {
                    onOpenAll()
                }
                .font(.system(size: 11, weight: .medium))
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .frame(width: 260)
    }
}

/// Hover style for items inside folder popover.
private struct FolderItemHoverButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovered ? Color.accentColor.opacity(0.12) : SwiftUI.Color.clear)
            )
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

private extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b)
    }
}
