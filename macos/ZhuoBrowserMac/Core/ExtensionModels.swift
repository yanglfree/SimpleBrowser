import AppKit
import CryptoKit
import Foundation

// MARK: - Extension Source & Access Mode

/// Origin of an installed browser extension.
public enum ExtensionSourceKind: String, Codable, CaseIterable, Equatable, Sendable {
    case builtIn = "built_in"
    case unpacked = "unpacked"
    case packaged = "packaged"
    case userScript = "user_script"

    public var displayName: String {
        switch self {
        case .builtIn:
            return "内置精选"
        case .unpacked:
            return "开发者目录"
        case .packaged:
            return "扩展程序包"
        case .userScript:
            return "用户脚本"
        }
    }
}

/// Chrome-style host access policy per extension.
public enum ExtensionHostAccessMode: String, Codable, CaseIterable, Identifiable, Equatable, Sendable {
    case onAllSites = "on_all_sites"
    case onSpecificSites = "on_specific_sites"
    case onClick = "on_click"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .onAllSites:
            return "在所有匹配的网站上允许"
        case .onSpecificSites:
            return "仅在指定网站上允许"
        case .onClick:
            return "点击扩展图标时生效"
        }
    }

    public var shortLabel: String {
        switch self {
        case .onAllSites:
            return "所有匹配站点"
        case .onSpecificSites:
            return "指定站点"
        case .onClick:
            return "点击时生效"
        }
    }
}

/// Content script injection timing matching Chrome's `run_at`.
public enum ExtensionRunAt: String, Codable, CaseIterable, Equatable, Sendable {
    case documentStart = "document_start"
    case documentEnd = "document_end"
    case documentIdle = "document_idle"
}

// MARK: - Manifest Specifications (MV2 & MV3 Compatible)

/// Represents a Chrome extension's `action` (MV3) or `browser_action` / `page_action` (MV2).
public struct ExtensionActionSpec: Codable, Equatable, Sendable {
    public var defaultTitle: String?
    public var defaultPopup: String?
    public var defaultIconPaths: [String: String]

    public init(
        defaultTitle: String? = nil,
        defaultPopup: String? = nil,
        defaultIconPaths: [String: String] = [:]
    ) {
        self.defaultTitle = defaultTitle
        self.defaultPopup = defaultPopup
        self.defaultIconPaths = defaultIconPaths
    }

    private enum CodingKeys: String, CodingKey {
        case defaultTitle = "default_title"
        case defaultPopup = "default_popup"
        case defaultIcon = "default_icon"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.defaultTitle = try container.decodeIfPresent(String.self, forKey: .defaultTitle)
        self.defaultPopup = try container.decodeIfPresent(String.self, forKey: .defaultPopup)
        if let dict = try? container.decodeIfPresent([String: String].self, forKey: .defaultIcon) {
            self.defaultIconPaths = dict
        } else if let singlePath = try? container.decodeIfPresent(String.self, forKey: .defaultIcon), !singlePath.isEmpty {
            self.defaultIconPaths = ["32": singlePath, "128": singlePath]
        } else {
            self.defaultIconPaths = [:]
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(defaultTitle, forKey: .defaultTitle)
        try container.encodeIfPresent(defaultPopup, forKey: .defaultPopup)
        if !defaultIconPaths.isEmpty {
            try container.encode(defaultIconPaths, forKey: .defaultIcon)
        }
    }
}

/// Represents an entry in `content_scripts`.
public struct ExtensionContentScriptSpec: Codable, Equatable, Sendable {
    public var matches: [String]
    public var excludeMatches: [String]
    public var includeGlobs: [String]
    public var excludeGlobs: [String]
    public var js: [String]
    public var css: [String]
    public var runAt: ExtensionRunAt
    public var allFrames: Bool
    public var matchAboutBlank: Bool
    public var world: String?

    public init(
        matches: [String] = ["<all_urls>"],
        excludeMatches: [String] = [],
        includeGlobs: [String] = [],
        excludeGlobs: [String] = [],
        js: [String] = [],
        css: [String] = [],
        runAt: ExtensionRunAt = .documentIdle,
        allFrames: Bool = false,
        matchAboutBlank: Bool = false,
        world: String? = nil
    ) {
        self.matches = matches
        self.excludeMatches = excludeMatches
        self.includeGlobs = includeGlobs
        self.excludeGlobs = excludeGlobs
        self.js = js
        self.css = css
        self.runAt = runAt
        self.allFrames = allFrames
        self.matchAboutBlank = matchAboutBlank
        self.world = world
    }

    private enum CodingKeys: String, CodingKey {
        case matches
        case excludeMatches = "exclude_matches"
        case includeGlobs = "include_globs"
        case excludeGlobs = "exclude_globs"
        case js
        case css
        case runAt = "run_at"
        case allFrames = "all_frames"
        case matchAboutBlank = "match_about_blank"
        case world
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.matches = (try? container.decodeIfPresent([String].self, forKey: .matches)) ?? []
        self.excludeMatches = (try? container.decodeIfPresent([String].self, forKey: .excludeMatches)) ?? []
        self.includeGlobs = (try? container.decodeIfPresent([String].self, forKey: .includeGlobs)) ?? []
        self.excludeGlobs = (try? container.decodeIfPresent([String].self, forKey: .excludeGlobs)) ?? []
        self.js = (try? container.decodeIfPresent([String].self, forKey: .js)) ?? []
        self.css = (try? container.decodeIfPresent([String].self, forKey: .css)) ?? []
        if let rawRunAt = try? container.decodeIfPresent(String.self, forKey: .runAt),
           let parsed = ExtensionRunAt(rawValue: rawRunAt) {
            self.runAt = parsed
        } else {
            self.runAt = .documentIdle
        }
        self.allFrames = (try? container.decodeIfPresent(Bool.self, forKey: .allFrames)) ?? false
        self.matchAboutBlank = (try? container.decodeIfPresent(Bool.self, forKey: .matchAboutBlank)) ?? false
        self.world = try? container.decodeIfPresent(String.self, forKey: .world)
    }

    /// Checks whether this content script spec should be injected into `urlString`.
    public func matchesURL(_ urlString: String, isMainFrame: Bool = true) -> Bool {
        if !isMainFrame && !allFrames {
            return false
        }
        guard !matches.isEmpty else { return false }
        let matchedPositive = matches.contains { ExtensionMatchPattern.matches(pattern: $0, urlString: urlString) }
        guard matchedPositive else { return false }

        if excludeMatches.contains(where: { ExtensionMatchPattern.matches(pattern: $0, urlString: urlString) }) {
            return false
        }
        if !includeGlobs.isEmpty {
            let globMatched = includeGlobs.contains { ExtensionMatchPattern.matchesGlob(glob: $0, text: urlString) }
            if !globMatched { return false }
        }
        if excludeGlobs.contains(where: { ExtensionMatchPattern.matchesGlob(glob: $0, text: urlString) }) {
            return false
        }
        return true
    }
}

/// Represents `background` in MV3 (`service_worker`) or MV2 (`scripts` / `page`).
public struct ExtensionBackgroundSpec: Codable, Equatable, Sendable {
    public var serviceWorker: String?
    public var scripts: [String]
    public var page: String?
    public var persistent: Bool
    public var type: String?

    public init(
        serviceWorker: String? = nil,
        scripts: [String] = [],
        page: String? = nil,
        persistent: Bool = false,
        type: String? = nil
    ) {
        self.serviceWorker = serviceWorker
        self.scripts = scripts
        self.page = page
        self.persistent = persistent
        self.type = type
    }

    private enum CodingKeys: String, CodingKey {
        case serviceWorker = "service_worker"
        case scripts
        case page
        case persistent
        case type
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.serviceWorker = try? container.decodeIfPresent(String.self, forKey: .serviceWorker)
        self.scripts = (try? container.decodeIfPresent([String].self, forKey: .scripts)) ?? []
        self.page = try? container.decodeIfPresent(String.self, forKey: .page)
        self.persistent = (try? container.decodeIfPresent(Bool.self, forKey: .persistent)) ?? false
        self.type = try? container.decodeIfPresent(String.self, forKey: .type)
    }

    /// Returns all background JS file paths in execution order.
    public var allScriptPaths: [String] {
        var result: [String] = []
        if let sw = serviceWorker, !sw.isEmpty {
            result.append(sw)
        }
        for s in scripts where !s.isEmpty && !result.contains(s) {
            result.append(s)
        }
        return result
    }
}

/// Represents `declarative_net_request.rule_resources` in MV3.
public struct ExtensionDNRRuleResource: Codable, Equatable, Sendable {
    public var id: String
    public var enabled: Bool
    public var path: String

    public init(id: String, enabled: Bool = true, path: String) {
        self.id = id
        self.enabled = enabled
        self.path = path
    }
}

/// Parsed representation of a Chrome Extension `manifest.json` (MV2 & MV3).
public struct ExtensionManifest: Codable, Equatable, Sendable {
    public var manifestVersion: Int
    public var name: String
    public var shortName: String?
    public var version: String
    public var description: String?
    public var author: String?
    public var homepageURL: String?
    public var defaultLocale: String?
    public var icons: [String: String]
    public var permissions: [String]
    public var hostPermissions: [String]
    public var optionalPermissions: [String]
    public var action: ExtensionActionSpec?
    public var contentScripts: [ExtensionContentScriptSpec]
    public var background: ExtensionBackgroundSpec?
    public var optionsPage: String?
    public var optionsOpenInTab: Bool
    public var webAccessibleResources: [String]
    public var dnrRuleResources: [ExtensionDNRRuleResource]

    public init(
        manifestVersion: Int = 3,
        name: String,
        shortName: String? = nil,
        version: String = "1.0.0",
        description: String? = nil,
        author: String? = nil,
        homepageURL: String? = nil,
        defaultLocale: String? = nil,
        icons: [String: String] = [:],
        permissions: [String] = [],
        hostPermissions: [String] = [],
        optionalPermissions: [String] = [],
        action: ExtensionActionSpec? = nil,
        contentScripts: [ExtensionContentScriptSpec] = [],
        background: ExtensionBackgroundSpec? = nil,
        optionsPage: String? = nil,
        optionsOpenInTab: Bool = true,
        webAccessibleResources: [String] = [],
        dnrRuleResources: [ExtensionDNRRuleResource] = []
    ) {
        self.manifestVersion = manifestVersion
        self.name = name
        self.shortName = shortName
        self.version = version
        self.description = description
        self.author = author
        self.homepageURL = homepageURL
        self.defaultLocale = defaultLocale
        self.icons = icons
        self.permissions = permissions
        self.hostPermissions = hostPermissions
        self.optionalPermissions = optionalPermissions
        self.action = action
        self.contentScripts = contentScripts
        self.background = background
        self.optionsPage = optionsPage
        self.optionsOpenInTab = optionsOpenInTab
        self.webAccessibleResources = webAccessibleResources
        self.dnrRuleResources = dnrRuleResources
    }

    private enum CodingKeys: String, CodingKey {
        case manifestVersion = "manifest_version"
        case name
        case shortName = "short_name"
        case version
        case description
        case author
        case homepageURL = "homepage_url"
        case defaultLocale = "default_locale"
        case icons
        case permissions
        case hostPermissions = "host_permissions"
        case optionalPermissions = "optional_permissions"
        case action
        case browserAction = "browser_action"
        case pageAction = "page_action"
        case contentScripts = "content_scripts"
        case background
        case optionsPage = "options_page"
        case optionsUI = "options_ui"
        case webAccessibleResources = "web_accessible_resources"
        case declarativeNetRequest = "declarative_net_request"
    }

    private struct OptionsUISpec: Codable {
        var page: String?
        var openInTab: Bool?
        private enum CodingKeys: String, CodingKey {
            case page
            case openInTab = "open_in_tab"
        }
    }

    private struct MV3WebAccessibleEntry: Codable {
        var resources: [String]?
    }

    private struct DNRWrapper: Codable {
        var ruleResources: [ExtensionDNRRuleResource]?
        private enum CodingKeys: String, CodingKey {
            case ruleResources = "rule_resources"
        }
    }

    private struct AuthorWrapper: Codable {
        var name: String?
        var email: String?
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.manifestVersion = (try? container.decodeIfPresent(Int.self, forKey: .manifestVersion)) ?? 3
        self.name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? "未命名扩展"
        self.shortName = try? container.decodeIfPresent(String.self, forKey: .shortName)
        self.version = (try? container.decodeIfPresent(String.self, forKey: .version)) ?? "1.0.0"
        self.description = try? container.decodeIfPresent(String.self, forKey: .description)
        if let authorStr = try? container.decodeIfPresent(String.self, forKey: .author) {
            self.author = authorStr
        } else if let authorObj = try? container.decodeIfPresent(AuthorWrapper.self, forKey: .author) {
            self.author = authorObj.name ?? authorObj.email
        } else {
            self.author = nil
        }
        self.homepageURL = try? container.decodeIfPresent(String.self, forKey: .homepageURL)
        self.defaultLocale = try? container.decodeIfPresent(String.self, forKey: .defaultLocale)
        self.icons = (try? container.decodeIfPresent([String: String].self, forKey: .icons)) ?? [:]

        let rawPermissions = (try? container.decodeIfPresent([String].self, forKey: .permissions)) ?? []
        let explicitHostPerms = (try? container.decodeIfPresent([String].self, forKey: .hostPermissions)) ?? []
        var apiPerms: [String] = []
        var hostPerms: [String] = explicitHostPerms
        for perm in rawPermissions {
            if perm == "<all_urls>" || perm.contains("://") {
                if !hostPerms.contains(perm) {
                    hostPerms.append(perm)
                }
            } else {
                apiPerms.append(perm)
            }
        }
        self.permissions = apiPerms
        self.hostPermissions = hostPerms
        self.optionalPermissions = (try? container.decodeIfPresent([String].self, forKey: .optionalPermissions)) ?? []

        if let mv3Action = try? container.decodeIfPresent(ExtensionActionSpec.self, forKey: .action) {
            self.action = mv3Action
        } else if let mv2BrowserAction = try? container.decodeIfPresent(ExtensionActionSpec.self, forKey: .browserAction) {
            self.action = mv2BrowserAction
        } else if let mv2PageAction = try? container.decodeIfPresent(ExtensionActionSpec.self, forKey: .pageAction) {
            self.action = mv2PageAction
        } else {
            self.action = nil
        }

        self.contentScripts = (try? container.decodeIfPresent([ExtensionContentScriptSpec].self, forKey: .contentScripts)) ?? []
        self.background = try? container.decodeIfPresent(ExtensionBackgroundSpec.self, forKey: .background)

        if let optsUI = try? container.decodeIfPresent(OptionsUISpec.self, forKey: .optionsUI), let page = optsUI.page {
            self.optionsPage = page
            self.optionsOpenInTab = optsUI.openInTab ?? true
        } else if let optsPage = try? container.decodeIfPresent(String.self, forKey: .optionsPage) {
            self.optionsPage = optsPage
            self.optionsOpenInTab = true
        } else {
            self.optionsPage = nil
            self.optionsOpenInTab = true
        }

        if let mv3Resources = try? container.decodeIfPresent([MV3WebAccessibleEntry].self, forKey: .webAccessibleResources) {
            self.webAccessibleResources = mv3Resources.flatMap { $0.resources ?? [] }
        } else if let mv2Resources = try? container.decodeIfPresent([String].self, forKey: .webAccessibleResources) {
            self.webAccessibleResources = mv2Resources
        } else {
            self.webAccessibleResources = []
        }

        if let dnr = try? container.decodeIfPresent(DNRWrapper.self, forKey: .declarativeNetRequest) {
            self.dnrRuleResources = dnr.ruleResources ?? []
        } else {
            self.dnrRuleResources = []
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(manifestVersion, forKey: .manifestVersion)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(shortName, forKey: .shortName)
        try container.encode(version, forKey: .version)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(author, forKey: .author)
        try container.encodeIfPresent(homepageURL, forKey: .homepageURL)
        try container.encodeIfPresent(defaultLocale, forKey: .defaultLocale)
        if !icons.isEmpty {
            try container.encode(icons, forKey: .icons)
        }
        try container.encode(permissions, forKey: .permissions)
        if !hostPermissions.isEmpty {
            try container.encode(hostPermissions, forKey: .hostPermissions)
        }
        if !optionalPermissions.isEmpty {
            try container.encode(optionalPermissions, forKey: .optionalPermissions)
        }
        try container.encodeIfPresent(action, forKey: .action)
        if !contentScripts.isEmpty {
            try container.encode(contentScripts, forKey: .contentScripts)
        }
        try container.encodeIfPresent(background, forKey: .background)
        if let optionsPage {
            try container.encode(OptionsUISpec(page: optionsPage, openInTab: optionsOpenInTab), forKey: .optionsUI)
            try container.encode(optionsPage, forKey: .optionsPage)
        }
        if !webAccessibleResources.isEmpty {
            try container.encode(webAccessibleResources, forKey: .webAccessibleResources)
        }
        if !dnrRuleResources.isEmpty {
            try container.encode(DNRWrapper(ruleResources: dnrRuleResources), forKey: .declarativeNetRequest)
        }
    }

    /// Preferred relative icon path for toolbar/manager display.
    public var preferredIconRelativePath: String? {
        let iconTable = icons.isEmpty ? (action?.defaultIconPaths ?? [:]) : icons
        for key in ["128", "64", "48", "32", "24", "16"] {
            if let path = iconTable[key], !path.isEmpty {
                return path
            }
        }
        return iconTable.values.first
    }

    /// Human-readable summary of requested permissions for the security inspector.
    public var humanReadablePermissions: [String] {
        var descriptions: [String] = []
        let allHosts = Set(hostPermissions + contentScripts.flatMap(\.matches))
        if allHosts.contains("<all_urls>") || allHosts.contains("*://*/*") || allHosts.contains("http://*/*") {
            descriptions.append("读取和更改您在所有网站上的数据")
        } else if !allHosts.isEmpty {
            let sample = Array(allHosts.prefix(3)).joined(separator: "、")
            descriptions.append("读取和更改您在指定网站上的数据 (\(sample))")
        }
        for perm in permissions {
            switch perm {
            case "storage":
                descriptions.append("在本地存储扩展配置与偏好数据")
            case "tabs":
                descriptions.append("访问浏览器标签页的标题与网址状态")
            case "activeTab":
                descriptions.append("在您点击扩展时临时访问当前活跃标签页")
            case "scripting":
                descriptions.append("向当前页面动态注入脚本或自定义样式")
            case "contextMenus":
                descriptions.append("在网页右键上下文菜单中添加快捷操作")
            case "notifications":
                descriptions.append("显示桌面通知提示")
            case "declarativeNetRequest", "declarativeNetRequestWithHostAccess", "webRequest":
                descriptions.append("拦截或优化网页网络请求规则")
            case "clipboardWrite", "clipboardRead":
                descriptions.append("读写系统剪贴板文本内容")
            default:
                break
            }
        }
        if descriptions.isEmpty {
            descriptions.append("无需特殊系统权限（仅在您调用时运行）")
        }
        return descriptions
    }
}

// MARK: - Installed Extension & Action State

/// Runtime state for `chrome.action` / `chrome.browserAction` badges and popups.
public struct ExtensionActionState: Codable, Equatable, Sendable {
    public var defaultBadgeText: String
    public var tabBadgeText: [String: String]
    public var defaultBadgeBackgroundColor: String
    public var tabBadgeBackgroundColor: [String: String]
    public var titleOverride: String?
    public var popupOverride: String?
    public var isActionEnabled: Bool

    public init(
        defaultBadgeText: String = "",
        tabBadgeText: [String: String] = [:],
        defaultBadgeBackgroundColor: String = "#2563EB",
        tabBadgeBackgroundColor: [String: String] = [:],
        titleOverride: String? = nil,
        popupOverride: String? = nil,
        isActionEnabled: Bool = true
    ) {
        self.defaultBadgeText = defaultBadgeText
        self.tabBadgeText = tabBadgeText
        self.defaultBadgeBackgroundColor = defaultBadgeBackgroundColor
        self.tabBadgeBackgroundColor = tabBadgeBackgroundColor
        self.titleOverride = titleOverride
        self.popupOverride = popupOverride
        self.isActionEnabled = isActionEnabled
    }

    public func badgeText(forTabID tabID: String?) -> String {
        if let tabID, let specific = tabBadgeText[tabID] {
            return specific
        }
        return defaultBadgeText
    }

    public func badgeColorHex(forTabID tabID: String?) -> String {
        if let tabID, let specific = tabBadgeBackgroundColor[tabID], !specific.isEmpty {
            return specific
        }
        return defaultBadgeBackgroundColor
    }
}

/// Represents a context menu item registered via `chrome.contextMenus.create`.
public struct ExtensionContextMenuItem: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var extensionID: String
    public var menuItemID: String
    public var title: String
    public var contexts: [String]
    public var documentURLPatterns: [String]

    public init(
        extensionID: String,
        menuItemID: String,
        title: String,
        contexts: [String] = ["all"],
        documentURLPatterns: [String] = []
    ) {
        self.id = "\(extensionID)::\(menuItemID)"
        self.extensionID = extensionID
        self.menuItemID = menuItemID
        self.title = title
        self.contexts = contexts
        self.documentURLPatterns = documentURLPatterns
    }
}

/// Complete record of an installed extension in ZhuoBrowser Mac.
public struct InstalledExtension: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public var manifest: ExtensionManifest
    public var sourceKind: ExtensionSourceKind
    public var directoryPath: String
    public var isEnabled: Bool
    public var isPinnedToToolbar: Bool
    public var allowInPrivateBrowsing: Bool
    public var hostAccessMode: ExtensionHostAccessMode
    public var customAllowedHosts: [String]
    public var blockedHosts: [String]
    public var installedAt: Date
    public var updatedAt: Date
    public var sfSymbolFallback: String
    public var accentColorHex: String
    public var actionState: ExtensionActionState
    public var lastLoadError: String?

    public init(
        id: String,
        manifest: ExtensionManifest,
        sourceKind: ExtensionSourceKind,
        directoryPath: String,
        isEnabled: Bool = true,
        isPinnedToToolbar: Bool = true,
        allowInPrivateBrowsing: Bool = false,
        hostAccessMode: ExtensionHostAccessMode = .onAllSites,
        customAllowedHosts: [String] = [],
        blockedHosts: [String] = [],
        installedAt: Date = Date(),
        updatedAt: Date = Date(),
        sfSymbolFallback: String = "puzzlepiece.extension.fill",
        accentColorHex: String = "#3B82F6",
        actionState: ExtensionActionState = ExtensionActionState(),
        lastLoadError: String? = nil
    ) {
        self.id = id
        self.manifest = manifest
        self.sourceKind = sourceKind
        self.directoryPath = directoryPath
        self.isEnabled = isEnabled
        self.isPinnedToToolbar = isPinnedToToolbar
        self.allowInPrivateBrowsing = allowInPrivateBrowsing
        self.hostAccessMode = hostAccessMode
        self.customAllowedHosts = customAllowedHosts
        self.blockedHosts = blockedHosts
        self.installedAt = installedAt
        self.updatedAt = updatedAt
        self.sfSymbolFallback = sfSymbolFallback
        self.accentColorHex = accentColorHex
        self.actionState = actionState
        self.lastLoadError = lastLoadError
    }

    public var displayTitle: String {
        if let override = actionState.titleOverride, !override.isEmpty {
            return override
        }
        if let actionTitle = manifest.action?.defaultTitle, !actionTitle.isEmpty {
            return actionTitle
        }
        return manifest.name
    }

    /// Relative path to the popup HTML if configured.
    public var effectivePopupRelativePath: String? {
        if let override = actionState.popupOverride {
            return override.isEmpty ? nil : override
        }
        guard let popup = manifest.action?.defaultPopup, !popup.isEmpty else {
            return nil
        }
        return popup
    }

    /// URL in the `zhuo-extension://` scheme for the popup page.
    public var popupURL: URL? {
        guard let rel = effectivePopupRelativePath else { return nil }
        let cleaned = rel.hasPrefix("/") ? String(rel.dropFirst()) : rel
        return URL(string: "zhuo-extension://\(id)/\(cleaned)")
    }

    /// URL in the `zhuo-extension://` scheme for the options page.
    public var optionsURL: URL? {
        guard let rel = manifest.optionsPage, !rel.isEmpty else { return nil }
        let cleaned = rel.hasPrefix("/") ? String(rel.dropFirst()) : rel
        return URL(string: "zhuo-extension://\(id)/\(cleaned)")
    }

    /// Generates a deterministic 32-character Chrome-style extension ID (`a` through `p`) from a seed string.
    public static func makeChromeExtensionID(from seed: String) -> String {
        let digest = SHA256.hash(data: Data(seed.utf8))
        let alphabet: [Character] = Array("abcdefghijklmnop")
        var chars: [Character] = []
        chars.reserveCapacity(32)
        for byte in digest.prefix(16) {
            let high = Int((byte >> 4) & 0x0F)
            let low = Int(byte & 0x0F)
            chars.append(alphabet[high])
            chars.append(alphabet[low])
        }
        return String(chars)
    }

    /// Checks whether this extension is allowed to run automatically on `urlString`.
    public func canRunOn(url urlString: String, isPrivateTab: Bool, hasActiveTabGrant: Bool = false) -> Bool {
        guard isEnabled else { return false }
        if isPrivateTab && !allowInPrivateBrowsing {
            return false
        }
        if URLPolicy.isHomeURL(urlString)
            || urlString.hasPrefix("zhuo://")
            || urlString.hasPrefix("chrome://")
            || urlString.hasPrefix("zhuo-extension://") {
            return false
        }
        let host = URLPolicy.rawHost(urlString)
        if !host.isEmpty {
            let isBlocked = blockedHosts.contains { blocked in
                let normalized = blocked.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                return host == normalized || host.hasSuffix("." + normalized)
            }
            if isBlocked { return false }
        }
        if hasActiveTabGrant {
            return true
        }
        switch hostAccessMode {
        case .onAllSites:
            return true
        case .onSpecificSites:
            guard !host.isEmpty else { return false }
            return customAllowedHosts.contains { allowed in
                let normalized = allowed.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                return host == normalized || host.hasSuffix("." + normalized)
            }
        case .onClick:
            return false
        }
    }
}

// MARK: - Chrome Match Pattern & Glob Engine

/// Evaluates Chrome Extension Match Patterns (`<all_urls>`, `*://*.example.com/*`, etc.) and globs.
public enum ExtensionMatchPattern {
    private static let allURLSchemes: Set<String> = ["http", "https", "file", "ws", "wss"]

    /// Validates whether `pattern` conforms to Chrome's match pattern syntax.
    public static func isValid(pattern: String) -> Bool {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "<all_urls>" || trimmed == "*://*/*" {
            return true
        }
        guard let schemeRange = trimmed.range(of: "://") else {
            return false
        }
        let scheme = String(trimmed[..<schemeRange.lowerBound]).lowercased()
        guard ["*", "http", "https", "file", "ws", "wss", "zhuo-extension", "chrome-extension"].contains(scheme) else {
            return false
        }
        let rest = String(trimmed[schemeRange.upperBound...])
        guard let slashIndex = rest.firstIndex(of: "/") else {
            return false
        }
        let host = String(rest[..<slashIndex])
        if scheme != "file" && host.isEmpty {
            return false
        }
        if host.contains("*") && host != "*" && !host.hasPrefix("*.") {
            return false
        }
        return true
    }

    /// Evaluates whether `urlString` matches a Chrome match pattern.
    public static func matches(pattern: String, urlString: String) -> Bool {
        let trimmedPattern = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPattern.isEmpty, let url = URL(string: urlString), let urlScheme = url.scheme?.lowercased() else {
            return false
        }

        if trimmedPattern == "<all_urls>" {
            return allURLSchemes.contains(urlScheme)
        }

        guard let schemeRange = trimmedPattern.range(of: "://") else {
            return false
        }
        let patternScheme = String(trimmedPattern[..<schemeRange.lowerBound]).lowercased()
        let rest = String(trimmedPattern[schemeRange.upperBound...])
        guard let slashIndex = rest.firstIndex(of: "/") else {
            return false
        }
        let patternHost = String(rest[..<slashIndex]).lowercased()
        let patternPath = String(rest[slashIndex...])

        // 1. Scheme check
        if patternScheme == "*" {
            guard urlScheme == "http" || urlScheme == "https" else { return false }
        } else if patternScheme != urlScheme {
            return false
        }

        // 2. Host check
        if patternScheme != "file" {
            let urlHost = (url.host ?? "").lowercased()
            guard !urlHost.isEmpty else { return false }
            if patternHost == "*" {
                // matches any non-empty host
            } else if patternHost.hasPrefix("*.") {
                let baseDomain = String(patternHost.dropFirst(2))
                guard urlHost == baseDomain || urlHost.hasSuffix("." + baseDomain) else {
                    return false
                }
            } else {
                // Strip optional port in patternHost if present
                let cleanPatternHost = patternHost.split(separator: ":").first.map(String.init) ?? patternHost
                guard urlHost == cleanPatternHost else { return false }
            }
        }

        // 3. Path (+ query) check
        if patternPath == "/*" || patternPath == "*" {
            return true
        }
        let rawPath = url.path.isEmpty ? "/" : url.path
        let fullPathAndQuery: String
        if let query = url.query, !query.isEmpty {
            fullPathAndQuery = "\(rawPath)?\(query)"
        } else {
            fullPathAndQuery = rawPath
        }
        return wildcardMatch(pattern: patternPath, text: fullPathAndQuery)
            || wildcardMatch(pattern: patternPath, text: rawPath)
    }

    /// Evaluates UserScript / Chrome `include_globs` & `exclude_globs` patterns.
    public static func matchesGlob(glob: String, text: String) -> Bool {
        wildcardMatch(pattern: glob, text: text)
    }

    /// Fast non-backtracking wildcard matcher supporting `*` and `?`.
    public static func wildcardMatch(pattern: String, text: String) -> Bool {
        let pChars = Array(pattern.utf8)
        let tChars = Array(text.utf8)
        var pIdx = 0
        var tIdx = 0
        var starIdx = -1
        var matchIdx = 0

        while tIdx < tChars.count {
            if pIdx < pChars.count && (pChars[pIdx] == UInt8(ascii: "?") || pChars[pIdx] == tChars[tIdx]) {
                pIdx += 1
                tIdx += 1
            } else if pIdx < pChars.count && pChars[pIdx] == UInt8(ascii: "*") {
                starIdx = pIdx
                matchIdx = tIdx
                pIdx += 1
            } else if starIdx != -1 {
                pIdx = starIdx + 1
                matchIdx += 1
                tIdx = matchIdx
            } else {
                return false
            }
        }

        while pIdx < pChars.count && pChars[pIdx] == UInt8(ascii: "*") {
            pIdx += 1
        }

        return pIdx == pChars.count
    }
}

// MARK: - i18n Catalog (`_locales/<locale>/messages.json`)

/// Resolves `__MSG_key__` placeholders and `chrome.i18n.getMessage()` calls.
public struct ExtensionI18nCatalog: Sendable {
    public let messages: [String: String]

    public init(messages: [String: String] = [:]) {
        var normalized: [String: String] = [:]
        for (k, v) in messages {
            normalized[k.lowercased()] = v
        }
        self.messages = normalized
    }

    /// Loads `_locales` messages from an extension directory on disk.
    public static func load(from extensionDirectory: URL, defaultLocale: String?) -> ExtensionI18nCatalog {
        let localesDir = extensionDirectory.appendingPathComponent("_locales", isDirectory: true)
        guard FileManager.default.fileExists(atPath: localesDir.path) else {
            return ExtensionI18nCatalog()
        }

        var candidateLocales: [String] = ["zh_CN", "zh", "en_US", "en"]
        if let defaultLocale, !defaultLocale.isEmpty {
            candidateLocales.insert(defaultLocale, at: 0)
        }

        var merged: [String: String] = [:]
        for locale in candidateLocales.reversed() {
            let fileURL = localesDir
                .appendingPathComponent(locale, isDirectory: true)
                .appendingPathComponent("messages.json")
            guard let data = try? Data(contentsOf: fileURL),
                  let rawDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            for (key, value) in rawDict {
                if let entry = value as? [String: Any],
                   let msg = entry["message"] as? String {
                    merged[key.lowercased()] = msg
                }
            }
        }
        return ExtensionI18nCatalog(messages: merged)
    }

    public func getMessage(_ key: String, substitutions: [String] = []) -> String {
        guard var template = messages[key.lowercased()] else { return "" }
        for (idx, sub) in substitutions.enumerated() {
            template = template.replacingOccurrences(of: "$\(idx + 1)", with: sub)
        }
        return template
    }

    /// Replaces all `__MSG_name__` tokens inside `input`.
    public func resolvePlaceholders(in input: String) -> String {
        guard input.contains("__MSG_"), !messages.isEmpty else { return input }
        var result = input
        let pattern = "__MSG_([A-Za-z0-9_@]+)__"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return input }
        let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
        for match in matches.reversed() {
            guard let fullRange = Range(match.range(at: 0), in: result),
                  let keyRange = Range(match.range(at: 1), in: result) else {
                continue
            }
            let key = String(result[keyRange]).lowercased()
            if let replacement = messages[key] {
                result.replaceSubrange(fullRange, with: replacement)
            }
        }
        return result
    }

    public func applying(to manifest: ExtensionManifest) -> ExtensionManifest {
        guard !messages.isEmpty else { return manifest }
        var copy = manifest
        copy.name = resolvePlaceholders(in: copy.name)
        if let shortName = copy.shortName {
            copy.shortName = resolvePlaceholders(in: shortName)
        }
        if let desc = copy.description {
            copy.description = resolvePlaceholders(in: desc)
        }
        if var action = copy.action, let title = action.defaultTitle {
            action.defaultTitle = resolvePlaceholders(in: title)
            copy.action = action
        }
        return copy
    }
}

// MARK: - UserScript (`// ==UserScript==`) Parser & Converter

/// Metadata extracted from a Tampermonkey / Greasemonkey `.user.js` file.
public struct ParsedUserScript: Equatable, Sendable {
    public var name: String
    public var namespace: String?
    public var version: String
    public var description: String
    public var author: String?
    public var matches: [String]
    public var excludeMatches: [String]
    public var includeGlobs: [String]
    public var excludeGlobs: [String]
    public var runAt: ExtensionRunAt
    public var allFrames: Bool
    public var grants: [String]
    public var sourceCode: String

    public init(
        name: String,
        namespace: String? = nil,
        version: String = "1.0.0",
        description: String = "",
        author: String? = nil,
        matches: [String] = ["<all_urls>"],
        excludeMatches: [String] = [],
        includeGlobs: [String] = [],
        excludeGlobs: [String] = [],
        runAt: ExtensionRunAt = .documentEnd,
        allFrames: Bool = true,
        grants: [String] = [],
        sourceCode: String
    ) {
        self.name = name
        self.namespace = namespace
        self.version = version
        self.description = description
        self.author = author
        self.matches = matches
        self.excludeMatches = excludeMatches
        self.includeGlobs = includeGlobs
        self.excludeGlobs = excludeGlobs
        self.runAt = runAt
        self.allFrames = allFrames
        self.grants = grants
        self.sourceCode = sourceCode
    }
}

public enum UserScriptParser {
    /// Parses a `.user.js` script and extracts its metadata block and executable code.
    public static func parse(scriptContent: String, fallbackName: String = "自定义用户脚本") -> ParsedUserScript {
        var name: String = fallbackName
        var localizedZhName: String?
        var namespace: String?
        var version = "1.0.0"
        var description = "通过 UserScript 导入的浏览器增强脚本"
        var localizedZhDesc: String?
        var author: String?
        var matches: [String] = []
        var excludeMatches: [String] = []
        var includeGlobs: [String] = []
        var excludeGlobs: [String] = []
        var runAt: ExtensionRunAt = .documentEnd
        var noFrames = false
        var grants: [String] = []

        var insideHeader = false
        for rawLine in scriptContent.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("// ==UserScript==") {
                insideHeader = true
                continue
            }
            if line.hasPrefix("// ==/UserScript==") {
                break
            }
            guard insideHeader, line.hasPrefix("//") else { continue }
            let body = line.dropFirst(2).trimmingCharacters(in: .whitespaces)
            guard body.hasPrefix("@") else { continue }

            let parts = body.split(maxSplits: 1, whereSeparator: { $0.isWhitespace })
            guard let rawKey = parts.first else { continue }
            let key = String(rawKey).lowercased()
            let value = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : ""

            switch key {
            case "@name:zh-cn", "@name:zh":
                if !value.isEmpty { localizedZhName = value }
            case "@name":
                if !value.isEmpty { name = value }
            case "@namespace":
                if !value.isEmpty { namespace = value }
            case "@version":
                if !value.isEmpty { version = value }
            case "@description:zh-cn", "@description:zh":
                if !value.isEmpty { localizedZhDesc = value }
            case "@description":
                if !value.isEmpty { description = value }
            case "@author":
                if !value.isEmpty { author = value }
            case "@match":
                if ExtensionMatchPattern.isValid(pattern: value) {
                    matches.append(value)
                } else if !value.isEmpty {
                    includeGlobs.append(value)
                }
            case "@include":
                if ExtensionMatchPattern.isValid(pattern: value) {
                    matches.append(value)
                } else if !value.isEmpty {
                    includeGlobs.append(value)
                }
            case "@exclude", "@exclude-match":
                if ExtensionMatchPattern.isValid(pattern: value) {
                    excludeMatches.append(value)
                } else if !value.isEmpty {
                    excludeGlobs.append(value)
                }
            case "@run-at":
                let normalized = value.replacingOccurrences(of: "-", with: "_").lowercased()
                if let parsedRunAt = ExtensionRunAt(rawValue: normalized) {
                    runAt = parsedRunAt
                }
            case "@noframes":
                noFrames = true
            case "@grant":
                if !value.isEmpty && value != "none" {
                    grants.append(value)
                }
            default:
                break
            }
        }

        if let localizedZhName {
            name = localizedZhName
        }
        if let localizedZhDesc {
            description = localizedZhDesc
        }
        if matches.isEmpty {
            matches = ["<all_urls>"]
        }

        return ParsedUserScript(
            name: name,
            namespace: namespace,
            version: version,
            description: description,
            author: author,
            matches: matches,
            excludeMatches: excludeMatches,
            includeGlobs: includeGlobs,
            excludeGlobs: excludeGlobs,
            runAt: runAt,
            allFrames: !noFrames,
            grants: grants,
            sourceCode: scriptContent
        )
    }

    /// Builds an `ExtensionManifest` for a parsed UserScript (with optional companion CSS).
    public static func buildManifest(
        from script: ParsedUserScript,
        jsFilename: String = "userscript.js",
        cssFilename: String? = nil,
        popupFilename: String? = nil
    ) -> ExtensionManifest {
        let cs = ExtensionContentScriptSpec(
            matches: script.matches,
            excludeMatches: script.excludeMatches,
            includeGlobs: script.includeGlobs,
            excludeGlobs: script.excludeGlobs,
            js: script.sourceCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [] : [jsFilename],
            css: cssFilename.map { [$0] } ?? [],
            runAt: script.runAt,
            allFrames: script.allFrames
        )
        let action = ExtensionActionSpec(
            defaultTitle: script.name,
            defaultPopup: popupFilename
        )
        return ExtensionManifest(
            manifestVersion: 3,
            name: script.name,
            version: script.version,
            description: script.description,
            author: script.author,
            permissions: ["storage", "activeTab", "scripting"],
            hostPermissions: script.matches,
            action: action,
            contentScripts: [cs]
        )
    }
}

// MARK: - CRX (CRX2 / CRX3) & ZIP Package Unpacker

public enum ExtensionPackageError: LocalizedError, Equatable {
    case fileNotFound(String)
    case invalidCRXHeader
    case zipExtractionFailed(String)
    case manifestMissing
    case invalidManifest(String)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "找不到扩展文件：\(path)"
        case .invalidCRXHeader:
            return "无效的 Chrome 扩展包 (.crx)：文件头损坏或格式不受支持"
        case .zipExtractionFailed(let detail):
            return "解压扩展程序包失败：\(detail)"
        case .manifestMissing:
            return "扩展目录中未找到 manifest.json"
        case .invalidManifest(let detail):
            return "解析 manifest.json 失败：\(detail)"
        }
    }
}

/// Unpacks Chrome `.crx` (v2 & v3) and `.zip` archives into a local directory.
public enum CRXPackageUnpacker {
    /// Extracts the inner ZIP byte slice from a Chrome `.crx` file `Data`.
    /// Supports both CRX2 (`Cr24` + version 2 + pubkeyLen + sigLen) and CRX3 (`Cr24` + version 3 + headerLen).
    public static func extractZIPData(fromCRX data: Data) throws -> Data {
        // Also accept raw ZIP data directly (`PK\x03\x04`)
        if data.count >= 4,
           data[data.startIndex] == 0x50,
           data[data.startIndex + 1] == 0x4B,
           data[data.startIndex + 2] == 0x03,
           data[data.startIndex + 3] == 0x04 {
            return data
        }

        guard data.count >= 12 else {
            throw ExtensionPackageError.invalidCRXHeader
        }
        let magic = String(decoding: data.prefix(4), as: UTF8.self)
        guard magic == "Cr24" else {
            throw ExtensionPackageError.invalidCRXHeader
        }

        let version = readUInt32LE(data, offset: 4)
        let zipStartOffset: Int
        switch version {
        case 2:
            guard data.count >= 16 else {
                throw ExtensionPackageError.invalidCRXHeader
            }
            let pubKeyLength = Int(readUInt32LE(data, offset: 8))
            let signatureLength = Int(readUInt32LE(data, offset: 12))
            zipStartOffset = 16 + pubKeyLength + signatureLength
        case 3:
            let headerLength = Int(readUInt32LE(data, offset: 8))
            zipStartOffset = 12 + headerLength
        default:
            throw ExtensionPackageError.invalidCRXHeader
        }

        guard zipStartOffset > 0, zipStartOffset < data.count else {
            throw ExtensionPackageError.invalidCRXHeader
        }

        let zipSlice = Data(data.suffix(from: data.startIndex + zipStartOffset))
        guard zipSlice.count >= 4,
              zipSlice[zipSlice.startIndex] == 0x50,
              zipSlice[zipSlice.startIndex + 1] == 0x4B else {
            throw ExtensionPackageError.invalidCRXHeader
        }
        return zipSlice
    }

    /// Unpacks a `.crx` or `.zip` archive file into `destinationDirectory`.
    /// Returns the directory that directly contains `manifest.json`.
    public static func unpackArchive(at archiveURL: URL, into destinationDirectory: URL) throws -> URL {
        guard FileManager.default.fileExists(atPath: archiveURL.path) else {
            throw ExtensionPackageError.fileNotFound(archiveURL.path)
        }
        let rawData = try Data(contentsOf: archiveURL)
        let zipData = try extractZIPData(fromCRX: rawData)

        let fm = FileManager.default
        if fm.fileExists(atPath: destinationDirectory.path) {
            try? fm.removeItem(at: destinationDirectory)
        }
        try fm.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        let tempZipURL = destinationDirectory.appendingPathComponent("_package.zip")
        try zipData.write(to: tempZipURL, options: .atomic)
        defer { try? fm.removeItem(at: tempZipURL) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", tempZipURL.path, destinationDirectory.path]
        let errPipe = Pipe()
        process.standardError = errPipe
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errMsg = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "未知解压错误"
            throw ExtensionPackageError.zipExtractionFailed(errMsg.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return try locateExtensionRoot(in: destinationDirectory)
    }

    /// Finds the directory containing `manifest.json` (handles archives that wrap files in a single top-level folder).
    public static func locateExtensionRoot(in directory: URL) throws -> URL {
        let fm = FileManager.default
        let directManifest = directory.appendingPathComponent("manifest.json")
        if fm.fileExists(atPath: directManifest.path) {
            return directory
        }

        if let children = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for child in children where child.lastPathComponent != "__MACOSX" {
                let nestedManifest = child.appendingPathComponent("manifest.json")
                if fm.fileExists(atPath: nestedManifest.path) {
                    return child
                }
            }
        }
        throw ExtensionPackageError.manifestMissing
    }

    private static func readUInt32LE(_ data: Data, offset: Int) -> UInt32 {
        let base = data.startIndex + offset
        let b0 = UInt32(data[base])
        let b1 = UInt32(data[base + 1]) << 8
        let b2 = UInt32(data[base + 2]) << 16
        let b3 = UInt32(data[base + 3]) << 24
        return b0 | b1 | b2 | b3
    }
}
