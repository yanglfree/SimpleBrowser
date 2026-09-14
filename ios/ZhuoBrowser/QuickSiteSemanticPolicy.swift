import Foundation

struct QuickSiteSemanticTheme: Equatable {
    let systemImageName: String
    let backgroundHex: String
}

enum QuickSiteSemanticPolicy {
    static func theme(title: String, url: String) -> QuickSiteSemanticTheme? {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedURL = url.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if titleContains(normalizedTitle, anyOf: ["下载", "download", "离线", "安装包", "安装"])
            || urlContains(normalizedURL, anyOf: ["download", "/apk", "/hap", "browser://downloads"]) {
            return QuickSiteSemanticTheme(systemImageName: "arrow.down.to.line", backgroundHex: "#1D4ED8")
        }

        if titleContains(normalizedTitle, anyOf: ["历史", "history", "足迹", "记录"])
            || urlContains(normalizedURL, anyOf: ["history", "browser://history"]) {
            return QuickSiteSemanticTheme(systemImageName: "clock", backgroundHex: "#EA580C")
        }

        if titleContains(normalizedTitle, anyOf: ["书签", "bookmark", "收藏", "favorite"])
            || urlContains(normalizedURL, anyOf: ["bookmarks", "favorites"]) {
            return QuickSiteSemanticTheme(systemImageName: "bookmark", backgroundHex: "#D97706")
        }

        if titleContains(normalizedTitle, anyOf: ["设置", "setting", "配置", "选项", "preference"])
            || normalizedURL.contains("settings") {
            return QuickSiteSemanticTheme(systemImageName: "gearshape", backgroundHex: "#475569")
        }

        if titleContains(normalizedTitle, anyOf: ["阅读", "reader", "文章", "博客", "blog", "小说"])
            || urlContains(normalizedURL, anyOf: ["reader", "blog"]) {
            return QuickSiteSemanticTheme(systemImageName: "text.alignleft", backgroundHex: "#059669")
        }

        if titleContains(normalizedTitle, anyOf: ["搜索", "search", "探索", "发现"])
            || normalizedURL.contains("search") {
            return QuickSiteSemanticTheme(systemImageName: "magnifyingglass", backgroundHex: "#0284C7")
        }

        if titleContains(normalizedTitle, anyOf: ["首页", "主页", "导航", "portal"])
            || normalizedTitle == "home"
            || normalizedURL == "browser://home" {
            return QuickSiteSemanticTheme(systemImageName: "house", backgroundHex: "#0D9488")
        }

        if titleContains(normalizedTitle, anyOf: ["隐私", "无痕", "私密", "安全", "incognito", "private"]) {
            return QuickSiteSemanticTheme(systemImageName: "eyeglasses", backgroundHex: "#334155")
        }

        if titleContains(normalizedTitle, anyOf: ["分享", "社区", "share", "community"]) {
            return QuickSiteSemanticTheme(systemImageName: "square.and.arrow.up", backgroundHex: "#7C3AED")
        }

        return nil
    }

    private static func titleContains(_ title: String, anyOf candidates: [String]) -> Bool {
        candidates.contains(where: title.contains)
    }

    private static func urlContains(_ url: String, anyOf candidates: [String]) -> Bool {
        candidates.contains(where: url.contains)
    }
}
