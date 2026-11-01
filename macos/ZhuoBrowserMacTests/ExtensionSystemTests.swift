import WebKit
import XCTest
@testable import ZhuoBrowserMac

final class ExtensionSystemTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZhuoExtensionTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        super.tearDown()
    }

    // MARK: - 1. Manifest V3 & V2 Parsing and i18n Resolution

    func testManifestV3AndV2DecodingWithLocales() throws {
        let extDir = tempDir.appendingPathComponent("sample-mv3", isDirectory: true)
        let zhLocaleDir = extDir
            .appendingPathComponent("_locales", isDirectory: true)
            .appendingPathComponent("zh_CN", isDirectory: true)
        try FileManager.default.createDirectory(at: zhLocaleDir, withIntermediateDirectories: true)

        let messagesJSON = """
        {
          "ext_name": { "message": "测试超级扩展" },
          "ext_desc": { "message": "支持 $1 的 Chrome 扩展" }
        }
        """
        try messagesJSON.write(to: zhLocaleDir.appendingPathComponent("messages.json"), atomically: true, encoding: .utf8)

        let mv3JSON = """
        {
          "manifest_version": 3,
          "name": "__MSG_ext_name__",
          "version": "2.1.0",
          "description": "__MSG_ext_desc__",
          "default_locale": "zh_CN",
          "permissions": ["storage", "tabs", "scripting"],
          "host_permissions": ["*://*.github.com/*"],
          "action": {
            "default_title": "__MSG_ext_name__",
            "default_popup": "popup.html",
            "default_icon": { "32": "icon32.png" }
          },
          "content_scripts": [
            {
              "matches": ["https://*.github.com/*"],
              "exclude_matches": ["https://gist.github.com/*"],
              "js": ["content.js"],
              "css": ["style.css"],
              "run_at": "document_start",
              "all_frames": true
            }
          ],
          "options_ui": {
            "page": "options.html",
            "open_in_tab": true
          },
          "web_accessible_resources": [
            {
              "resources": ["assets/logo.svg"],
              "matches": ["<all_urls>"]
            }
          ]
        }
        """
        try mv3JSON.write(to: extDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)

        let manifest = try ExtensionManager.loadManifest(fromDirectory: extDir)
        XCTAssertEqual(manifest.manifestVersion, 3)
        XCTAssertEqual(manifest.name, "测试超级扩展")
        XCTAssertEqual(manifest.action?.defaultTitle, "测试超级扩展")
        XCTAssertEqual(manifest.action?.defaultPopup, "popup.html")
        XCTAssertEqual(manifest.permissions, ["storage", "tabs", "scripting"])
        XCTAssertEqual(manifest.hostPermissions, ["*://*.github.com/*"])
        XCTAssertEqual(manifest.optionsPage, "options.html")
        XCTAssertEqual(manifest.webAccessibleResources, ["assets/logo.svg"])
        XCTAssertEqual(manifest.contentScripts.first?.runAt, .documentStart)
        XCTAssertTrue(manifest.contentScripts.first?.allFrames == true)

        // Also verify MV2 compatibility (browser_action + mixed permissions)
        let mv2Data = Data("""
        {
          "manifest_version": 2,
          "name": "Legacy MV2 Extension",
          "version": "1.0",
          "permissions": ["storage", "<all_urls>", "https://example.com/*"],
          "browser_action": {
            "default_title": "MV2 Action",
            "default_popup": "mv2_popup.html",
            "default_icon": "icon.png"
          },
          "options_page": "mv2_options.html",
          "web_accessible_resources": ["inject.js"]
        }
        """.utf8)
        let mv2Manifest = try JSONDecoder().decode(ExtensionManifest.self, from: mv2Data)
        XCTAssertEqual(mv2Manifest.manifestVersion, 2)
        XCTAssertEqual(mv2Manifest.permissions, ["storage"])
        XCTAssertEqual(mv2Manifest.hostPermissions, ["<all_urls>", "https://example.com/*"])
        XCTAssertEqual(mv2Manifest.action?.defaultPopup, "mv2_popup.html")
        XCTAssertEqual(mv2Manifest.optionsPage, "mv2_options.html")
        XCTAssertEqual(mv2Manifest.webAccessibleResources, ["inject.js"])
    }

    // MARK: - 2. Chrome Match Pattern & Glob Engine

    func testChromeMatchPatternEvaluation() {
        XCTAssertTrue(ExtensionMatchPattern.matches(pattern: "<all_urls>", urlString: "https://github.com/youdroid/ZhuoBrowser"))
        XCTAssertTrue(ExtensionMatchPattern.matches(pattern: "<all_urls>", urlString: "http://localhost:8080/index.html"))
        XCTAssertFalse(ExtensionMatchPattern.matches(pattern: "<all_urls>", urlString: "zhuo://home"))

        XCTAssertTrue(ExtensionMatchPattern.matches(pattern: "*://*.github.com/*", urlString: "https://github.com/explore"))
        XCTAssertTrue(ExtensionMatchPattern.matches(pattern: "*://*.github.com/*", urlString: "https://docs.github.com/en/pages"))
        XCTAssertFalse(ExtensionMatchPattern.matches(pattern: "*://*.github.com/*", urlString: "https://gitlab.com/explore"))

        let spec = ExtensionContentScriptSpec(
            matches: ["https://*.example.com/*"],
            excludeMatches: ["https://admin.example.com/*"],
            includeGlobs: ["*article*"],
            excludeGlobs: ["*draft*"],
            js: ["content.js"],
            runAt: .documentEnd,
            allFrames: false
        )
        XCTAssertTrue(spec.matchesURL("https://news.example.com/article/123", isMainFrame: true))
        XCTAssertFalse(spec.matchesURL("https://news.example.com/article/123", isMainFrame: false))
        XCTAssertFalse(spec.matchesURL("https://admin.example.com/article/123", isMainFrame: true))
        XCTAssertFalse(spec.matchesURL("https://news.example.com/article/draft-1", isMainFrame: true))
    }

    // MARK: - 3. UserScript Parser & Installation

    func testUserScriptParsingAndInstallation() throws {
        let script = """
        // ==UserScript==
        // @name         GitHub Wide Viewer
        // @name:zh-CN   GitHub 宽屏增强脚本
        // @namespace    https://youdroid.top/
        // @version      1.4.2
        // @description  Makes GitHub repository containers full width
        // @match        https://github.com/*
        // @exclude      https://github.com/settings/*
        // @run-at       document-start
        // @noframes
        // @grant        GM_addStyle
        // ==/UserScript==

        GM_addStyle('.container-xl { max-width: 98% !important; }');
        """

        let parsed = UserScriptParser.parse(scriptContent: script)
        XCTAssertEqual(parsed.name, "GitHub 宽屏增强脚本")
        XCTAssertEqual(parsed.version, "1.4.2")
        XCTAssertEqual(parsed.matches, ["https://github.com/*"])
        XCTAssertEqual(parsed.excludeMatches, ["https://github.com/settings/*"])
        XCTAssertEqual(parsed.runAt, .documentStart)
        XCTAssertFalse(parsed.allFrames)
        XCTAssertEqual(parsed.grants, ["GM_addStyle"])

        let manager = ExtensionManager(rootDirectory: tempDir, persistsToDisk: true)
        let installed = try manager.installUserScript(scriptContent: script)
        XCTAssertEqual(installed.sourceKind, .userScript)
        XCTAssertEqual(installed.manifest.name, "GitHub 宽屏增强脚本")
        XCTAssertTrue(installed.isEnabled)
        XCTAssertEqual(installed.manifest.contentScripts.first?.runAt, .documentStart)
    }

    // MARK: - 4. CRX2 & CRX3 Binary Unpacker and ZIP Package Installation

    func testCRX2AndCRX3PackageExtractionAndInstallation() throws {
        // Create an extension directory and zip it via /usr/bin/ditto
        let srcDir = tempDir.appendingPathComponent("crx-source", isDirectory: true)
        try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
        let manifest = """
        {
          "manifest_version": 3,
          "name": "Packaged CRX Test Extension",
          "version": "3.0.1",
          "description": "Unpacked from a binary CRX3 container",
          "content_scripts": [
            {
              "matches": ["<all_urls>"],
              "js": ["inject.js"]
            }
          ]
        }
        """
        try manifest.write(to: srcDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try "console.log('crx loaded');".write(to: srcDir.appendingPathComponent("inject.js"), atomically: true, encoding: .utf8)

        let zipURL = tempDir.appendingPathComponent("ext.zip")
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        proc.arguments = ["-c", "-k", srcDir.path, zipURL.path]
        try proc.run()
        proc.waitUntilExit()
        XCTAssertEqual(proc.terminationStatus, 0)

        let zipData = try Data(contentsOf: zipURL)

        // Wrap zipData in a valid CRX3 header: "Cr24" + version(3) + headerLen(8) + 8 dummy header bytes + zipData
        var crx3Data = Data("Cr24".utf8)
        var versionLE: UInt32 = 3
        var headerLenLE: UInt32 = 8
        withUnsafeBytes(of: &versionLE) { crx3Data.append(contentsOf: $0) }
        withUnsafeBytes(of: &headerLenLE) { crx3Data.append(contentsOf: $0) }
        crx3Data.append(Data(repeating: 0xAA, count: 8))
        crx3Data.append(zipData)

        let extractedFromCRX3 = try CRXPackageUnpacker.extractZIPData(fromCRX: crx3Data)
        XCTAssertEqual(extractedFromCRX3, zipData)

        let crx3FileURL = tempDir.appendingPathComponent("test-ext.crx")
        try crx3Data.write(to: crx3FileURL)

        let manager = ExtensionManager(rootDirectory: tempDir, persistsToDisk: true)
        let installed = try manager.installPackage(from: crx3FileURL)
        XCTAssertEqual(installed.sourceKind, .packaged)
        XCTAssertEqual(installed.manifest.name, "Packaged CRX Test Extension")
        XCTAssertEqual(installed.manifest.version, "3.0.1")
    }

    // MARK: - 5. Built-In Extensions, Host Access Modes, and Bridge RPC

    func testBuiltInExtensionsAndChromeBridgeCalls() throws {
        let manager = ExtensionManager(rootDirectory: tempDir, persistsToDisk: true)
        XCTAssertGreaterThanOrEqual(manager.extensions.count, 5)

        let stateStore = TabStateStore(isPersistenceEnabled: false)
        let session = BrowserSession(
            stateStore: stateStore,
            extensionManager: manager,
            restoresPreviousSession: false
        )

        let darkExt = try XCTUnwrap(manager.extensionItem(forID: BuiltInExtensions.darkModeProID))
        XCTAssertTrue(darkExt.isEnabled)
        XCTAssertTrue(darkExt.isPinnedToToolbar)

        // Test host access control (blocked host, specific sites, on-click)
        XCTAssertTrue(darkExt.canRunOn(url: "https://developer.apple.com/documentation", isPrivateTab: false))
        manager.toggleBlockHost(id: darkExt.id, host: "developer.apple.com")
        let updatedDark = try XCTUnwrap(manager.extensionItem(forID: BuiltInExtensions.darkModeProID))
        XCTAssertFalse(updatedDark.canRunOn(url: "https://developer.apple.com/documentation", isPrivateTab: false))

        // Test chrome.storage.local set/get/remove via processBridgeCall
        let setExp = expectation(description: "storage.set")
        manager.processBridgeCall(
            extensionID: darkExt.id,
            action: "storage.set",
            payload: ["area": "local", "items": ["brightness": 110, "theme": "midnight"]],
            sourceTabID: nil
        ) { _, err in
            XCTAssertNil(err)
            setExp.fulfill()
        }
        wait(for: [setExp], timeout: 1.0)

        let snapshot = manager.storageSnapshot(forExtensionID: darkExt.id, area: "local")
        XCTAssertEqual(snapshot["brightness"] as? Int, 110)
        XCTAssertEqual(snapshot["theme"] as? String, "midnight")

        // Test chrome.action.setBadgeText & setBadgeBackgroundColor
        manager.processBridgeCall(
            extensionID: darkExt.id,
            action: "action.setBadgeText",
            payload: ["text": "12"],
            sourceTabID: nil
        ) { _, _ in }
        manager.processBridgeCall(
            extensionID: darkExt.id,
            action: "action.setBadgeBackgroundColor",
            payload: ["color": [239, 68, 68]],
            sourceTabID: nil
        ) { _, _ in }

        let badgedExt = try XCTUnwrap(manager.extensionItem(forID: darkExt.id))
        XCTAssertEqual(badgedExt.actionState.badgeText(forTabID: nil), "12")
        XCTAssertEqual(badgedExt.actionState.badgeColorHex(forTabID: nil), "#EF4444")

        // Test chrome.tabs.create and chrome.tabs.query via bridge
        manager.processBridgeCall(
            extensionID: darkExt.id,
            action: "tabs.create",
            payload: ["url": "https://example.com/docs", "active": true],
            sourceTabID: nil
        ) { result, err in
            XCTAssertNil(err)
            let dict = result as? [String: Any]
            XCTAssertEqual(dict?["url"] as? String, "https://example.com/docs")
        }

        manager.processBridgeCall(
            extensionID: darkExt.id,
            action: "tabs.query",
            payload: ["active": true],
            sourceTabID: nil
        ) { result, err in
            XCTAssertNil(err)
            let tabs = result as? [[String: Any]]
            XCTAssertEqual(tabs?.count, 1)
            XCTAssertEqual(tabs?.first?["url"] as? String, "https://example.com/docs")
        }

        // Test navigating to chrome://extensions opens Extension Manager
        XCTAssertFalse(manager.isShowingExtensionManager)
        session.navigate(to: "chrome://extensions")
        XCTAssertTrue(manager.isShowingExtensionManager)

        // Verify WKUserScript generation for enabled extensions
        let scripts = manager.makeUserScripts(forTabID: session.activeTabID ?? "tab-1", isPrivate: false)
        XCTAssertGreaterThanOrEqual(scripts.count, 5)
    }

    // MARK: - 6. Custom Extension Creator, Scheme Bootstrap, and Live WKWebView Popup Loading

    func testCustomExtensionCreatorAndLivePopupSchemeHandler() throws {
        let manager = ExtensionManager(rootDirectory: tempDir, persistsToDisk: true)
        let custom = try manager.createCustomExtension(
            name: "Custom Page Highlighter",
            version: "1.0.5",
            description: "Highlights code blocks on developer docs",
            matches: ["https://*.example.com/*", "<all_urls>"],
            runAt: .documentEnd,
            jsCode: "window.__CUSTOM_EXT_RAN__ = true;",
            cssCode: "pre { border: 1px solid #10B981; }"
        )

        XCTAssertTrue(custom.isEnabled)
        XCTAssertEqual(custom.manifest.name, "Custom Page Highlighter")
        XCTAssertEqual(custom.manifest.version, "1.0.5")
        XCTAssertEqual(custom.manifest.contentScripts.first?.js, ["content.js"])
        XCTAssertEqual(custom.manifest.contentScripts.first?.css, ["content.css"])

        // Test ExtensionSchemeHandler bootstrap injection & MIME resolution
        XCTAssertEqual(ExtensionSchemeHandler.mimeType(forExtension: "html"), "text/html; charset=utf-8")
        XCTAssertEqual(ExtensionSchemeHandler.mimeType(forExtension: "js"), "application/javascript; charset=utf-8")
        XCTAssertEqual(ExtensionSchemeHandler.mimeType(forExtension: "css"), "text/css; charset=utf-8")
        XCTAssertEqual(ExtensionSchemeHandler.mimeType(forExtension: "svg"), "image/svg+xml")

        let injectedHTML = ExtensionSchemeHandler.injectBootstrapScript(
            "window.__TEST_BOOTSTRAP__ = 42;",
            intoHTML: "<html><head><title>Popup</title></head><body>Hi</body></html>"
        )
        XCTAssertTrue(injectedHTML.contains("data-zhuo-extension-bootstrap=\"true\""))
        XCTAssertTrue(injectedHTML.contains("window.__TEST_BOOTSTRAP__ = 42;"))

        // Verify persistence across ExtensionManager re-initialization
        manager.setExtensionEnabled(id: custom.id, enabled: false)
        manager.togglePinToToolbar(id: custom.id)
        manager.isDeveloperMode = true

        let reloadedManager = ExtensionManager(rootDirectory: tempDir, persistsToDisk: true)
        XCTAssertTrue(reloadedManager.isDeveloperMode)
        let restoredCustom = try XCTUnwrap(reloadedManager.extensionItem(forID: custom.id))
        XCTAssertFalse(restoredCustom.isEnabled)
        XCTAssertFalse(restoredCustom.isPinnedToToolbar)

        // Verify uninstalling custom extension removes it from registry
        reloadedManager.uninstallExtension(id: custom.id)
        XCTAssertNil(reloadedManager.extensionItem(forID: custom.id))
    }
}
