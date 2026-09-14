import Foundation

enum SettingsSection: String, CaseIterable {
    case pro
    case appearance
    case search
    case gestures
    case blocking
    case addressBar
    case startPage
    case tabs
    case library
    case downloads
    case privacy
    case about
}

struct SettingsSearchEntry: Equatable {
    let section: SettingsSection
    let label: String
    let keywords: String
}

enum SettingsSearchPolicy {
    static let entries: [SettingsSearchEntry] = [
        .init(section: .pro, label: "卓阅 Pro", keywords: "升级 激活 订阅 购买 恢复 支持 联系"),
        .init(section: .appearance, label: "应用外观", keywords: "主题 系统 深色 浅色"),
        .init(section: .appearance, label: "网页外观", keywords: "网页 深色 暗色 模式 图片 视频"),
        .init(section: .appearance, label: "网页最小字号", keywords: "字体 大字 无障碍"),
        .init(section: .search, label: "搜索引擎", keywords: "默认 必应 百度 谷歌 Google Bing DuckDuckGo"),
        .init(section: .search, label: "自定义搜索模板", keywords: "搜索 URL 地址 %s"),
        .init(section: .gestures, label: "启用手势", keywords: "滑动 操作"),
        .init(section: .gestures, label: "上滑打开页面工具", keywords: "动作 面板"),
        .init(section: .gestures, label: "横滑切换标签页", keywords: "地址栏 左右滑动"),
        .init(section: .gestures, label: "长按打开内容拦截", keywords: "广告 面板"),
        .init(section: .gestures, label: "滚动时自动隐藏工具栏", keywords: "自动 隐藏"),
        .init(section: .gestures, label: "恢复手势默认设置", keywords: "重置"),
        .init(section: .blocking, label: "拦截广告与跟踪器", keywords: "内容保护 隐私 防护 追踪"),
        .init(section: .blocking, label: "规则强度", keywords: "页面 清理 标准 严格"),
        .init(section: .blocking, label: "更新拦截规则", keywords: "订阅 EasyList"),
        .init(section: .blocking, label: "网站权限与允许列表", keywords: "相机 麦克风 位置 恢复拦截"),
        .init(section: .addressBar, label: "显示搜索建议", keywords: "地址栏 本地 历史 收藏 快捷项"),
        .init(section: .startPage, label: "显示快捷站点", keywords: "起始页 主页 常访问 数量 管理"),
        .init(section: .startPage, label: "显示首页背景", keywords: "开启 关闭 保留 来源"),
        .init(section: .startPage, label: "首页背景", keywords: "每日美图 自定义照片 内置图片 竖屏 横屏 山色 静巷 河岸 拱廊 屋顶 木纹"),
        .init(section: .tabs, label: "自动归档", keywords: "标签页 清理 过期"),
        .init(section: .tabs, label: "活动网页数量", keywords: "WebView 存活 内存"),
        .init(section: .tabs, label: "标签页提醒", keywords: "软限制 阈值 数量"),
        .init(section: .library, label: "书签与历史", keywords: "收藏 阅读清单"),
        .init(section: .library, label: "历史保留时长", keywords: "清除 记录"),
        .init(section: .library, label: "导入导出 HTML 书签", keywords: "文件 迁移"),
        .init(section: .downloads, label: "下载内容", keywords: "文件 任务"),
        .init(section: .downloads, label: "同时下载", keywords: "并发 任务 数量"),
        .init(section: .downloads, label: "大文件提醒", keywords: "阈值 流量 移动网络 MB"),
        .init(section: .downloads, label: "仅 Wi-Fi 下载", keywords: "WIFI 网络"),
        .init(section: .downloads, label: "下载完成提醒", keywords: "通知"),
        .init(section: .privacy, label: "关闭标签时清除 Cookie", keywords: "隐私 数据"),
        .init(section: .privacy, label: "本机性能与使用统计", keywords: "遥测 崩溃 日志"),
        .init(section: .privacy, label: "清除浏览数据", keywords: "历史 Cookie 缓存 权限"),
        .init(section: .about, label: "意见反馈", keywords: "用户反馈 问题 建议 联系"),
        .init(section: .about, label: "版本", keywords: "关于 应用 build"),
    ]

    static func visibleSections(for rawQuery: String) -> Set<SettingsSection> {
        let query = normalized(rawQuery)
        guard !query.isEmpty else {
            return Set(SettingsSection.allCases)
        }
        return Set(entries.lazy.filter { matches($0, normalizedQuery: query) }.map(\.section))
    }

    static func initialQuery(for section: SettingsSection) -> String {
        entries.first(where: { $0.section == section })?.label ?? ""
    }

    static func matches(_ entry: SettingsSearchEntry, query rawQuery: String) -> Bool {
        matches(entry, normalizedQuery: normalized(rawQuery))
    }

    private static func matches(_ entry: SettingsSearchEntry, normalizedQuery query: String) -> Bool {
        guard !query.isEmpty else { return true }
        let searchable = normalized("\(entry.label) \(entry.keywords)")
        if searchable.contains(query) {
            return true
        }

        let compactQuery = compact(query)
        let compactSearchable = compact(searchable)
        if compactSearchable.contains(compactQuery) {
            return true
        }

        guard compactQuery.unicodeScalars.contains(where: isHanCharacter) else {
            return false
        }
        return compactQuery.allSatisfy { compactSearchable.contains($0) }
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }

    private static func compact(_ value: String) -> String {
        value.filter { !$0.isWhitespace }
    }

    private static func isHanCharacter(_ scalar: UnicodeScalar) -> Bool {
        (0x3400...0x4DBF).contains(scalar.value)
            || (0x4E00...0x9FFF).contains(scalar.value)
            || (0xF900...0xFAFF).contains(scalar.value)
    }
}
