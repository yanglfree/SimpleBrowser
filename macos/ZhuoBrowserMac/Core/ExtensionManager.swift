import AppKit
import Foundation
import WebKit

/// Central manager for ZhuoBrowser Mac's Chrome-compatible extension & UserScript system.
public final class ExtensionManager: ObservableObject {
    public static let shared = ExtensionManager()

    @Published public private(set) var extensions: [InstalledExtension] = []
    @Published public var isDeveloperMode: Bool {
        didSet {
            guard isDeveloperMode != oldValue else { return }
            persistRegistry()
        }
    }
    @Published public var isShowingExtensionManager: Bool = false
    @Published public var isShowingCreatorSheet: Bool = false
    @Published public var isShowingToolbarPuzzlePopover: Bool = false
    @Published public var activePopupExtensionID: String? = nil
    @Published public var inspectingExtensionID: String? = nil
    @Published public private(set) var contextMenuItems: [ExtensionContextMenuItem] = []
    @Published public var lastOperationBanner: String? = nil

    public weak var session: BrowserSession?

    public let rootDirectory: URL
    private let registryFileURL: URL
    private let storageDirectory: URL
    private let installedPackagesDirectory: URL
    private let persistsToDisk: Bool

    /// Per-extension storage areas: `[extensionID: [areaName: [key: Any]]]`
    private var storageMemoryCache: [String: [String: [String: Any]]] = [:]
    /// Per-tab temporary `activeTab` grants: `[tabID: Set<extensionID>]`
    private var activeTabGrants: [String: Set<String>] = [:]
    /// Stable mapping between `BrowserTab.id` (UUID string) and Chrome numeric `tab.id` (`Int`).
    private var tabStringToNumeric: [String: Int] = [:]
    private var tabNumericToString: [Int: String] = [:]
    private var nextNumericTabID: Int = 101
    /// Cached `NSImage` icons keyed by `extensionID`.
    private var iconCache: [String: NSImage] = [:]
    /// Weak reference to the currently visible popup `WKWebView` so messages can be routed to it.
    public weak var activePopupWebView: WKWebView?

    private struct PersistedRegistry: Codable {
        var isDeveloperMode: Bool
        var extensions: [InstalledExtension]
    }

    public init(
        rootDirectory: URL? = nil,
        persistsToDisk: Bool = !RuntimeEnvironment.isRunningUnitTests
    ) {
        self.persistsToDisk = persistsToDisk
        let resolvedRoot: URL
        if let rootDirectory {
            resolvedRoot = rootDirectory
        } else if persistsToDisk,
                  let appSupport = try? FileManager.default.url(
                      for: .applicationSupportDirectory,
                      in: .userDomainMask,
                      appropriateFor: nil,
                      create: true
                  ) {
            resolvedRoot = appSupport
                .appendingPathComponent("ZhuoBrowserMac", isDirectory: true)
                .appendingPathComponent("Extensions", isDirectory: true)
        } else {
            resolvedRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent("ZhuoBrowserMacExtensionsTests-\(UUID().uuidString)", isDirectory: true)
        }

        self.rootDirectory = resolvedRoot
        self.registryFileURL = resolvedRoot.appendingPathComponent("extensions_registry.json")
        self.storageDirectory = resolvedRoot.appendingPathComponent("Storage", isDirectory: true)
        self.installedPackagesDirectory = resolvedRoot.appendingPathComponent("Installed", isDirectory: true)
        self.isDeveloperMode = false

        try? FileManager.default.createDirectory(at: resolvedRoot, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: installedPackagesDirectory, withIntermediateDirectories: true)

        loadInitialExtensions()
    }

    // MARK: - Computed Collections

    public var enabledExtensions: [InstalledExtension] {
        extensions.filter(\.isEnabled)
    }

    public var pinnedToolbarExtensions: [InstalledExtension] {
        extensions.filter { $0.isEnabled && $0.isPinnedToToolbar }
    }

    public func extensionItem(forID id: String) -> InstalledExtension? {
        extensions.first { $0.id == id }
    }

    public func icon(for extensionItem: InstalledExtension) -> NSImage? {
        if let cached = iconCache[extensionItem.id] {
            return cached
        }
        guard let relPath = extensionItem.manifest.preferredIconRelativePath else {
            return nil
        }
        let iconURL = URL(fileURLWithPath: extensionItem.directoryPath, isDirectory: true)
            .appendingPathComponent(relPath)
        guard let img = NSImage(contentsOf: iconURL) else {
            return nil
        }
        iconCache[extensionItem.id] = img
        return img
    }

    // MARK: - Initialization & Registry Persistence

    private func loadInitialExtensions() {
        let builtIns = BuiltInExtensions.materializeAll(in: rootDirectory)
        guard let data = try? Data(contentsOf: registryFileURL),
              let savedRegistry = try? JSONDecoder().decode(PersistedRegistry.self, from: data) else {
            self.extensions = builtIns
            persistRegistry()
            return
        }

        self.isDeveloperMode = savedRegistry.isDeveloperMode
        var merged: [InstalledExtension] = []
        let savedByID = Dictionary(uniqueKeysWithValues: savedRegistry.extensions.map { ($0.id, $0) })

        // 1. Merge built-in extensions with user preferences
        for var builtIn in builtIns {
            if let saved = savedByID[builtIn.id] {
                builtIn.isEnabled = saved.isEnabled
                builtIn.isPinnedToToolbar = saved.isPinnedToToolbar
                builtIn.allowInPrivateBrowsing = saved.allowInPrivateBrowsing
                builtIn.hostAccessMode = saved.hostAccessMode
                builtIn.customAllowedHosts = saved.customAllowedHosts
                builtIn.blockedHosts = saved.blockedHosts
                builtIn.installedAt = saved.installedAt
            }
            merged.append(builtIn)
        }

        // 2. Append user-installed extensions whose directories still exist
        let builtInIDs = Set(builtIns.map(\.id))
        for saved in savedRegistry.extensions where !builtInIDs.contains(saved.id) {
            let dirURL = URL(fileURLWithPath: saved.directoryPath, isDirectory: true)
            let manifestURL = dirURL.appendingPathComponent("manifest.json")
            if FileManager.default.fileExists(atPath: manifestURL.path),
               let refreshedManifest = try? Self.loadManifest(fromDirectory: dirURL) {
                var updated = saved
                updated.manifest = refreshedManifest
                updated.lastLoadError = nil
                merged.append(updated)
            } else if FileManager.default.fileExists(atPath: dirURL.path) {
                var broken = saved
                broken.lastLoadError = "未找到 manifest.json"
                merged.append(broken)
            }
        }

        self.extensions = merged
    }

    public func persistRegistry() {
        let snapshot = PersistedRegistry(
            isDeveloperMode: isDeveloperMode,
            extensions: extensions
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: registryFileURL, options: .atomic)
    }

    public static func loadManifest(fromDirectory directory: URL) throws -> ExtensionManifest {
        let manifestURL = directory.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw ExtensionPackageError.manifestMissing
        }
        let rawData: Data
        do {
            rawData = try Data(contentsOf: manifestURL)
        } catch {
            throw ExtensionPackageError.invalidManifest(error.localizedDescription)
        }
        do {
            let decoded = try JSONDecoder().decode(ExtensionManifest.self, from: rawData)
            let i18n = ExtensionI18nCatalog.load(from: directory, defaultLocale: decoded.defaultLocale)
            return i18n.applying(to: decoded)
        } catch {
            throw ExtensionPackageError.invalidManifest(error.localizedDescription)
        }
    }

    // MARK: - Installation (Unpacked Directory, CRX, ZIP, UserScript, Custom Creator)

    /// Loads an unpacked Chrome extension from a local directory containing `manifest.json`.
    @discardableResult
    public func installUnpackedExtension(from directoryURL: URL) throws -> InstalledExtension {
        let rootDir = try CRXPackageUnpacker.locateExtensionRoot(in: directoryURL)
        let manifest = try Self.loadManifest(fromDirectory: rootDir)
        let extID = InstalledExtension.makeChromeExtensionID(from: "unpacked:\(rootDir.standardizedFileURL.path)")

        let item = InstalledExtension(
            id: extID,
            manifest: manifest,
            sourceKind: .unpacked,
            directoryPath: rootDir.standardizedFileURL.path,
            isEnabled: true,
            isPinnedToToolbar: true,
            allowInPrivateBrowsing: false,
            hostAccessMode: .onAllSites,
            sfSymbolFallback: "Shippingbox.fill".lowercased(),
            accentColorHex: "#3B82F6"
        )
        upsertExtension(item)
        showBanner("已加载扩展「\(manifest.name)」v\(manifest.version)")
        return item
    }

    /// Installs an extension from a `.crx`, `.zip`, or `.user.js` file URL.
    @discardableResult
    public func installPackage(from fileURL: URL) throws -> InstalledExtension {
        let fileName = fileURL.lastPathComponent.lowercased()
        if fileName.hasSuffix(".user.js") || fileName.hasSuffix(".js") {
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            let fallbackName = fileURL.deletingPathExtension().deletingPathExtension().lastPathComponent
            return try installUserScript(scriptContent: content, fallbackName: fallbackName)
        }

        let stagingID = UUID().uuidString
        let stagingDir = installedPackagesDirectory.appendingPathComponent("staging-\(stagingID)", isDirectory: true)
        let unpackedRoot = try CRXPackageUnpacker.unpackArchive(at: fileURL, into: stagingDir)
        let manifest = try Self.loadManifest(fromDirectory: unpackedRoot)
        let extID = InstalledExtension.makeChromeExtensionID(from: "pkg:\(manifest.name):\(fileURL.lastPathComponent)")
        let finalDir = installedPackagesDirectory.appendingPathComponent(extID, isDirectory: true)

        let fm = FileManager.default
        if fm.fileExists(atPath: finalDir.path) {
            try? fm.removeItem(at: finalDir)
        }
        try fm.moveItem(at: unpackedRoot, to: finalDir)
        try? fm.removeItem(at: stagingDir)

        let item = InstalledExtension(
            id: extID,
            manifest: manifest,
            sourceKind: .packaged,
            directoryPath: finalDir.path,
            isEnabled: true,
            isPinnedToToolbar: true,
            allowInPrivateBrowsing: false,
            hostAccessMode: .onAllSites,
            sfSymbolFallback: "puzzlepiece.extension.fill",
            accentColorHex: "#0EA5E9"
        )
        upsertExtension(item)
        showBanner("已安装扩展包「\(manifest.name)」v\(manifest.version)")
        return item
    }

    /// Installs a `.user.js` Tampermonkey/Greasemonkey script as a first-class browser extension.
    @discardableResult
    public func installUserScript(scriptContent: String, fallbackName: String = "自定义脚本") throws -> InstalledExtension {
        let parsed = UserScriptParser.parse(scriptContent: scriptContent, fallbackName: fallbackName)
        let extID = InstalledExtension.makeChromeExtensionID(from: "userscript:\(parsed.namespace ?? ""):\(parsed.name)")
        let extDir = installedPackagesDirectory.appendingPathComponent(extID, isDirectory: true)

        let fm = FileManager.default
        try fm.createDirectory(at: extDir, withIntermediateDirectories: true)

        let jsURL = extDir.appendingPathComponent("userscript.js")
        try parsed.sourceCode.write(to: jsURL, atomically: true, encoding: .utf8)

        let manifest = UserScriptParser.buildManifest(from: parsed, jsFilename: "userscript.js")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let manifestData = try encoder.encode(manifest)
        try manifestData.write(to: extDir.appendingPathComponent("manifest.json"), options: .atomic)

        let item = InstalledExtension(
            id: extID,
            manifest: manifest,
            sourceKind: .userScript,
            directoryPath: extDir.path,
            isEnabled: true,
            isPinnedToToolbar: true,
            allowInPrivateBrowsing: false,
            hostAccessMode: .onAllSites,
            sfSymbolFallback: "scroll.fill",
            accentColorHex: "#8B5CF6"
        )
        upsertExtension(item)
        showBanner("已导入用户脚本「\(manifest.name)」")
        return item
    }

    /// Creates a custom extension with user-supplied metadata, match patterns, JavaScript, and CSS.
    @discardableResult
    public func createCustomExtension(
        name: String,
        version: String = "1.0.0",
        description: String,
        matches: [String] = ["<all_urls>"],
        runAt: ExtensionRunAt = .documentEnd,
        jsCode: String,
        cssCode: String,
        sfSymbol: String = "sparkles.rectangle.stack.fill",
        accentColorHex: String = "#10B981"
    ) throws -> InstalledExtension {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else {
            throw ExtensionPackageError.invalidManifest("扩展名称不能为空")
        }
        let validMatches = matches
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { ExtensionMatchPattern.isValid(pattern: $0) }
        let effectiveMatches = validMatches.isEmpty ? ["<all_urls>"] : validMatches

        let extID = InstalledExtension.makeChromeExtensionID(from: "custom:\(cleanName):\(Date().timeIntervalSince1970)")
        let extDir = installedPackagesDirectory.appendingPathComponent(extID, isDirectory: true)
        try FileManager.default.createDirectory(at: extDir, withIntermediateDirectories: true)

        var jsFiles: [String] = []
        var cssFiles: [String] = []

        if !jsCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try jsCode.write(to: extDir.appendingPathComponent("content.js"), atomically: true, encoding: .utf8)
            jsFiles.append("content.js")
        }
        if !cssCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try cssCode.write(to: extDir.appendingPathComponent("content.css"), atomically: true, encoding: .utf8)
            cssFiles.append("content.css")
        }

        let popupHTML = """
        <!DOCTYPE html>
        <html lang="zh-CN">
        <head>
        <meta charset="utf-8">
        <style>
            body { width: 260px; padding: 14px; background: #18181B; color: #F4F4F5; font-family: -apple-system, sans-serif; margin: 0; }
            h3 { font-size: 13px; margin: 0 0 6px 0; }
            p { font-size: 11.5px; color: #A1A1AA; margin: 0 0 10px 0; line-height: 1.45; }
            .tag { display: inline-block; padding: 2px 7px; border-radius: 4px; background: #27272A; font-size: 10.5px; color: #10B981; }
        </style>
        </head>
        <body>
            <h3>\(cleanName)</h3>
            <p>\(description.isEmpty ? "自定义页面增强扩展" : description)</p>
            <span class="tag">运行阶段：\(runAt.rawValue)</span>
        </body>
        </html>
        """
        try popupHTML.write(to: extDir.appendingPathComponent("popup.html"), atomically: true, encoding: .utf8)

        let manifest = ExtensionManifest(
            manifestVersion: 3,
            name: cleanName,
            version: version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "1.0.0" : version,
            description: description,
            author: "Local Developer",
            permissions: ["storage", "activeTab", "scripting"],
            hostPermissions: effectiveMatches,
            action: ExtensionActionSpec(defaultTitle: cleanName, defaultPopup: "popup.html"),
            contentScripts: [
                ExtensionContentScriptSpec(
                    matches: effectiveMatches,
                    js: jsFiles,
                    css: cssFiles,
                    runAt: runAt,
                    allFrames: false
                )
            ]
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let manifestData = try encoder.encode(manifest)
        try manifestData.write(to: extDir.appendingPathComponent("manifest.json"), options: .atomic)

        let item = InstalledExtension(
            id: extID,
            manifest: manifest,
            sourceKind: .userScript,
            directoryPath: extDir.path,
            isEnabled: true,
            isPinnedToToolbar: true,
            allowInPrivateBrowsing: false,
            hostAccessMode: .onAllSites,
            sfSymbolFallback: sfSymbol,
            accentColorHex: accentColorHex
        )
        upsertExtension(item)
        showBanner("已创建自定义扩展「\(cleanName)」")
        return item
    }

    private func upsertExtension(_ item: InstalledExtension) {
        iconCache.removeValue(forKey: item.id)
        if let idx = extensions.firstIndex(where: { $0.id == item.id }) {
            var updated = item
            updated.installedAt = extensions[idx].installedAt
            updated.updatedAt = Date()
            extensions[idx] = updated
        } else {
            extensions.append(item)
        }
        persistRegistry()
        syncAllOpenTabs(evaluateLiveScripts: true)
    }

    // MARK: - Extension Lifecycle & Permissions Mutation

    public func setExtensionEnabled(id: String, enabled: Bool) {
        guard let idx = extensions.firstIndex(where: { $0.id == id }) else { return }
        guard extensions[idx].isEnabled != enabled else { return }
        extensions[idx].isEnabled = enabled
        extensions[idx].updatedAt = Date()
        if !enabled {
            if activePopupExtensionID == id {
                activePopupExtensionID = nil
            }
            contextMenuItems.removeAll { $0.extensionID == id }
            removeInjectedStylesFromAllTabs(extensionID: id)
        }
        persistRegistry()
        syncAllOpenTabs(evaluateLiveScripts: enabled)
    }

    public func togglePinToToolbar(id: String) {
        guard let idx = extensions.firstIndex(where: { $0.id == id }) else { return }
        extensions[idx].isPinnedToToolbar.toggle()
        extensions[idx].updatedAt = Date()
        persistRegistry()
    }

    public func setAllowInPrivateBrowsing(id: String, allowed: Bool) {
        guard let idx = extensions.firstIndex(where: { $0.id == id }) else { return }
        extensions[idx].allowInPrivateBrowsing = allowed
        extensions[idx].updatedAt = Date()
        persistRegistry()
        syncAllOpenTabs(evaluateLiveScripts: false)
    }

    public func setHostAccessMode(id: String, mode: ExtensionHostAccessMode) {
        guard let idx = extensions.firstIndex(where: { $0.id == id }) else { return }
        extensions[idx].hostAccessMode = mode
        extensions[idx].updatedAt = Date()
        persistRegistry()
        syncAllOpenTabs(evaluateLiveScripts: true)
    }

    public func addAllowedHost(id: String, host: String) {
        let clean = URLPolicy.rawHost(host.contains("://") ? host : "https://\(host)")
        guard !clean.isEmpty, let idx = extensions.firstIndex(where: { $0.id == id }) else { return }
        if !extensions[idx].customAllowedHosts.contains(clean) {
            extensions[idx].customAllowedHosts.append(clean)
            extensions[idx].updatedAt = Date()
            persistRegistry()
            syncAllOpenTabs(evaluateLiveScripts: true)
        }
    }

    public func removeAllowedHost(id: String, host: String) {
        guard let idx = extensions.firstIndex(where: { $0.id == id }) else { return }
        extensions[idx].customAllowedHosts.removeAll { $0.caseInsensitiveCompare(host) == .orderedSame }
        extensions[idx].updatedAt = Date()
        persistRegistry()
        syncAllOpenTabs(evaluateLiveScripts: false)
    }

    public func toggleBlockHost(id: String, host: String) {
        let clean = host.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let idx = extensions.firstIndex(where: { $0.id == id }) else { return }
        if extensions[idx].blockedHosts.contains(clean) {
            extensions[idx].blockedHosts.removeAll { $0 == clean }
        } else {
            extensions[idx].blockedHosts.append(clean)
        }
        extensions[idx].updatedAt = Date()
        persistRegistry()
        syncAllOpenTabs(evaluateLiveScripts: true)
    }

    @discardableResult
    public func reloadExtension(id: String) -> Bool {
        guard let idx = extensions.firstIndex(where: { $0.id == id }) else { return false }
        iconCache.removeValue(forKey: id)
        if extensions[idx].sourceKind == .builtIn {
            _ = BuiltInExtensions.materializeAll(in: rootDirectory)
        }
        let dirURL = URL(fileURLWithPath: extensions[idx].directoryPath, isDirectory: true)
        do {
            let reloadedManifest = try Self.loadManifest(fromDirectory: dirURL)
            extensions[idx].manifest = reloadedManifest
            extensions[idx].lastLoadError = nil
            extensions[idx].updatedAt = Date()
            persistRegistry()
            syncAllOpenTabs(evaluateLiveScripts: true)
            showBanner("已重新加载「\(reloadedManifest.name)」")
            return true
        } catch {
            extensions[idx].lastLoadError = error.localizedDescription
            persistRegistry()
            return false
        }
    }

    public func reloadAllExtensions() {
        _ = BuiltInExtensions.materializeAll(in: rootDirectory)
        for idx in extensions.indices {
            let id = extensions[idx].id
            iconCache.removeValue(forKey: id)
            let dirURL = URL(fileURLWithPath: extensions[idx].directoryPath, isDirectory: true)
            if let manifest = try? Self.loadManifest(fromDirectory: dirURL) {
                extensions[idx].manifest = manifest
                extensions[idx].lastLoadError = nil
                extensions[idx].updatedAt = Date()
            }
        }
        persistRegistry()
        syncAllOpenTabs(evaluateLiveScripts: true)
        showBanner("已重新加载全部 \(extensions.count) 个扩展程序")
    }

    public func uninstallExtension(id: String) {
        guard let idx = extensions.firstIndex(where: { $0.id == id }) else { return }
        let ext = extensions[idx]
        if activePopupExtensionID == id {
            activePopupExtensionID = nil
        }
        if inspectingExtensionID == id {
            inspectingExtensionID = nil
        }
        contextMenuItems.removeAll { $0.extensionID == id }
        removeInjectedStylesFromAllTabs(extensionID: id)
        clearStorage(forExtensionID: id, area: "local")
        clearStorage(forExtensionID: id, area: "sync")

        if ext.sourceKind == .builtIn {
            // Built-in extensions can be disabled and reset rather than deleting bundled templates
            extensions[idx].isEnabled = false
            extensions[idx].isPinnedToToolbar = false
            extensions[idx].actionState = ExtensionActionState()
            persistRegistry()
            syncAllOpenTabs(evaluateLiveScripts: false)
            showBanner("已禁用并重置内置扩展「\(ext.manifest.name)」")
            return
        }

        if ext.sourceKind == .packaged || ext.sourceKind == .userScript {
            let dirURL = URL(fileURLWithPath: ext.directoryPath, isDirectory: true)
            if dirURL.path.hasPrefix(installedPackagesDirectory.path) {
                try? FileManager.default.removeItem(at: dirURL)
            }
        }
        extensions.remove(at: idx)
        iconCache.removeValue(forKey: id)
        persistRegistry()
        syncAllOpenTabs(evaluateLiveScripts: false)
        showBanner("已卸载扩展「\(ext.manifest.name)」")
    }

    // MARK: - Panel File Pickers (macOS Open Panel)

    public func promptLoadUnpackedExtension() {
        let panel = NSOpenPanel()
        panel.title = "加载已解压的扩展程序 (选择包含 manifest.json 的文件夹)"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            do {
                _ = try installUnpackedExtension(from: url)
            } catch {
                showBanner("加载失败：\(error.localizedDescription)")
            }
        }
    }

    public func promptInstallExtensionPackage() {
        let panel = NSOpenPanel()
        panel.title = "安装扩展程序包 (.crx / .zip) 或用户脚本 (.user.js)"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedFileTypes = ["crx", "zip", "js"]
        if panel.runModal() == .OK, let url = panel.url {
            do {
                _ = try installPackage(from: url)
            } catch {
                showBanner("安装失败：\(error.localizedDescription)")
            }
        }
    }

    // MARK: - Toolbar Action & Options Triggers

    /// Invoked when the user clicks an extension's toolbar button or puzzle menu row.
    public func triggerExtensionAction(id: String, in browserSession: BrowserSession? = nil) {
        let targetSession = browserSession ?? session ?? BrowserSession.shared
        guard let ext = extensionItem(forID: id), ext.isEnabled else { return }

        if let activeTabID = targetSession.activeTabID {
            activeTabGrants[activeTabID, default: []].insert(id)
        }

        if ext.effectivePopupRelativePath != nil {
            if activePopupExtensionID == id {
                activePopupExtensionID = nil
            } else {
                isShowingToolbarPuzzlePopover = false
                activePopupExtensionID = id
            }
            return
        }

        // No popup configured: execute on-click content scripts if in `.onClick` mode and fire `chrome.action.onClicked`
        if let activeTab = targetSession.activeTab,
           let controller = targetSession.controller(for: activeTab.id),
           let webView = controller.webView {
            if ext.hostAccessMode == .onClick {
                evaluateExtensionScripts(ext, on: webView, tabID: activeTab.id, urlString: activeTab.url)
            }
            let tabNumID = numericTabID(for: activeTab.id)
            let dispatchJS = """
            if (window.__ZHUO_EXTENSIONS__ && window.__ZHUO_EXTENSIONS__["\(ExtensionRuntimeBridge.escapeJSString(id))"]) {
                window.__ZHUO_EXTENSIONS__["\(ExtensionRuntimeBridge.escapeJSString(id))"].dispatchActionClicked({
                    id: \(tabNumID),
                    url: "\(ExtensionRuntimeBridge.escapeJSString(activeTab.url))",
                    title: "\(ExtensionRuntimeBridge.escapeJSString(activeTab.title))",
                    active: true
                });
            }
            """
            webView.evaluateJavaScript(dispatchJS, completionHandler: nil)
        }
    }

    public func openOptionsPage(forExtensionID id: String, in browserSession: BrowserSession? = nil) {
        let targetSession = browserSession ?? session ?? BrowserSession.shared
        guard let ext = extensionItem(forID: id) else { return }
        if let optionsURL = ext.optionsURL {
            isShowingExtensionManager = false
            isShowingToolbarPuzzlePopover = false
            activePopupExtensionID = nil
            targetSession.createTab(url: optionsURL.absoluteString, select: true)
        } else {
            inspectingExtensionID = id
            isShowingExtensionManager = true
        }
    }

    // MARK: - Storage Management (`chrome.storage.local` / `sync` / `session`)

    public func storageSnapshot(forExtensionID extensionID: String, area: String = "local") -> [String: Any] {
        if let cached = storageMemoryCache[extensionID]?[area] {
            return cached
        }
        guard area != "session" else { return [:] }
        let fileURL = storageFileURL(extensionID: extensionID, area: area)
        guard let data = try? Data(contentsOf: fileURL),
              let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return [:]
        }
        storageMemoryCache[extensionID, default: [:]][area] = dict
        return dict
    }

    public func updateStorage(
        forExtensionID extensionID: String,
        area: String = "local",
        merging items: [String: Any]
    ) -> [String: [String: Any]] {
        var current = storageSnapshot(forExtensionID: extensionID, area: area)
        var changes: [String: [String: Any]] = [:]
        for (key, newVal) in items {
            var changeEntry: [String: Any] = ["newValue": newVal]
            if let oldVal = current[key] {
                changeEntry["oldValue"] = oldVal
            }
            changes[key] = changeEntry
            current[key] = newVal
        }
        storageMemoryCache[extensionID, default: [:]][area] = current
        persistStorageArea(extensionID: extensionID, area: area, dictionary: current)
        broadcastStorageChanges(extensionID: extensionID, area: area, changes: changes)
        return changes
    }

    public func removeStorageKeys(
        forExtensionID extensionID: String,
        area: String = "local",
        keys: [String]
    ) {
        var current = storageSnapshot(forExtensionID: extensionID, area: area)
        var changes: [String: [String: Any]] = [:]
        for key in keys {
            if let oldVal = current.removeValue(forKey: key) {
                changes[key] = ["oldValue": oldVal]
            }
        }
        storageMemoryCache[extensionID, default: [:]][area] = current
        persistStorageArea(extensionID: extensionID, area: area, dictionary: current)
        broadcastStorageChanges(extensionID: extensionID, area: area, changes: changes)
    }

    public func clearStorage(forExtensionID extensionID: String, area: String = "local") {
        let current = storageSnapshot(forExtensionID: extensionID, area: area)
        var changes: [String: [String: Any]] = [:]
        for (k, oldVal) in current {
            changes[k] = ["oldValue": oldVal]
        }
        storageMemoryCache[extensionID, default: [:]][area] = [:]
        let fileURL = storageFileURL(extensionID: extensionID, area: area)
        try? FileManager.default.removeItem(at: fileURL)
        broadcastStorageChanges(extensionID: extensionID, area: area, changes: changes)
    }

    private func storageFileURL(extensionID: String, area: String) -> URL {
        let safeID = extensionID.replacingOccurrences(of: "/", with: "_")
        return storageDirectory.appendingPathComponent("\(safeID)_\(area).json")
    }

    private func persistStorageArea(extensionID: String, area: String, dictionary: [String: Any]) {
        guard area != "session" else { return }
        guard JSONSerialization.isValidJSONObject(dictionary),
              let data = try? JSONSerialization.data(withJSONObject: dictionary, options: [.prettyPrinted, .sortedKeys]) else {
            return
        }
        let fileURL = storageFileURL(extensionID: extensionID, area: area)
        try? data.write(to: fileURL, options: .atomic)
    }

    private func broadcastStorageChanges(extensionID: String, area: String, changes: [String: [String: Any]]) {
        guard !changes.isEmpty else { return }
        let changesJSON = ExtensionRuntimeBridge.serializeJSONDictionary(changes)
        let escapedID = ExtensionRuntimeBridge.escapeJSString(extensionID)
        let js = """
        if (window.__ZHUO_EXTENSIONS__ && window.__ZHUO_EXTENSIONS__["\(escapedID)"]) {
            window.__ZHUO_EXTENSIONS__["\(escapedID)"].dispatchStorageChanged(\(changesJSON), "\(ExtensionRuntimeBridge.escapeJSString(area))");
        }
        """
        let targetSession = session ?? BrowserSession.shared
        for tab in targetSession.tabs {
            targetSession.controller(for: tab.id)?.webView?.evaluateJavaScript(js, completionHandler: nil)
        }
        activePopupWebView?.evaluateJavaScript(js, completionHandler: nil)
    }

    // MARK: - Content Script Compilation & Injection into `WKUserContentController`

    /// Builds all `WKUserScript`s required by currently enabled extensions for a tab.
    public func makeUserScripts(forTabID tabID: String, isPrivate: Bool) -> [WKUserScript] {
        let tabNumID = numericTabID(for: tabID)
        var userScripts: [WKUserScript] = []

        for ext in enabledExtensions {
            if isPrivate && !ext.allowInPrivateBrowsing {
                continue
            }
            guard !ext.manifest.contentScripts.isEmpty else { continue }

            let extDir = URL(fileURLWithPath: ext.directoryPath, isDirectory: true)
            let localStore = storageSnapshot(forExtensionID: ext.id, area: "local")
            let syncStore = storageSnapshot(forExtensionID: ext.id, area: "sync")
            let i18n = ExtensionI18nCatalog.load(from: extDir, defaultLocale: ext.manifest.defaultLocale)
            let polyfill = ExtensionRuntimeBridge.makePolyfillScript(
                extensionItem: ext,
                contextType: .contentScript,
                tabNumericID: tabNumID,
                initialLocalStore: localStore,
                initialSyncStore: syncStore,
                i18nCatalog: i18n
            )

            for (specIndex, spec) in ext.manifest.contentScripts.enumerated() {
                let injectionTime: WKUserScriptInjectionTime = (spec.runAt == .documentStart)
                    ? .atDocumentStart
                    : .atDocumentEnd
                let mainFrameOnly = !spec.allFrames

                // 1. CSS files
                for (cssIdx, cssRelPath) in spec.css.enumerated() {
                    let cssURL = extDir.appendingPathComponent(cssRelPath)
                    guard let rawCSS = try? String(contentsOf: cssURL, encoding: .utf8) else { continue }
                    let resolvedCSS = i18n.resolvePlaceholders(in: rawCSS)
                    let styleID = "zhuo-ext-css-\(ext.id)-\(specIndex)-\(cssIdx)"
                    let cssJS = ExtensionRuntimeBridge.makeCSSInjectionScript(
                        extensionID: ext.id,
                        styleID: styleID,
                        cssContent: resolvedCSS
                    )
                    userScripts.append(
                        WKUserScript(
                            source: cssJS,
                            injectionTime: injectionTime,
                            forMainFrameOnly: mainFrameOnly
                        )
                    )
                }

                // 2. JS files
                for jsRelPath in spec.js {
                    let jsURL = extDir.appendingPathComponent(jsRelPath)
                    guard let rawJS = try? String(contentsOf: jsURL, encoding: .utf8) else { continue }
                    let wrapped = ExtensionRuntimeBridge.wrapContentScript(
                        extensionItem: ext,
                        spec: spec,
                        jsSource: rawJS,
                        polyfillScript: polyfill
                    )
                    userScripts.append(
                        WKUserScript(
                            source: wrapped,
                            injectionTime: injectionTime,
                            forMainFrameOnly: mainFrameOnly
                        )
                    )
                }
            }
        }
        return userScripts
    }

    /// Evaluates enabled extensions on a live `WKWebView` (e.g., when an extension is newly enabled or reloaded).
    public func evaluateEnabledExtensions(on webView: WKWebView, tabID: String, isPrivate: Bool) {
        guard let urlString = webView.url?.absoluteString, !URLPolicy.isHomeURL(urlString) else { return }
        for ext in enabledExtensions {
            let hasGrant = activeTabGrants[tabID]?.contains(ext.id) ?? false
            guard ext.canRunOn(url: urlString, isPrivateTab: isPrivate, hasActiveTabGrant: hasGrant) else {
                continue
            }
            evaluateExtensionScripts(ext, on: webView, tabID: tabID, urlString: urlString)
        }
    }

    public func evaluateExtensionScripts(
        _ ext: InstalledExtension,
        on webView: WKWebView,
        tabID: String,
        urlString: String
    ) {
        let extDir = URL(fileURLWithPath: ext.directoryPath, isDirectory: true)
        let tabNumID = numericTabID(for: tabID)
        let localStore = storageSnapshot(forExtensionID: ext.id, area: "local")
        let syncStore = storageSnapshot(forExtensionID: ext.id, area: "sync")
        let i18n = ExtensionI18nCatalog.load(from: extDir, defaultLocale: ext.manifest.defaultLocale)
        let polyfill = ExtensionRuntimeBridge.makePolyfillScript(
            extensionItem: ext,
            contextType: .contentScript,
            tabNumericID: tabNumID,
            initialLocalStore: localStore,
            initialSyncStore: syncStore,
            i18nCatalog: i18n
        )

        for (specIndex, spec) in ext.manifest.contentScripts.enumerated() {
            guard spec.matchesURL(urlString, isMainFrame: true) else { continue }
            for (cssIdx, cssRelPath) in spec.css.enumerated() {
                let cssURL = extDir.appendingPathComponent(cssRelPath)
                if let rawCSS = try? String(contentsOf: cssURL, encoding: .utf8) {
                    let styleID = "zhuo-ext-css-\(ext.id)-\(specIndex)-\(cssIdx)"
                    let cssJS = ExtensionRuntimeBridge.makeCSSInjectionScript(
                        extensionID: ext.id,
                        styleID: styleID,
                        cssContent: i18n.resolvePlaceholders(in: rawCSS)
                    )
                    webView.evaluateJavaScript(cssJS, completionHandler: nil)
                }
            }
            for jsRelPath in spec.js {
                let jsURL = extDir.appendingPathComponent(jsRelPath)
                if let rawJS = try? String(contentsOf: jsURL, encoding: .utf8) {
                    let wrapped = ExtensionRuntimeBridge.wrapContentScript(
                        extensionItem: ext,
                        spec: spec,
                        jsSource: rawJS,
                        polyfillScript: polyfill
                    )
                    webView.evaluateJavaScript(wrapped, completionHandler: nil)
                }
            }
        }
    }

    private func removeInjectedStylesFromAllTabs(extensionID: String) {
        let escaped = ExtensionRuntimeBridge.escapeJSString(extensionID)
        let cleanupJS = """
        document.querySelectorAll('[data-zhuo-extension="\(escaped)"]').forEach(function(el) { el.remove(); });
        """
        let targetSession = session ?? BrowserSession.shared
        for tab in targetSession.tabs {
            targetSession.controller(for: tab.id)?.webView?.evaluateJavaScript(cleanupJS, completionHandler: nil)
        }
    }

    private func syncAllOpenTabs(evaluateLiveScripts: Bool) {
        let targetSession = session ?? BrowserSession.shared
        targetSession.applyContentProtectionSettingsToAllTabs(evaluateLiveScripts: evaluateLiveScripts)
    }

    // MARK: - Numeric Tab ID Mapping for `chrome.tabs`

    public func numericTabID(for tabUUID: String) -> Int {
        if let existing = tabStringToNumeric[tabUUID] {
            return existing
        }
        let assigned = nextNumericTabID
        nextNumericTabID += 1
        tabStringToNumeric[tabUUID] = assigned
        tabNumericToString[assigned] = tabUUID
        return assigned
    }

    public func tabUUID(forNumericID numericID: Int) -> String? {
        tabNumericToString[numericID]
    }

    public func activeTabNumericID() -> Int {
        let targetSession = session ?? BrowserSession.shared
        guard let activeID = targetSession.activeTabID else { return 1 }
        return numericTabID(for: activeID)
    }

    public func serializeTabForChromeAPI(_ tab: BrowserTab, index: Int, isActive: Bool) -> [String: Any] {
        [
            "id": numericTabID(for: tab.id),
            "index": index,
            "windowId": 1,
            "active": isActive,
            "pinned": false,
            "incognito": tab.isPrivate,
            "url": tab.url,
            "title": tab.title,
            "status": tab.isLoading ? "loading" : "complete"
        ]
    }

    // MARK: - Native Message Router (`window.webkit.messageHandlers.zhuoExtensionBridge`)

    public func handleScriptMessage(_ message: WKScriptMessage, sourceWebView: WKWebView?, tabID: String?) {
        guard let body = message.body as? [String: Any],
              let requestID = body["requestId"] as? String,
              let extensionID = body["extensionId"] as? String,
              let action = body["action"] as? String else {
            return
        }
        let payload = (body["payload"] as? [String: Any]) ?? [:]
        let originatingWebView = sourceWebView ?? message.webView

        processBridgeCall(
            extensionID: extensionID,
            action: action,
            payload: payload,
            sourceTabID: tabID
        ) { [weak originatingWebView] result, errorMessage in
            guard let originatingWebView else { return }
            var responseObj: [String: Any] = [:]
            if let errorMessage {
                responseObj["error"] = errorMessage
            }
            if let result {
                responseObj["result"] = result
            }
            let responseJSON = ExtensionRuntimeBridge.serializeJSONDictionary(responseObj)
            let escapedReqID = ExtensionRuntimeBridge.escapeJSString(requestID)
            let callbackJS = "window.__zhuoExtensionResolveCallback && window.__zhuoExtensionResolveCallback(\"\(escapedReqID)\", \(responseJSON));"
            originatingWebView.evaluateJavaScript(callbackJS, completionHandler: nil)
        }
    }

    public func processBridgeCall(
        extensionID: String,
        action: String,
        payload: [String: Any],
        sourceTabID: String?,
        completion: @escaping (Any?, String?) -> Void
    ) {
        let targetSession = session ?? BrowserSession.shared

        switch action {
        // 1. Storage APIs
        case "storage.get":
            let area = (payload["area"] as? String) ?? "local"
            let fullStore = storageSnapshot(forExtensionID: extensionID, area: area)
            completion(fullStore, nil)

        case "storage.set":
            let area = (payload["area"] as? String) ?? "local"
            let items = (payload["items"] as? [String: Any]) ?? [:]
            _ = updateStorage(forExtensionID: extensionID, area: area, merging: items)
            completion(NSNull(), nil)

        case "storage.remove":
            let area = (payload["area"] as? String) ?? "local"
            let keys = (payload["keys"] as? [String]) ?? []
            removeStorageKeys(forExtensionID: extensionID, area: area, keys: keys)
            completion(NSNull(), nil)

        case "storage.clear":
            let area = (payload["area"] as? String) ?? "local"
            clearStorage(forExtensionID: extensionID, area: area)
            completion(NSNull(), nil)

        // 2. Action / BrowserAction APIs
        case "action.setBadgeText":
            let text = (payload["text"] as? String) ?? ""
            let targetTabNum = payload["tabId"] as? Int
            if let idx = extensions.firstIndex(where: { $0.id == extensionID }) {
                if let targetTabNum, let tUUID = tabUUID(forNumericID: targetTabNum) {
                    extensions[idx].actionState.tabBadgeText[tUUID] = text
                } else {
                    extensions[idx].actionState.defaultBadgeText = text
                }
            }
            completion(NSNull(), nil)

        case "action.setBadgeBackgroundColor":
            let colorStr: String
            if let str = payload["color"] as? String, !str.isEmpty {
                colorStr = str
            } else if let arr = payload["color"] as? [Int], arr.count >= 3 {
                colorStr = String(format: "#%02X%02X%02X", arr[0], arr[1], arr[2])
            } else {
                colorStr = "#2563EB"
            }
            if let idx = extensions.firstIndex(where: { $0.id == extensionID }) {
                extensions[idx].actionState.defaultBadgeBackgroundColor = colorStr
            }
            completion(NSNull(), nil)

        case "action.setTitle":
            let title = payload["title"] as? String
            if let idx = extensions.firstIndex(where: { $0.id == extensionID }) {
                extensions[idx].actionState.titleOverride = title
            }
            completion(NSNull(), nil)

        case "action.setPopup":
            let popup = payload["popup"] as? String
            if let idx = extensions.firstIndex(where: { $0.id == extensionID }) {
                extensions[idx].actionState.popupOverride = popup
            }
            completion(NSNull(), nil)

        case "action.setEnabled":
            let enabled = (payload["enabled"] as? Bool) ?? true
            if let idx = extensions.firstIndex(where: { $0.id == extensionID }) {
                extensions[idx].actionState.isActionEnabled = enabled
            }
            completion(NSNull(), nil)

        // 3. Tabs APIs
        case "tabs.query":
            let activeOnly = payload["active"] as? Bool
            var results: [[String: Any]] = []
            for (idx, tab) in targetSession.tabs.enumerated() {
                let isActive = (tab.id == targetSession.activeTabID)
                if let activeOnly, activeOnly != isActive {
                    continue
                }
                results.append(serializeTabForChromeAPI(tab, index: idx, isActive: isActive))
            }
            completion(results, nil)

        case "tabs.get":
            if let numID = payload["tabId"] as? Int,
               let tUUID = tabUUID(forNumericID: numID),
               let idx = targetSession.tabs.firstIndex(where: { $0.id == tUUID }) {
                let tab = targetSession.tabs[idx]
                completion(serializeTabForChromeAPI(tab, index: idx, isActive: tab.id == targetSession.activeTabID), nil)
            } else if let active = targetSession.activeTab {
                completion(serializeTabForChromeAPI(active, index: 0, isActive: true), nil)
            } else {
                completion(nil, "Tab not found")
            }

        case "tabs.getCurrent":
            if let sourceTabID,
               let idx = targetSession.tabs.firstIndex(where: { $0.id == sourceTabID }) {
                let tab = targetSession.tabs[idx]
                completion(serializeTabForChromeAPI(tab, index: idx, isActive: tab.id == targetSession.activeTabID), nil)
            } else if let active = targetSession.activeTab {
                completion(serializeTabForChromeAPI(active, index: 0, isActive: true), nil)
            } else {
                completion(NSNull(), nil)
            }

        case "tabs.create":
            let url = (payload["url"] as? String) ?? "zhuo://home"
            let active = (payload["active"] as? Bool) ?? true
            let created = targetSession.createTab(url: url, select: active)
            let idx = targetSession.tabs.firstIndex(where: { $0.id == created.id }) ?? 0
            completion(serializeTabForChromeAPI(created, index: idx, isActive: active), nil)

        case "tabs.update":
            let numID = payload["tabId"] as? Int
            let props = (payload["updateProperties"] as? [String: Any]) ?? [:]
            let targetUUID = numID.flatMap { tabUUID(forNumericID: $0) } ?? targetSession.activeTabID
            guard let targetUUID,
                  let idx = targetSession.tabs.firstIndex(where: { $0.id == targetUUID }) else {
                completion(nil, "Tab not found")
                return
            }
            if let active = props["active"] as? Bool, active {
                targetSession.selectTab(id: targetUUID)
            }
            if let newURL = props["url"] as? String, !newURL.isEmpty {
                if targetSession.activeTabID == targetUUID {
                    targetSession.navigate(to: newURL)
                } else if let urlObj = URL(string: newURL) {
                    targetSession.updateTab(targetUUID) { $0.url = newURL }
                    targetSession.controller(for: targetUUID)?.load(url: urlObj)
                }
            }
            let updatedTab = targetSession.tab(for: targetUUID) ?? targetSession.tabs[idx]
            completion(serializeTabForChromeAPI(updatedTab, index: idx, isActive: targetSession.activeTabID == targetUUID), nil)

        case "tabs.reload":
            let numID = payload["tabId"] as? Int
            let targetUUID = numID.flatMap { tabUUID(forNumericID: $0) } ?? targetSession.activeTabID
            if let targetUUID {
                if targetUUID == targetSession.activeTabID {
                    targetSession.reloadActiveTab()
                } else {
                    targetSession.controller(for: targetUUID)?.reload()
                }
            }
            completion(NSNull(), nil)

        case "tabs.remove":
            let ids = (payload["tabIds"] as? [Int]) ?? []
            for numID in ids {
                if let tUUID = tabUUID(forNumericID: numID) {
                    targetSession.closeTab(id: tUUID)
                }
            }
            completion(NSNull(), nil)

        case "tabs.sendMessage":
            let numID = payload["tabId"] as? Int
            let targetUUID = numID.flatMap { tabUUID(forNumericID: $0) } ?? targetSession.activeTabID
            let msgPayload = payload["message"]
            guard let targetUUID,
                  let webView = targetSession.controller(for: targetUUID)?.webView else {
                completion(NSNull(), nil)
                return
            }
            dispatchMessageToWebView(webView, extensionID: extensionID, message: msgPayload, completion: completion)

        // 4. Scripting APIs (`chrome.scripting.executeScript` / `insertCSS` / `removeCSS`)
        case "scripting.executeScript":
            let numID = payload["tabId"] as? Int
            let targetUUID = numID.flatMap { tabUUID(forNumericID: $0) } ?? sourceTabID ?? targetSession.activeTabID
            guard let targetUUID,
                  let webView = targetSession.controller(for: targetUUID)?.webView else {
                completion([], nil)
                return
            }
            var scriptsToRun: [String] = []
            if let inlineCode = payload["code"] as? String, !inlineCode.isEmpty {
                scriptsToRun.append(inlineCode)
            }
            if let files = payload["files"] as? [String],
               let ext = extensionItem(forID: extensionID) {
                let extDir = URL(fileURLWithPath: ext.directoryPath, isDirectory: true)
                for file in files {
                    let fileURL = extDir.appendingPathComponent(file)
                    if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                        scriptsToRun.append(content)
                    }
                }
            }
            guard !scriptsToRun.isEmpty else {
                completion([], nil)
                return
            }
            let combined = scriptsToRun.joined(separator: ";\n")
            webView.evaluateJavaScript(combined) { evalResult, error in
                if let error {
                    completion([], error.localizedDescription)
                } else {
                    let safeResult: Any = (evalResult != nil && JSONSerialization.isValidJSONObject(["v": evalResult!])) ? evalResult! : NSNull()
                    completion([["frameId": 0, "result": safeResult]], nil)
                }
            }

        case "scripting.insertCSS":
            let numID = payload["tabId"] as? Int
            let targetUUID = numID.flatMap { tabUUID(forNumericID: $0) } ?? sourceTabID ?? targetSession.activeTabID
            guard let targetUUID,
                  let webView = targetSession.controller(for: targetUUID)?.webView else {
                completion(NSNull(), nil)
                return
            }
            var cssBlocks: [String] = []
            if let rawCSS = payload["css"] as? String, !rawCSS.isEmpty {
                cssBlocks.append(rawCSS)
            }
            if let files = payload["files"] as? [String],
               let ext = extensionItem(forID: extensionID) {
                let extDir = URL(fileURLWithPath: ext.directoryPath, isDirectory: true)
                for file in files {
                    if let content = try? String(contentsOf: extDir.appendingPathComponent(file), encoding: .utf8) {
                        cssBlocks.append(content)
                    }
                }
            }
            let styleID = "zhuo-ext-dynamic-css-\(extensionID)"
            let js = ExtensionRuntimeBridge.makeCSSInjectionScript(
                extensionID: extensionID,
                styleID: styleID,
                cssContent: cssBlocks.joined(separator: "\n")
            )
            webView.evaluateJavaScript(js) { _, _ in
                completion(NSNull(), nil)
            }

        case "scripting.removeCSS":
            let numID = payload["tabId"] as? Int
            let targetUUID = numID.flatMap { tabUUID(forNumericID: $0) } ?? sourceTabID ?? targetSession.activeTabID
            if let targetUUID, let webView = targetSession.controller(for: targetUUID)?.webView {
                let styleID = "zhuo-ext-dynamic-css-\(extensionID)"
                let js = "document.getElementById(\"\(ExtensionRuntimeBridge.escapeJSString(styleID))\")?.remove();"
                webView.evaluateJavaScript(js, completionHandler: nil)
            }
            completion(NSNull(), nil)

        // 5. Runtime APIs
        case "runtime.sendMessage":
            let targetExtID = (payload["targetExtensionId"] as? String) ?? extensionID
            let msgPayload = payload["message"]
            if let popupWV = activePopupWebView {
                dispatchMessageToWebView(popupWV, extensionID: targetExtID, message: msgPayload, completion: completion)
            } else if let activeTabID = targetSession.activeTabID,
                      let tabWV = targetSession.controller(for: activeTabID)?.webView {
                dispatchMessageToWebView(tabWV, extensionID: targetExtID, message: msgPayload, completion: completion)
            } else {
                completion(NSNull(), nil)
            }

        case "runtime.openOptionsPage":
            openOptionsPage(forExtensionID: extensionID, in: targetSession)
            completion(NSNull(), nil)

        // 6. Context Menus
        case "contextMenus.create":
            let menuID = (payload["id"] as? String) ?? UUID().uuidString
            let title = (payload["title"] as? String) ?? "扩展操作"
            let contexts = (payload["contexts"] as? [String]) ?? ["all"]
            let item = ExtensionContextMenuItem(
                extensionID: extensionID,
                menuItemID: menuID,
                title: title,
                contexts: contexts
            )
            contextMenuItems.removeAll { $0.id == item.id }
            contextMenuItems.append(item)
            completion(menuID, nil)

        case "contextMenus.remove":
            if let menuID = payload["id"] as? String {
                contextMenuItems.removeAll { $0.extensionID == extensionID && $0.menuItemID == menuID }
            }
            completion(NSNull(), nil)

        case "contextMenus.removeAll":
            contextMenuItems.removeAll { $0.extensionID == extensionID }
            completion(NSNull(), nil)

        // 7. Clipboard & Notifications
        case "clipboard.writeText":
            if let text = payload["text"] as? String {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(text, forType: .string)
            }
            completion(true, nil)

        case "notifications.create":
            let notifID = (payload["id"] as? String) ?? "notif"
            let opts = (payload["options"] as? [String: Any]) ?? [:]
            let title = (opts["title"] as? String) ?? "扩展通知"
            let msg = (opts["message"] as? String) ?? ""
            showBanner("\(title)：\(msg)")
            completion(notifID, nil)

        default:
            completion(NSNull(), nil)
        }
    }

    private func dispatchMessageToWebView(
        _ webView: WKWebView,
        extensionID: String,
        message: Any?,
        completion: @escaping (Any?, String?) -> Void
    ) {
        let msgJSON: String
        if let message, JSONSerialization.isValidJSONObject(["m": message]),
           let data = try? JSONSerialization.data(withJSONObject: ["m": message]),
           let wrapper = String(data: data, encoding: .utf8) {
            msgJSON = "(\(wrapper)).m"
        } else if let str = message as? String {
            msgJSON = "\"\(ExtensionRuntimeBridge.escapeJSString(str))\""
        } else {
            msgJSON = "null"
        }
        let escapedExtID = ExtensionRuntimeBridge.escapeJSString(extensionID)
        let js = """
        (function() {
            if (window.__zhuoExtensionDispatchMessage) {
                const res = window.__zhuoExtensionDispatchMessage("\(escapedExtID)", \(msgJSON), { id: "\(escapedExtID)" });
                return res !== undefined ? JSON.stringify(res) : null;
            }
            return null;
        })();
        """
        webView.evaluateJavaScript(js) { evalResult, _ in
            if let jsonStr = evalResult as? String,
               let data = jsonStr.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
                completion(parsed, nil)
            } else {
                completion(NSNull(), nil)
            }
        }
    }

    private func showBanner(_ text: String) {
        lastOperationBanner = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            if self?.lastOperationBanner == text {
                self?.lastOperationBanner = nil
            }
        }
    }
}
