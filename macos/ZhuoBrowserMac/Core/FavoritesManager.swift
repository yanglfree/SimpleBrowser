import AppKit
import Foundation
import SwiftUI

/// Represents a single bookmark link inside a folder.
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

    public init(
        id: String = UUID().uuidString,
        title: String,
        fullTitle: String? = nil,
        url: String = "",
        isFolder: Bool = false,
        iconName: String,
        children: [FavoriteChild] = []
    ) {
        self.id = id
        self.title = title
        self.fullTitle = fullTitle ?? title
        self.url = url
        self.isFolder = isFolder
        self.iconName = iconName
        self.children = children
    }
}

/// Manages default curated favorites matching macOS Safari's home page design.
@MainActor
public final class FavoritesManager: ObservableObject {
    public static let shared = FavoritesManager()

    @Published public private(set) var items: [FavoriteItem] = []
    private var imageCache: [String: NSImage] = [:]

    public init() {
        self.items = Self.defaultFavorites
    }

    /// Loads the icon image from app bundle resources or disk.
    public func iconImage(named name: String) -> NSImage? {
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

    public static let defaultFavorites: [FavoriteItem] = [
        // Row 1
        FavoriteItem(
            title: "设计",
            isFolder: true,
            iconName: "fav_design",
            children: [
                FavoriteChild(title: "Figma", url: "https://www.figma.com", iconLetter: "F", colorHex: "#A259FF"),
                FavoriteChild(title: "Dribbble", url: "https://dribbble.com", iconLetter: "D", colorHex: "#EA4C89"),
                FavoriteChild(title: "Behance", url: "https://www.behance.net", iconLetter: "B", colorHex: "#1769FF"),
                FavoriteChild(title: "Canva", url: "https://www.canva.com", iconLetter: "C", colorHex: "#00C4CC"),
                FavoriteChild(title: "UI Garage", url: "https://uigarage.net", iconLetter: "U", colorHex: "#2563EB"),
                FavoriteChild(title: "Mobbin", url: "https://mobbin.com", iconLetter: "M", colorHex: "#111827"),
                FavoriteChild(title: "Iconfont", url: "https://www.iconfont.cn", iconLetter: "I", colorHex: "#FF5000"),
                FavoriteChild(title: "Material Design", url: "https://m3.material.io", iconLetter: "M", colorHex: "#4285F4"),
                FavoriteChild(title: "Apple HIG", url: "https://developer.apple.com/design/human-interface-guidelines/", iconLetter: "", colorHex: "#1D1D1F")
            ]
        ),
        FavoriteItem(
            title: "Google",
            url: "https://www.google.com",
            iconName: "fav_google"
        ),
        FavoriteItem(
            title: "Android 开发",
            isFolder: true,
            iconName: "fav_android_dev",
            children: [
                FavoriteChild(title: "Android Developers", url: "https://developer.android.com", iconLetter: "A", colorHex: "#3DDC84"),
                FavoriteChild(title: "Kotlin 官方语言", url: "https://kotlinlang.org", iconLetter: "K", colorHex: "#7F52FF"),
                FavoriteChild(title: "Jetpack Compose", url: "https://developer.android.com/jetpack/compose", iconLetter: "C", colorHex: "#4285F4"),
                FavoriteChild(title: "AndroidX 核心库", url: "https://developer.android.com/jetpack/androidx", iconLetter: "X", colorHex: "#34A853"),
                FavoriteChild(title: "GitHub Android", url: "https://github.com/topics/android", iconLetter: "G", colorHex: "#24292E"),
                FavoriteChild(title: "掘金 Android 专栏", url: "https://juejin.cn/tag/Android", iconLetter: "掘", colorHex: "#1E80FF"),
                FavoriteChild(title: "WanAndroid 社区", url: "https://www.wanandroid.com", iconLetter: "玩", colorHex: "#009688"),
                FavoriteChild(title: "StackOverflow Android", url: "https://stackoverflow.com/questions/tagged/android", iconLetter: "S", colorHex: "#F48024"),
                FavoriteChild(title: "微信开放平台", url: "https://open.weixin.qq.com", iconLetter: "微", colorHex: "#07C160")
            ]
        ),
        FavoriteItem(
            title: "iOS 开发",
            isFolder: true,
            iconName: "fav_ios_dev",
            children: [
                FavoriteChild(title: "Apple Developer", url: "https://developer.apple.com", iconLetter: "", colorHex: "#1D1D1F"),
                FavoriteChild(title: "Swift 语言官网", url: "https://www.swift.org", iconLetter: "S", colorHex: "#F05138"),
                FavoriteChild(title: "SwiftUI 官方教程", url: "https://developer.apple.com/xcode/swiftui/", iconLetter: "UI", colorHex: "#0071E3"),
                FavoriteChild(title: "CocoaPods", url: "https://cocoapods.org", iconLetter: "C", colorHex: "#EE3322"),
                FavoriteChild(title: "Swift Package Index", url: "https://swiftpackageindex.com", iconLetter: "P", colorHex: "#FF6B00"),
                FavoriteChild(title: "Objc.io", url: "https://www.objc.io", iconLetter: "O", colorHex: "#10B981"),
                FavoriteChild(title: "Hacking with Swift", url: "https://www.hackingwithswift.com", iconLetter: "H", colorHex: "#EF4444"),
                FavoriteChild(title: "iOS Dev Weekly", url: "https://iosdevweekly.com", iconLetter: "W", colorHex: "#8B5CF6"),
                FavoriteChild(title: "Kodeco (Ray Wenderlich)", url: "https://www.kodeco.com", iconLetter: "K", colorHex: "#0C4B33")
            ]
        ),
        FavoriteItem(
            title: "GitMind",
            url: "https://gitmind.cn",
            iconName: "fav_gitmind"
        ),
        FavoriteItem(
            title: "工具",
            isFolder: true,
            iconName: "fav_tools",
            children: [
                FavoriteChild(title: "GitHub", url: "https://github.com", iconLetter: "G", colorHex: "#24292E"),
                FavoriteChild(title: "V2EX", url: "https://www.v2ex.com", iconLetter: "V", colorHex: "#333333"),
                FavoriteChild(title: "Stack Overflow", url: "https://stackoverflow.com", iconLetter: "S", colorHex: "#F48024"),
                FavoriteChild(title: "Regex101", url: "https://regex101.com", iconLetter: "R", colorHex: "#1E88E5"),
                FavoriteChild(title: "TinyPNG", url: "https://tinypng.com", iconLetter: "T", colorHex: "#8CB83C"),
                FavoriteChild(title: "Carbon 代码截图", url: "https://carbon.now.sh", iconLetter: "C", colorHex: "#121212"),
                FavoriteChild(title: "Can I use", url: "https://caniuse.com", iconLetter: "U", colorHex: "#BA3C24"),
                FavoriteChild(title: "DevDocs API 文档", url: "https://devdocs.io", iconLetter: "D", colorHex: "#3F51B5"),
                FavoriteChild(title: "Whimsical 流程图", url: "https://whimsical.com", iconLetter: "W", colorHex: "#7C3AED")
            ]
        ),
        FavoriteItem(
            title: "28 个 Unix/\nLinux 的命...",
            fullTitle: "28 个 Unix/Linux 的命令行神器",
            url: "https://coolshell.cn/articles/1079.html",
            iconName: "fav_unix_linux"
        ),
        FavoriteItem(
            title: "LeetCode",
            url: "https://leetcode.cn",
            iconName: "fav_leetcode"
        ),
        FavoriteItem(
            title: "Mac OS X: \n启动期间出...",
            fullTitle: "Mac OS X: 启动期间出现的灰色屏幕",
            url: "https://support.apple.com/zh-cn/HT204156",
            iconName: "fav_macos_boot"
        ),
        FavoriteItem(
            title: "searchcode \n| source co...",
            fullTitle: "searchcode | source code search engine",
            url: "https://searchcode.com",
            iconName: "fav_searchcode"
        ),
        FavoriteItem(
            title: "提升 \nUITableView...",
            fullTitle: "提升 UITableView 性能的几种方法",
            url: "https://blog.sunnyxx.com",
            iconName: "fav_uitableview"
        ),
        FavoriteItem(
            title: "MVVM 介绍",
            url: "https://objccn.io/issue-13-1/",
            iconName: "fav_mvvm"
        ),

        // Row 2
        FavoriteItem(
            title: "Snow \nMemory",
            fullTitle: "Snow Memory",
            url: "https://github.com",
            iconName: "fav_snow_memory"
        ),
        FavoriteItem(
            title: "Develop \nApps | And...",
            fullTitle: "Develop Apps | Android Developers",
            url: "https://developer.android.com",
            iconName: "fav_develop_apps"
        ),
        FavoriteItem(
            title: "git - the \nsimple gui...",
            fullTitle: "git - the simple guide",
            url: "https://rogerdudler.github.io/git-guide/index.zh.html",
            iconName: "fav_git_simple"
        ),
        FavoriteItem(
            title: "酷壳 - \nCoolShell.cn",
            fullTitle: "酷壳 - CoolShell.cn",
            url: "https://coolshell.cn",
            iconName: "fav_coolshell"
        ),
        FavoriteItem(
            title: "下载&资源",
            isFolder: true,
            iconName: "fav_download_res",
            children: [
                FavoriteChild(title: "GitHub Releases", url: "https://github.com", iconLetter: "G", colorHex: "#24292E"),
                FavoriteChild(title: "SourceForge 开源", url: "https://sourceforge.net", iconLetter: "S", colorHex: "#EE5F26"),
                FavoriteChild(title: "Internet Archive", url: "https://archive.org", iconLetter: "A", colorHex: "#000000"),
                FavoriteChild(title: "MacUpdate", url: "https://www.macupdate.com", iconLetter: "M", colorHex: "#007AFF"),
                FavoriteChild(title: "V2EX 资源分享", url: "https://www.v2ex.com/go/share", iconLetter: "V", colorHex: "#333333"),
                FavoriteChild(title: "少数派 效率资源", url: "https://sspai.com", iconLetter: "少", colorHex: "#D7191A"),
                FavoriteChild(title: "吾爱破解", url: "https://www.52pojie.cn", iconLetter: "吾", colorHex: "#0076F5"),
                FavoriteChild(title: "Mac 精品软件", url: "https://xclient.info", iconLetter: "X", colorHex: "#10B981"),
                FavoriteChild(title: "少数派 导航", url: "https://nav.sspai.com", iconLetter: "导", colorHex: "#6366F1")
            ]
        ),
        FavoriteItem(
            title: "工作",
            isFolder: true,
            iconName: "fav_work",
            children: [
                FavoriteChild(title: "钉钉", url: "https://www.dingtalk.com", iconLetter: "钉", colorHex: "#0089FF"),
                FavoriteChild(title: "飞书", url: "https://www.feishu.cn", iconLetter: "飞", colorHex: "#00D6B9"),
                FavoriteChild(title: "企业微信", url: "https://work.weixin.qq.com", iconLetter: "企", colorHex: "#2680EB"),
                FavoriteChild(title: "语雀 知识库", url: "https://www.yuque.com", iconLetter: "语", colorHex: "#00B96B"),
                FavoriteChild(title: "Notion", url: "https://www.notion.so", iconLetter: "N", colorHex: "#000000"),
                FavoriteChild(title: "Slack", url: "https://slack.com", iconLetter: "S", colorHex: "#4A154B"),
                FavoriteChild(title: "Jira 协同平台", url: "https://www.atlassian.com/software/jira", iconLetter: "J", colorHex: "#0052CC"),
                FavoriteChild(title: "腾讯会议", url: "https://meeting.tencent.com", iconLetter: "会", colorHex: "#0052D9"),
                FavoriteChild(title: "Google Calendar", url: "https://calendar.google.com", iconLetter: "31", colorHex: "#4285F4")
            ]
        ),
        FavoriteItem(
            title: "写作",
            url: "https://www.zybuluo.com/mdeditor",
            iconName: "fav_writing"
        ),
        FavoriteItem(
            title: "JSON在线\n工具 - 在线...",
            fullTitle: "JSON 在线工具 - 在线解析/格式化",
            url: "https://www.json.cn",
            iconName: "fav_json_tool"
        ),
        FavoriteItem(
            title: "百度",
            url: "https://www.baidu.com",
            iconName: "fav_baidu"
        ),
        FavoriteItem(
            title: "钉钉",
            url: "https://www.dingtalk.com",
            iconName: "fav_dingtalk"
        ),
        FavoriteItem(
            title: "bt 电影下载, \n网盘电影下...",
            fullTitle: "bt 电影下载, 网盘电影下载",
            url: "https://www.bttt.la",
            iconName: "fav_bt_movie"
        ),
        FavoriteItem(
            title: "Instagram",
            url: "https://www.instagram.com",
            iconName: "fav_instagram"
        )
    ]
}
