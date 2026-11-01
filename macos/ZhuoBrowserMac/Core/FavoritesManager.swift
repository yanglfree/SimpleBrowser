import AppKit
import Foundation
import SwiftUI

/// Represents a single bookmark link inside a folder on the Start Page.
public struct FavoriteChild: Identifiable, Hashable {
    public let id: String
    public let title: String
    public let url: String
    public let iconLetter: String
    public let colorHex: String

    public init(
        id: String = UUID().uuidString,
        title: String,
        url: String,
        iconLetter: String = "",
        colorHex: String = "#4B5563"
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.iconLetter = iconLetter.isEmpty ? String(title.prefix(1)) : iconLetter
        self.colorHex = colorHex
    }
}

/// Represents an item in the start page Favorites section (either a link or a folder).
public struct FavoriteItem: Identifiable, Hashable {
    public let id: String
    public let title: String
    public let fullTitle: String
    public let url: String
    public let isFolder: Bool
    public let iconName: String
    public let children: [FavoriteChild]
    public let sortOrder: Int

    public init(
        id: String = UUID().uuidString,
        title: String,
        fullTitle: String? = nil,
        url: String = "",
        isFolder: Bool = false,
        iconName: String,
        children: [FavoriteChild] = [],
        sortOrder: Int = 0
    ) {
        self.id = id
        self.title = title
        self.fullTitle = fullTitle ?? title
        self.url = url
        self.isFolder = isFolder
        self.iconName = iconName
        self.children = children
        self.sortOrder = sortOrder
    }
}

/// Manages curated and user-customized favorites on the Start Page, synchronized with `BrowserSession` bookmarks and folders.
@MainActor
public final class FavoritesManager: ObservableObject {
    public static let shared = FavoritesManager()

    @Published public private(set) var items: [FavoriteItem] = []
    private var imageCache: [String: NSImage] = [:]

    public init() {
        self.items = Self.defaultFavorites
    }

    /// Synchronizes the Start Page Favorites tiles with the live bookmark folders and entries.
    public func sync(folders: [BookmarkFolder], bookmarks: [BookmarkEntry]) {
        self.items = Self.rebuildItems(folders: folders, bookmarks: bookmarks)
    }

    /// Resets the Start Page Favorites to the curated defaults.
    public func resetToDefaults() {
        self.items = Self.defaultFavorites
    }

    /// Converts the curated default Favorites into structured `BookmarkFolder` and `BookmarkEntry` collections.
    nonisolated public static func seedDefaultLibrary() -> (folders: [BookmarkFolder], bookmarks: [BookmarkEntry]) {
        var folders: [BookmarkFolder] = []
        var bookmarks: [BookmarkEntry] = []
        let baseTimestamp: TimeInterval = 1_730_000_000

        for (index, item) in defaultFavorites.enumerated() {
            let itemTimestamp = baseTimestamp - Double(index * 60)
            if item.isFolder {
                let folder = BookmarkFolder(
                    id: item.id,
                    name: item.title,
                    iconName: item.iconName,
                    createdAt: itemTimestamp,
                    sortOrder: index,
                    isPinnedToStartPage: true
                )
                folders.append(folder)

                for (childIndex, child) in item.children.enumerated() {
                    let childEntry = BookmarkEntry(
                        id: child.id,
                        title: child.title,
                        shortTitle: nil,
                        url: child.url,
                        folderID: folder.id,
                        createdAt: itemTimestamp - Double(childIndex + 1),
                        updatedAt: itemTimestamp - Double(childIndex + 1),
                        isPinnedToStartPage: false,
                        iconName: "",
                        iconLetter: child.iconLetter,
                        colorHex: child.colorHex,
                        sortOrder: childIndex
                    )
                    bookmarks.append(childEntry)
                }
            } else {
                let rootEntry = BookmarkEntry(
                    id: item.id,
                    title: item.fullTitle,
                    shortTitle: item.title != item.fullTitle ? item.title : nil,
                    url: item.url,
                    folderID: nil,
                    createdAt: itemTimestamp,
                    updatedAt: itemTimestamp,
                    isPinnedToStartPage: true,
                    iconName: item.iconName,
                    iconLetter: String(item.fullTitle.prefix(1)).uppercased(),
                    colorHex: LibraryPolicy.colorHex(for: item.fullTitle),
                    sortOrder: index
                )
                bookmarks.append(rootEntry)
            }
        }

        return (folders, bookmarks)
    }

    /// Rebuilds the Start Page `FavoriteItem` grid from the given folders and bookmarks.
    nonisolated public static func rebuildItems(
        folders: [BookmarkFolder],
        bookmarks: [BookmarkEntry]
    ) -> [FavoriteItem] {
        var combined: [FavoriteItem] = []

        for folder in folders where folder.isPinnedToStartPage {
            let folderBookmarks = bookmarks
                .filter { $0.folderID == folder.id }
                .sorted { lhs, rhs in
                    if lhs.sortOrder != rhs.sortOrder {
                        return lhs.sortOrder < rhs.sortOrder
                    }
                    return lhs.createdAt > rhs.createdAt
                }
            let children = folderBookmarks.map { bm in
                FavoriteChild(
                    id: bm.id,
                    title: bm.displayTitle,
                    url: bm.url,
                    iconLetter: bm.resolvedIconLetter,
                    colorHex: bm.colorHex
                )
            }
            combined.append(
                FavoriteItem(
                    id: folder.id,
                    title: folder.name,
                    fullTitle: folder.name,
                    url: "",
                    isFolder: true,
                    iconName: folder.iconName,
                    children: children,
                    sortOrder: folder.sortOrder
                )
            )
        }

        let pinnedRootBookmarks = bookmarks.filter { $0.folderID == nil && $0.isPinnedToStartPage }
        for bm in pinnedRootBookmarks {
            combined.append(
                FavoriteItem(
                    id: bm.id,
                    title: bm.startPageTileTitle,
                    fullTitle: bm.displayTitle,
                    url: bm.url,
                    isFolder: false,
                    iconName: bm.iconName,
                    children: [],
                    sortOrder: bm.sortOrder
                )
            )
        }

        return combined.sorted { lhs, rhs in
            if lhs.sortOrder != rhs.sortOrder {
                return lhs.sortOrder < rhs.sortOrder
            }
            return lhs.id < rhs.id
        }
    }

    /// Loads the icon image from app bundle resources or disk.
    public func iconImage(named name: String) -> NSImage? {
        guard !name.isEmpty else { return nil }
        if let cached = imageCache[name] {
            return cached
        }

        // 1. Try bundle subdirectory "favorites"
        if let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "favorites") ??
            Bundle.main.url(forResource: name, withExtension: "png") {
            if let image = NSImage(contentsOf: url) {
                imageCache[name] = image
                return image
            }
        }

        // 2. Try bundle resourcePath directly
        if let resPath = Bundle.main.resourcePath {
            let directURL = URL(fileURLWithPath: resPath)
                .appendingPathComponent("favorites")
                .appendingPathComponent("\(name).png")
            if let image = NSImage(contentsOf: directURL) {
                imageCache[name] = image
                return image
            }
        }

        // 3. Fallback to developer workspace relative path (useful during development / preview)
        let localPath = "macos/ZhuoBrowserMac/Resources/favorites/\(name).png"
        if FileManager.default.fileExists(atPath: localPath),
           let image = NSImage(contentsOfFile: localPath) {
            imageCache[name] = image
            return image
        }

        return nil
    }

    // MARK: - Curated Default Favorites (Matching Screenshot 1:1)

    nonisolated public static let defaultFavorites: [FavoriteItem] = [
        // Row 1
        FavoriteItem(
            id: "folder-design",
            title: "设计",
            isFolder: true,
            iconName: "fav_design",
            children: [
                FavoriteChild(id: "bm-design-1", title: "Figma", url: "https://www.figma.com", iconLetter: "F", colorHex: "#A259FF"),
                FavoriteChild(id: "bm-design-2", title: "Dribbble", url: "https://dribbble.com", iconLetter: "D", colorHex: "#EA4C89"),
                FavoriteChild(id: "bm-design-3", title: "Behance", url: "https://www.behance.net", iconLetter: "B", colorHex: "#1769FF"),
                FavoriteChild(id: "bm-design-4", title: "Canva", url: "https://www.canva.com", iconLetter: "C", colorHex: "#00C4CC"),
                FavoriteChild(id: "bm-design-5", title: "UI Garage", url: "https://uigarage.net", iconLetter: "U", colorHex: "#2563EB"),
                FavoriteChild(id: "bm-design-6", title: "Mobbin", url: "https://mobbin.com", iconLetter: "M", colorHex: "#111827"),
                FavoriteChild(id: "bm-design-7", title: "Iconfont", url: "https://www.iconfont.cn", iconLetter: "I", colorHex: "#FF5000"),
                FavoriteChild(id: "bm-design-8", title: "Material Design", url: "https://m3.material.io", iconLetter: "M", colorHex: "#4285F4"),
                FavoriteChild(id: "bm-design-9", title: "Apple HIG", url: "https://developer.apple.com/design/human-interface-guidelines/", iconLetter: "", colorHex: "#1D1D1F")
            ],
            sortOrder: 0
        ),
        FavoriteItem(
            id: "bm-root-google",
            title: "Google",
            url: "https://www.google.com",
            iconName: "fav_google",
            sortOrder: 1
        ),
        FavoriteItem(
            id: "folder-android-dev",
            title: "Android 开发",
            isFolder: true,
            iconName: "fav_android_dev",
            children: [
                FavoriteChild(id: "bm-android-1", title: "Android Developers", url: "https://developer.android.com", iconLetter: "A", colorHex: "#3DDC84"),
                FavoriteChild(id: "bm-android-2", title: "Kotlin 官方语言", url: "https://kotlinlang.org", iconLetter: "K", colorHex: "#7F52FF"),
                FavoriteChild(id: "bm-android-3", title: "Jetpack Compose", url: "https://developer.android.com/jetpack/compose", iconLetter: "C", colorHex: "#4285F4"),
                FavoriteChild(id: "bm-android-4", title: "AndroidX 核心库", url: "https://developer.android.com/jetpack/androidx", iconLetter: "X", colorHex: "#34A853"),
                FavoriteChild(id: "bm-android-5", title: "GitHub Android", url: "https://github.com/topics/android", iconLetter: "G", colorHex: "#24292E"),
                FavoriteChild(id: "bm-android-6", title: "掘金 Android 专栏", url: "https://juejin.cn/tag/Android", iconLetter: "掘", colorHex: "#1E80FF"),
                FavoriteChild(id: "bm-android-7", title: "WanAndroid 社区", url: "https://www.wanandroid.com", iconLetter: "玩", colorHex: "#009688"),
                FavoriteChild(id: "bm-android-8", title: "StackOverflow Android", url: "https://stackoverflow.com/questions/tagged/android", iconLetter: "S", colorHex: "#F48024"),
                FavoriteChild(id: "bm-android-9", title: "微信开放平台", url: "https://open.weixin.qq.com", iconLetter: "微", colorHex: "#07C160")
            ],
            sortOrder: 2
        ),
        FavoriteItem(
            id: "folder-ios-dev",
            title: "iOS 开发",
            isFolder: true,
            iconName: "fav_ios_dev",
            children: [
                FavoriteChild(id: "bm-ios-1", title: "Apple Developer", url: "https://developer.apple.com", iconLetter: "", colorHex: "#1D1D1F"),
                FavoriteChild(id: "bm-ios-2", title: "Swift 语言官网", url: "https://www.swift.org", iconLetter: "S", colorHex: "#F05138"),
                FavoriteChild(id: "bm-ios-3", title: "SwiftUI 官方教程", url: "https://developer.apple.com/xcode/swiftui/", iconLetter: "UI", colorHex: "#0071E3"),
                FavoriteChild(id: "bm-ios-4", title: "CocoaPods", url: "https://cocoapods.org", iconLetter: "C", colorHex: "#EE3322"),
                FavoriteChild(id: "bm-ios-5", title: "Swift Package Index", url: "https://swiftpackageindex.com", iconLetter: "P", colorHex: "#FF6B00"),
                FavoriteChild(id: "bm-ios-6", title: "Objc.io", url: "https://www.objc.io", iconLetter: "O", colorHex: "#10B981"),
                FavoriteChild(id: "bm-ios-7", title: "Hacking with Swift", url: "https://www.hackingwithswift.com", iconLetter: "H", colorHex: "#EF4444"),
                FavoriteChild(id: "bm-ios-8", title: "iOS Dev Weekly", url: "https://iosdevweekly.com", iconLetter: "W", colorHex: "#8B5CF6"),
                FavoriteChild(id: "bm-ios-9", title: "Kodeco (Ray Wenderlich)", url: "https://www.kodeco.com", iconLetter: "K", colorHex: "#0C4B33")
            ],
            sortOrder: 3
        ),
        FavoriteItem(
            id: "bm-root-gitmind",
            title: "GitMind",
            url: "https://gitmind.cn",
            iconName: "fav_gitmind",
            sortOrder: 4
        ),
        FavoriteItem(
            id: "folder-tools",
            title: "工具",
            isFolder: true,
            iconName: "fav_tools",
            children: [
                FavoriteChild(id: "bm-tools-1", title: "GitHub", url: "https://github.com", iconLetter: "G", colorHex: "#24292E"),
                FavoriteChild(id: "bm-tools-2", title: "V2EX", url: "https://www.v2ex.com", iconLetter: "V", colorHex: "#333333"),
                FavoriteChild(id: "bm-tools-3", title: "Stack Overflow", url: "https://stackoverflow.com", iconLetter: "S", colorHex: "#F48024"),
                FavoriteChild(id: "bm-tools-4", title: "Regex101", url: "https://regex101.com", iconLetter: "R", colorHex: "#1E88E5"),
                FavoriteChild(id: "bm-tools-5", title: "TinyPNG", url: "https://tinypng.com", iconLetter: "T", colorHex: "#8CB83C"),
                FavoriteChild(id: "bm-tools-6", title: "Carbon 代码截图", url: "https://carbon.now.sh", iconLetter: "C", colorHex: "#121212"),
                FavoriteChild(id: "bm-tools-7", title: "Can I use", url: "https://caniuse.com", iconLetter: "U", colorHex: "#BA3C24"),
                FavoriteChild(id: "bm-tools-8", title: "DevDocs API 文档", url: "https://devdocs.io", iconLetter: "D", colorHex: "#3F51B5"),
                FavoriteChild(id: "bm-tools-9", title: "Whimsical 流程图", url: "https://whimsical.com", iconLetter: "W", colorHex: "#7C3AED")
            ],
            sortOrder: 5
        ),
        FavoriteItem(
            id: "bm-root-unix-linux",
            title: "28 个 Unix/\nLinux 的命...",
            fullTitle: "28 个 Unix/Linux 的命令行神器",
            url: "https://coolshell.cn/articles/1079.html",
            iconName: "fav_unix_linux",
            sortOrder: 6
        ),
        FavoriteItem(
            id: "bm-root-leetcode",
            title: "LeetCode",
            url: "https://leetcode.cn",
            iconName: "fav_leetcode",
            sortOrder: 7
        ),
        FavoriteItem(
            id: "bm-root-macos-boot",
            title: "Mac OS X: \n启动期间出...",
            fullTitle: "Mac OS X: 启动期间出现的灰色屏幕",
            url: "https://support.apple.com/zh-cn/HT204156",
            iconName: "fav_macos_boot",
            sortOrder: 8
        ),
        FavoriteItem(
            id: "bm-root-searchcode",
            title: "searchcode \n| source co...",
            fullTitle: "searchcode | source code search engine",
            url: "https://searchcode.com",
            iconName: "fav_searchcode",
            sortOrder: 9
        ),
        FavoriteItem(
            id: "bm-root-uitableview",
            title: "提升 \nUITableView...",
            fullTitle: "提升 UITableView 性能的几种方法",
            url: "https://blog.sunnyxx.com",
            iconName: "fav_uitableview",
            sortOrder: 10
        ),
        FavoriteItem(
            id: "bm-root-mvvm",
            title: "MVVM 介绍",
            url: "https://objccn.io/issue-13-1/",
            iconName: "fav_mvvm",
            sortOrder: 11
        ),

        // Row 2
        FavoriteItem(
            id: "bm-root-snow-memory",
            title: "Snow \nMemory",
            fullTitle: "Snow Memory",
            url: "https://github.com",
            iconName: "fav_snow_memory",
            sortOrder: 12
        ),
        FavoriteItem(
            id: "bm-root-develop-apps",
            title: "Develop \nApps | And...",
            fullTitle: "Develop Apps | Android Developers",
            url: "https://developer.android.com",
            iconName: "fav_develop_apps",
            sortOrder: 13
        ),
        FavoriteItem(
            id: "bm-root-git-simple",
            title: "git - the \nsimple gui...",
            fullTitle: "git - the simple guide",
            url: "https://rogerdudler.github.io/git-guide/index.zh.html",
            iconName: "fav_git_simple",
            sortOrder: 14
        ),
        FavoriteItem(
            id: "bm-root-coolshell",
            title: "酷壳 - \nCoolShell.cn",
            fullTitle: "酷壳 - CoolShell.cn",
            url: "https://coolshell.cn",
            iconName: "fav_coolshell",
            sortOrder: 15
        ),
        FavoriteItem(
            id: "folder-download-res",
            title: "下载&资源",
            isFolder: true,
            iconName: "fav_download_res",
            children: [
                FavoriteChild(id: "bm-dl-1", title: "GitHub Releases", url: "https://github.com", iconLetter: "G", colorHex: "#24292E"),
                FavoriteChild(id: "bm-dl-2", title: "SourceForge 开源", url: "https://sourceforge.net", iconLetter: "S", colorHex: "#EE5F26"),
                FavoriteChild(id: "bm-dl-3", title: "Internet Archive", url: "https://archive.org", iconLetter: "A", colorHex: "#000000"),
                FavoriteChild(id: "bm-dl-4", title: "MacUpdate", url: "https://www.macupdate.com", iconLetter: "M", colorHex: "#007AFF"),
                FavoriteChild(id: "bm-dl-5", title: "V2EX 资源分享", url: "https://www.v2ex.com/go/share", iconLetter: "V", colorHex: "#333333"),
                FavoriteChild(id: "bm-dl-6", title: "少数派 效率资源", url: "https://sspai.com", iconLetter: "少", colorHex: "#D7191A"),
                FavoriteChild(id: "bm-dl-7", title: "吾爱破解", url: "https://www.52pojie.cn", iconLetter: "吾", colorHex: "#0076F5"),
                FavoriteChild(id: "bm-dl-8", title: "Mac 精品软件", url: "https://xclient.info", iconLetter: "X", colorHex: "#10B981"),
                FavoriteChild(id: "bm-dl-9", title: "少数派 导航", url: "https://nav.sspai.com", iconLetter: "导", colorHex: "#6366F1")
            ],
            sortOrder: 16
        ),
        FavoriteItem(
            id: "folder-work",
            title: "工作",
            isFolder: true,
            iconName: "fav_work",
            children: [
                FavoriteChild(id: "bm-work-1", title: "钉钉", url: "https://www.dingtalk.com", iconLetter: "钉", colorHex: "#0089FF"),
                FavoriteChild(id: "bm-work-2", title: "飞书", url: "https://www.feishu.cn", iconLetter: "飞", colorHex: "#00D6B9"),
                FavoriteChild(id: "bm-work-3", title: "企业微信", url: "https://work.weixin.qq.com", iconLetter: "企", colorHex: "#2680EB"),
                FavoriteChild(id: "bm-work-4", title: "语雀 知识库", url: "https://www.yuque.com", iconLetter: "语", colorHex: "#00B96B"),
                FavoriteChild(id: "bm-work-5", title: "Notion", url: "https://www.notion.so", iconLetter: "N", colorHex: "#000000"),
                FavoriteChild(id: "bm-work-6", title: "Slack", url: "https://slack.com", iconLetter: "S", colorHex: "#4A154B"),
                FavoriteChild(id: "bm-work-7", title: "Jira 协同平台", url: "https://www.atlassian.com/software/jira", iconLetter: "J", colorHex: "#0052CC"),
                FavoriteChild(id: "bm-work-8", title: "腾讯会议", url: "https://meeting.tencent.com", iconLetter: "会", colorHex: "#0052D9"),
                FavoriteChild(id: "bm-work-9", title: "Google Calendar", url: "https://calendar.google.com", iconLetter: "31", colorHex: "#4285F4")
            ],
            sortOrder: 17
        ),
        FavoriteItem(
            id: "bm-root-writing",
            title: "写作",
            url: "https://www.zybuluo.com/mdeditor",
            iconName: "fav_writing",
            sortOrder: 18
        ),
        FavoriteItem(
            id: "bm-root-json-tool",
            title: "JSON在线\n工具 - 在线...",
            fullTitle: "JSON 在线工具 - 在线解析/格式化",
            url: "https://www.json.cn",
            iconName: "fav_json_tool",
            sortOrder: 19
        ),
        FavoriteItem(
            id: "bm-root-baidu",
            title: "百度",
            url: "https://www.baidu.com",
            iconName: "fav_baidu",
            sortOrder: 20
        ),
        FavoriteItem(
            id: "bm-root-dingtalk",
            title: "钉钉",
            url: "https://www.dingtalk.com",
            iconName: "fav_dingtalk",
            sortOrder: 21
        ),
        FavoriteItem(
            id: "bm-root-bt-movie",
            title: "bt 电影下载, \n网盘电影下...",
            fullTitle: "bt 电影下载, 网盘电影下载",
            url: "https://www.bttt.la",
            iconName: "fav_bt_movie",
            sortOrder: 22
        ),
        FavoriteItem(
            id: "bm-root-instagram",
            title: "Instagram",
            url: "https://www.instagram.com",
            iconName: "fav_instagram",
            sortOrder: 23
        )
    ]
}
