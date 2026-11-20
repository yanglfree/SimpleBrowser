import AppKit
import Foundation
import LocalAuthentication
import UniformTypeIdentifiers
import WebKit

/// `WKWebView` subclass that augments the native context menu for inline PDF previews
/// with explicit download and save-as actions.
public final class BrowserWKWebView: WKWebView {
    public weak var tabController: TabController?

    public override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        guard tabController?.isCurrentDocumentPDF == true else { return }

        let downloadTitle = "下载 PDF"
        let saveAsTitle = "存储 PDF 为..."
        let alreadyHasDownload = menu.items.contains { $0.title == downloadTitle || $0.title == saveAsTitle }
        guard !alreadyHasDownload else { return }

        if let lastItem = menu.items.last, !lastItem.isSeparatorItem {
            menu.addItem(.separator())
        }

        let downloadItem = NSMenuItem(
            title: downloadTitle,
            action: #selector(handleDownloadPDF(_:)),
            keyEquivalent: ""
        )
        downloadItem.target = self
        menu.addItem(downloadItem)

        let saveAsItem = NSMenuItem(
            title: saveAsTitle,
            action: #selector(handleSavePDFAs(_:)),
            keyEquivalent: ""
        )
        saveAsItem.target = self
        menu.addItem(saveAsItem)
    }

    @objc private func handleDownloadPDF(_ sender: Any?) {
        tabController?.downloadCurrentDocument()
    }

    @objc private func handleSavePDFAs(_ sender: Any?) {
        tabController?.saveCurrentDocumentAs()
    }
}

/// Manages the live WKWebView for a BrowserTab.
///
/// Two teardown-free paths keep tab switching instantaneous:
/// * the same WebView object is detached/re-attached when the tab stays inside the
///   live budget (nothing is reloaded, scroll and DOM stay exactly as they were);
/// * when the tab must be frozen, `makeSnapshot()` archives the WebKit interaction
///   state so a fresh WebView can reproduce the page without a network round trip.
public final class TabController: NSObject, WKNavigationDelegate, WKUIDelegate {
    public let tabID: String
    public private(set) var webView: WKWebView?
    public weak var session: BrowserSession?

    /// Set while a snapshot restore is in flight, so a failing/hanging restore can
    /// gracefully fall back to a normal navigation instead of leaving a blank page.
    public private(set) var isRestoringFromSnapshot: Bool = false

    /// Most recent non-blank target URL requested or committed in this tab controller.
    public private(set) var lastTargetURL: URL?

    /// Indicates that the most recent navigation attempt failed, so `reload()` should
    /// re-request `lastTargetURL` instead of calling `WKWebView.reload()` on `about:blank`.
    public private(set) var lastNavigationFailed: Bool = false

    /// Tracks whether at least one main-frame navigation has committed in this controller.
    public private(set) var hasCommittedNavigation: Bool = false

    /// MIME type of the latest main-frame navigation response (e.g. `application/pdf`).
    public private(set) var lastMainFrameMIMEType: String?

    private var restoreWatchdog: DispatchWorkItem?
    private var restoreFallbackURL: URL?
    private var shouldAutoRefreshAfterRestore: Bool = false
    private var shouldRestoreScrollAfterLoad: Bool = false
    private var lastKnownScrollPositionY: Double = 0
    private var didAttemptRestoreFallback: Bool = false

    static let restoreWatchdogTimeout: TimeInterval = 1.2
    static let scrollProbeScript = "window.scrollY || document.documentElement.scrollTop || document.body.scrollTop || 0"
    public static let safariApplicationNameForUserAgent = "Version/18.3 Safari/605.1.15"

    /// Optional closure used in unit tests or custom integrations to intercept text input prompts
    public var promptHandler: ((String, String?) -> String?)?
    /// Optional closure used in unit tests or custom integrations to intercept alert panels
    public var alertHandler: ((String) -> Void)?
    /// Optional closure used in unit tests or custom integrations to intercept confirm panels
    public var confirmHandler: ((String) -> Bool)?
    /// Optional closure used in unit tests or custom integrations to intercept auth challenges
    public var authChallengeHandler: ((URLAuthenticationChallenge) -> (URLSession.AuthChallengeDisposition, URLCredential?))?

    private var progressObservation: NSKeyValueObservation?
    private var titleObservation: NSKeyValueObservation?
    private var urlObservation: NSKeyValueObservation?
    private var canGoBackObservation: NSKeyValueObservation?
    private var canGoForwardObservation: NSKeyValueObservation?
    private let isPrivateTab: Bool
    private var hasRegisteredPageExtensionBridge: Bool = false
    private var appliedSessionStorageGeneration: Int = -1
    private var isContentProtectionBypassedForAllowlist: Bool = false

    /// - Parameters:
    ///   - initialURL: navigation target used only when no restorable snapshot exists
    ///   - restoring: frozen page state to revive without touching the network
    public init(
        tabID: String,
        session: BrowserSession,
        initialURL: URL?,
        isPrivate: Bool,
        restoring snapshot: TabStateSnapshot? = nil
    ) {
        self.tabID = tabID
        self.session = session
        self.isPrivateTab = isPrivate
        if let initialURL, !URLPolicy.isBlankURL(initialURL.absoluteString) {
            self.lastTargetURL = initialURL
        } else if let snapURL = snapshot?.url, !URLPolicy.isBlankURL(snapURL), let parsed = URL(string: snapURL) {
            self.lastTargetURL = parsed
        }
        super.init()
        setupWebView(isPrivate: isPrivate)

        let startNavigation = { [weak self] in
            guard let self else { return }
            if let snapshot, snapshot.hasRestorableState {
                self.restore(from: snapshot, fallbackURL: initialURL)
            } else if let initialURL = initialURL {
                self.load(url: initialURL)
            }
        }

        if isPrivate {
            startNavigation()
        } else {
            session.cookieSessionStore.performWhenReady(startNavigation)
        }
    }

    private func setupWebView(isPrivate: Bool) {
        let config = WKWebViewConfiguration()
        // Append standard Safari version/token so search engines (e.g. Google) do not
        // downgrade bare WKWebView User-Agent requests to legacy basic HTML pipelines.
        config.applicationNameForUserAgent = Self.safariApplicationNameForUserAgent

        // Profile-isolated or private data store
        config.websiteDataStore = isPrivate ? .nonPersistent() : (session?.websiteDataStore ?? .default())

        // Custom scheme handler for `zhuo-extension://<id>/<path>`
        let extManager = session?.extensionManager ?? ExtensionManager.shared
        config.setURLSchemeHandler(
            ExtensionSchemeHandler(extensionManager: extManager),
            forURLScheme: ExtensionSchemeHandler.scheme
        )

        // Install injected scripts & native content blocker rules according to user settings
        let userContentController = config.userContentController
        if !isPrivate {
            userContentController.add(
                WeakSessionStorageMessageHandler(target: self),
                contentWorld: .defaultClient,
                name: WebSessionStorageStore.messageHandlerName
            )
        }
        let extensionBridgeHandler = WeakExtensionBridgeMessageHandler(target: self)
        userContentController.add(
            extensionBridgeHandler,
            contentWorld: ExtensionRuntimeBridge.contentScriptWorld,
            name: ExtensionRuntimeBridge.messageHandlerName
        )
        // Extension options pages (`zhuo-extension://`) load their runtime polyfill in `.page`.
        ensurePageExtensionBridgeIfNeeded(for: lastTargetURL, on: userContentController)
        userContentController.add(
            WeakAutoFillMessageHandler(target: self),
            contentWorld: .defaultClient,
            name: "zhuoAutoFill"
        )
        applyContentProtection(to: userContentController, configuration: config)

        // Preferences for performance, video fullscreen, and safe browsing
        config.preferences.isElementFullscreenEnabled = true
        let effectiveSettings = session?.settings ?? BrowserSettings.shared
        SecurityRuntimeService.applySafeBrowsing(level: effectiveSettings.safeBrowsingLevel, to: config)
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs

        let wv = BrowserWKWebView(frame: .zero, configuration: config)
        wv.tabController = self
        wv.navigationDelegate = self
        wv.uiDelegate = self
        if #available(macOS 13.3, *) {
            wv.isInspectable = true
        }
        self.webView = wv

        // Setup KVO
        progressObservation = wv.observe(\.estimatedProgress, options: [.new]) { [weak self] _, change in
            guard let self = self, let progress = change.newValue else { return }
            self.session?.updateTab(self.tabID) { tab in
                let nextLoading = progress < 1.0
                if tab.isLoading != nextLoading || progress >= 1.0 || progress <= 0.1 || abs(progress - tab.loadingProgress) >= 0.03 {
                    tab.loadingProgress = progress
                    tab.isLoading = nextLoading
                }
            }
        }

        titleObservation = wv.observe(\.title, options: [.new]) { [weak self] webView, change in
            guard let self = self,
                  let rawTitle = change.newValue,
                  let trimmedTitle = rawTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !trimmedTitle.isEmpty else {
                return
            }
            self.session?.updateTab(self.tabID) { tab in
                tab.title = trimmedTitle
            }
            if !self.isPrivateTab,
               !self.isRestoringFromSnapshot,
               let currentURL = webView.url?.absoluteString,
               !currentURL.isEmpty,
               !URLPolicy.isBlankURL(currentURL),
               !URLPolicy.isHomeURL(currentURL) {
                self.session?.updateHistoryTitleIfNeeded(url: currentURL, title: trimmedTitle)
            }
        }

        urlObservation = wv.observe(\.url, options: [.new]) { [weak self] _, change in
            guard let self = self,
                  let url = change.newValue,
                  let resolvedURL = url,
                  !URLPolicy.isBlankURL(resolvedURL.absoluteString) else { return }
            let urlString = resolvedURL.absoluteString
            self.lastTargetURL = resolvedURL
            self.session?.updateTab(self.tabID) { tab in
                tab.url = urlString
            }
        }

        canGoBackObservation = wv.observe(\.canGoBack, options: [.new]) { [weak self] _, change in
            guard let self = self, let canGoBack = change.newValue else { return }
            self.session?.updateTab(self.tabID) { tab in
                tab.canGoBack = canGoBack
            }
        }

        canGoForwardObservation = wv.observe(\.canGoForward, options: [.new]) { [weak self] _, change in
            guard let self = self, let canGoForward = change.newValue else { return }
            self.session?.updateTab(self.tabID) { tab in
                tab.canGoForward = canGoForward
            }
        }
    }

    private func ensurePageExtensionBridgeIfNeeded(for url: URL?, on userContentController: WKUserContentController) {
        guard !hasRegisteredPageExtensionBridge,
              url?.scheme?.lowercased() == ExtensionSchemeHandler.scheme else {
            return
        }
        hasRegisteredPageExtensionBridge = true
        userContentController.add(
            WeakExtensionBridgeMessageHandler(target: self),
            contentWorld: .page,
            name: ExtensionRuntimeBridge.messageHandlerName
        )
    }

    public func applyContentProtectionSettings(evaluateLiveScripts: Bool = false) {
        guard let webView else { return }
        let userContentController = webView.configuration.userContentController
        let host = URLPolicy.rawHost(webView.url?.absoluteString ?? lastTargetURL?.absoluteString ?? session?.tab(for: tabID)?.url ?? "")
        applyContentProtection(to: userContentController, configuration: webView.configuration, host: host)

        guard evaluateLiveScripts, webView.url != nil else { return }
        let activeSettings = session?.settings ?? BrowserSettings.shared
        let isAllowlisted = activeSettings.isHostAllowlisted(host)
        if activeSettings.cosmeticCleanupEnabled && !isAllowlisted {
            if let script = InjectedScripts.shared.scriptContent(named: "content-cleanup-standard") {
                webView.evaluateJavaScript(script, in: nil, in: .defaultClient, completionHandler: nil)
            }
        } else {
            if let restoreScript = InjectedScripts.shared.scriptContent(named: "restore-hidden") {
                webView.evaluateJavaScript(restoreScript, in: nil, in: .defaultClient, completionHandler: nil)
            }
        }
        let extManager = session?.extensionManager ?? ExtensionManager.shared
        extManager.evaluateEnabledExtensions(on: webView, tabID: tabID, isPrivate: isPrivateTab)
    }

    private func applyContentProtection(
        to userContentController: WKUserContentController,
        configuration: WKWebViewConfiguration? = nil,
        host: String? = nil
    ) {
        let activeSettings = session?.settings ?? BrowserSettings.shared
        let resolvedHost = host ?? URLPolicy.rawHost(
            webView?.url?.absoluteString ?? lastTargetURL?.absoluteString ?? session?.tab(for: tabID)?.url ?? ""
        )
        let isAllowlisted = activeSettings.isHostAllowlisted(resolvedHost)
        isContentProtectionBypassedForAllowlist = isAllowlisted

        if let targetConfig = configuration ?? webView?.configuration {
            SecurityRuntimeService.applySafeBrowsing(level: activeSettings.safeBrowsingLevel, to: targetConfig)
        }

        userContentController.removeAllUserScripts()
        if !isPrivateTab {
            let sessionStorageStore = session?.webSessionStorageStore ?? WebSessionStorageStore.shared
            appliedSessionStorageGeneration = sessionStorageStore.generation
            if let sessionStorageScript = sessionStorageStore.makeBootstrapUserScript() {
                userContentController.addUserScript(sessionStorageScript)
            }
        }
        if !activeSettings.javascriptJITOptimizationEnabled {
            userContentController.addUserScript(SecurityRuntimeService.makeHardenedNoJITScript())
        }
        if activeSettings.adBlockEnabled && !isAllowlisted,
           let trackerScript = InjectedScripts.shared.makeTrackerBlockScript() {
            userContentController.addUserScript(trackerScript)
        }
        if activeSettings.cosmeticCleanupEnabled && !isAllowlisted,
           let cosmeticScript = InjectedScripts.shared.makeCosmeticCleanupScript() {
            userContentController.addUserScript(cosmeticScript)
        }
        if activeSettings.safeBrowsingLevel == .enhanced,
           let linkGuardScript = InjectedScripts.shared.makeBlockedLinkGuardScript() {
            userContentController.addUserScript(linkGuardScript)
        }
        if let autoFillScript = InjectedScripts.shared.makeAutoFillScript() {
            userContentController.addUserScript(autoFillScript)
        }

        // Install user scripts from enabled Chrome / UserScript extensions
        let extManager = session?.extensionManager ?? ExtensionManager.shared
        for extScript in extManager.makeUserScripts(forTabID: tabID, isPrivate: isPrivateTab) {
            userContentController.addUserScript(extScript)
        }

        userContentController.removeAllContentRuleLists()
        if activeSettings.adBlockEnabled && !isAllowlisted {
            ContentBlocker.shared.install(on: userContentController)
        }
    }

    private func refreshContentProtectionIfNeeded(for targetURL: URL?) {
        guard let webView else { return }
        let activeSettings = session?.settings ?? BrowserSettings.shared
        let host = URLPolicy.rawHost(targetURL?.absoluteString ?? "")
        let shouldBypass = activeSettings.isHostAllowlisted(host)
        if shouldBypass != isContentProtectionBypassedForAllowlist {
            applyContentProtection(to: webView.configuration.userContentController, configuration: webView.configuration, host: host)
        }
    }

    private func refreshSessionStorageScriptIfNeeded() {
        let sessionStorageStore = session?.webSessionStorageStore ?? WebSessionStorageStore.shared
        guard !isPrivateTab,
              let userContentController = webView?.configuration.userContentController,
              appliedSessionStorageGeneration != sessionStorageStore.generation else {
            return
        }
        applyContentProtection(to: userContentController)
    }

    public func load(url: URL) {
        guard let webView = webView else { return }
        refreshSessionStorageScriptIfNeeded()
        cancelRestoration()
        // A typed/open navigation is an explicit intent: never restore an old offset.
        shouldRestoreScrollAfterLoad = false
        var targetURL = url
        let effectiveSettings = session?.settings ?? BrowserSettings.shared
        if effectiveSettings.alwaysUseSecureConnections,
           targetURL.scheme?.lowercased() == "http",
           let upgraded = URL(string: URLPolicy.upgradeToHTTPSIfPublicHost(targetURL.absoluteString)) {
            targetURL = upgraded
        }
        refreshContentProtectionIfNeeded(for: targetURL)
        if !URLPolicy.isBlankURL(targetURL.absoluteString) {
            lastTargetURL = targetURL
            lastNavigationFailed = false
            session?.updateTab(tabID) { $0.loadErrorDescription = nil }
        }
        ensurePageExtensionBridgeIfNeeded(for: targetURL, on: webView.configuration.userContentController)
        if targetURL.isFileURL {
            webView.loadFileURL(targetURL, allowingReadAccessTo: targetURL.deletingLastPathComponent())
            return
        }
        let request = URLRequest(url: targetURL)
        webView.load(request)
    }

    public func reload() {
        guard let webView else { return }
        refreshSessionStorageScriptIfNeeded()
        cancelRestoration()
        shouldRestoreScrollAfterLoad = lastKnownScrollPositionY > 0
        session?.updateTab(tabID) { $0.isSnapshotStale = false }

        let liveURLString = webView.url?.absoluteString ?? ""
        let fallbackTabURLString = session?.tab(for: tabID)?.url ?? lastTargetURL?.absoluteString ?? ""
        let effectiveURLString = (!liveURLString.isEmpty && !URLPolicy.isBlankURL(liveURLString))
            ? liveURLString
            : fallbackTabURLString

        if !effectiveURLString.isEmpty,
           !URLPolicy.isHomeURL(effectiveURLString),
           !URLPolicy.isBlankURL(effectiveURLString) {
            let upgraded = URLPolicy.upgradeToHTTPSIfPublicHost(effectiveURLString)
            if upgraded != effectiveURLString || URLPolicy.isBlankURL(session?.tab(for: tabID)?.url ?? "") {
                session?.updateTab(tabID) { $0.url = upgraded }
            }
            if upgraded != liveURLString || lastNavigationFailed || URLPolicy.isBlankURL(liveURLString) || webView.url == nil,
               let targetURL = URL(string: upgraded) {
                load(url: targetURL)
                return
            }
        }
        webView.reload()
    }

    /// Forces a full reload from the origin server, bypassing local WebKit caches and
    /// upgrading any plain-HTTP public domain to HTTPS.
    public func reloadFromOrigin() {
        guard let webView else { return }
        refreshSessionStorageScriptIfNeeded()
        cancelRestoration()
        shouldRestoreScrollAfterLoad = lastKnownScrollPositionY > 0
        session?.updateTab(tabID) { $0.isSnapshotStale = false }

        let liveURLString = webView.url?.absoluteString ?? ""
        let fallbackTabURLString = session?.tab(for: tabID)?.url ?? lastTargetURL?.absoluteString ?? ""
        let currentURLString = (!liveURLString.isEmpty && !URLPolicy.isBlankURL(liveURLString))
            ? liveURLString
            : fallbackTabURLString
        let upgradedString = URLPolicy.upgradeToHTTPSIfPublicHost(currentURLString)
        let didUpgradeScheme = upgradedString != currentURLString
        if didUpgradeScheme || URLPolicy.isBlankURL(session?.tab(for: tabID)?.url ?? "") {
            session?.updateTab(tabID) { $0.url = upgradedString }
        }
        let host = URLPolicy.rawHost(upgradedString)

        let performReload = { [weak self, weak webView] in
            guard let webView else { return }
            let liveNow = webView.url?.absoluteString ?? ""
            let needsExplicitLoad = didUpgradeScheme
                || (self?.lastNavigationFailed ?? false)
                || webView.url == nil
                || URLPolicy.isBlankURL(liveNow)
            if needsExplicitLoad, let targetURL = URL(string: upgradedString), !upgradedString.isEmpty {
                self?.lastTargetURL = targetURL
                self?.lastNavigationFailed = false
                let request = URLRequest(url: targetURL, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
                webView.load(request)
            } else if webView.url != nil {
                webView.reloadFromOrigin()
            }
        }

        let cacheTypes: Set<String> = [
            WKWebsiteDataTypeDiskCache,
            WKWebsiteDataTypeMemoryCache,
            WKWebsiteDataTypeFetchCache
        ]
        let store = webView.configuration.websiteDataStore
        if !host.isEmpty {
            store.fetchDataRecords(ofTypes: cacheTypes) { records in
                let matching = records.filter { record in
                    let name = record.displayName.lowercased()
                    return host == name || host.hasSuffix("." + name) || name.hasSuffix("." + host)
                }
                guard !matching.isEmpty else {
                    performReload()
                    return
                }
                store.removeData(ofTypes: cacheTypes, for: matching) {
                    performReload()
                }
            }
        } else {
            performReload()
        }
    }

    public func zoomIn() {
        guard let webView else { return }
        webView.pageZoom = min(3.0, (webView.pageZoom * 10 + 1).rounded() / 10)
    }

    public func zoomOut() {
        guard let webView else { return }
        webView.pageZoom = max(0.5, (webView.pageZoom * 10 - 1).rounded() / 10)
    }

    public func resetZoom() {
        guard let webView else { return }
        webView.pageZoom = 1.0
    }

    public func goBack() {
        webView?.goBack()
    }

    public func goForward() {
        webView?.goForward()
    }

    public func stopLoading() {
        webView?.stopLoading()
    }

    public func find(query: String, forward: Bool = true) {
        guard let webView else { return }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let config = WKFindConfiguration()
        config.backwards = !forward
        config.caseSensitive = false
        config.wraps = true
        webView.find(trimmed, configuration: config) { _ in }
    }

    public func printCurrentDocument() {
        guard let webView else { return }
        let printInfo = NSPrintInfo.shared
        let operation = webView.printOperation(with: printInfo)
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        if let window = webView.window {
            operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        } else {
            operation.run()
        }
    }

    // MARK: - Snapshot / Restore

    /// Captures the page state synchronously (interaction state read is cheap and
    /// main-thread safe), which is what makes "freeze without losing anything" work.
    public func makeSnapshot(scrollPositionY: Double? = nil) -> TabStateSnapshot? {
        guard let webView else { return nil }
        let tab = session?.tab(for: tabID)
        let liveURL = webView.url?.absoluteString ?? ""
        let fallbackURL = tab?.url ?? lastTargetURL?.absoluteString ?? ""
        let resolvedURL: String
        if !liveURL.isEmpty && !URLPolicy.isBlankURL(liveURL) {
            resolvedURL = liveURL
        } else if !URLPolicy.isBlankURL(fallbackURL) {
            resolvedURL = fallbackURL
        } else {
            resolvedURL = ""
        }
        guard !resolvedURL.isEmpty else { return nil }
        let hasValidLiveDocument = !liveURL.isEmpty && !URLPolicy.isBlankURL(liveURL) && !lastNavigationFailed
        let rawState = hasValidLiveDocument ? webView.interactionState : nil
        return TabStateSnapshot(
            url: resolvedURL,
            title: webView.title ?? tab?.title ?? "",
            scrollPositionY: scrollPositionY ?? lastKnownScrollPositionY,
            canGoBack: webView.canGoBack,
            canGoForward: webView.canGoForward,
            capturedAt: Date(),
            interactionState: InteractionStateCodec.encode(rawState),
            rawInteractionState: rawState
        )
    }

    /// Captures a snapshot and additionally probes the live scroll offset.
    ///
    /// The probe is bounded by `timeout` so a wedged content process can never block
    /// freezing; the caller destroys the WebView only after `completion` returns,
    /// which removes the previous race where the scroll read happened after teardown.
    public func captureSnapshotWithScrollPosition(
        timeout: TimeInterval = 0.25,
        completion: @escaping (TabStateSnapshot?) -> Void
    ) {
        guard let webView, let base = makeSnapshot() else {
            completion(nil)
            return
        }

        var finished = false
        let finish: (Double?) -> Void = { [weak self] probedY in
            guard !finished else { return }
            finished = true
            guard let probedY else {
                completion(base)
                return
            }
            self?.lastKnownScrollPositionY = probedY
            completion(base.withScrollPosition(probedY))
        }

        webView.evaluateJavaScript(Self.scrollProbeScript) { result, _ in
            finish((result as? NSNumber)?.doubleValue)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
            finish(nil)
        }
    }

    /// Revives a frozen page from its interaction archive — no network navigation.
    @discardableResult
    public func restore(from snapshot: TabStateSnapshot, fallbackURL: URL?) -> TabRestorePolicy.Strategy {
        guard let webView else { return .reload }

        let strategy = TabRestorePolicy.decide(hasLiveWebView: false, snapshot: snapshot)
        lastKnownScrollPositionY = snapshot.scrollPositionY
        shouldRestoreScrollAfterLoad = snapshot.scrollPositionY > 0
        restoreFallbackURL = fallbackURL
        didAttemptRestoreFallback = false
        shouldAutoRefreshAfterRestore = (strategy == .restoreStateThenRefresh)

        // When an archived snapshot has already expired (>1h), load the URL directly
        // instead of briefly mounting a stale interactionState whose cached JS could
        // overwrite newer localStorage/sessionStorage auth state before reloading.
        if strategy == .restoreStateThenRefresh,
           let targetURL = fallbackURL ?? URL(string: snapshot.url) {
            load(url: targetURL)
            shouldRestoreScrollAfterLoad = snapshot.scrollPositionY > 0
            return strategy
        }

        guard strategy.restoresFromSnapshot,
              let archivableState = snapshot.restorableInteractionState() else {
            if let fallbackURL {
                load(url: fallbackURL)
            }
            return .reload
        }

        isRestoringFromSnapshot = true
        webView.interactionState = archivableState
        scheduleRestoreWatchdog()
        return strategy
    }

    /// Restores the scroll position after webview recreation
    public func restoreScrollPosition(_ y: Double) {
        guard y > 0, let webView else { return }
        let js = "window.scrollTo(0, \(y));"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    private func scheduleRestoreWatchdog() {
        restoreWatchdog?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isRestoringFromSnapshot else { return }
            self.isRestoringFromSnapshot = false
            // A restore that never produced a URL or ended on about:blank silently failed
            // (corrupt/stale archive): fall back to a real navigation instead of showing a blank page.
            let currentWebURL = self.webView?.url?.absoluteString ?? ""
            if self.webView?.url == nil || URLPolicy.isBlankURL(currentWebURL),
               let fallback = self.restoreFallbackURL ?? self.lastTargetURL {
                self.restoreFallbackURL = nil
                self.load(url: fallback)
            }
        }
        restoreWatchdog = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.restoreWatchdogTimeout, execute: work)
    }

    private func cancelRestoration() {
        restoreWatchdog?.cancel()
        restoreWatchdog = nil
        isRestoringFromSnapshot = false
        shouldAutoRefreshAfterRestore = false
    }

    /// Completely destroys the WKWebView and its observers to release memory to the system
    public func destroy() {
        cancelRestoration()
        progressObservation?.invalidate()
        titleObservation?.invalidate()
        urlObservation?.invalidate()
        canGoBackObservation?.invalidate()
        canGoForwardObservation?.invalidate()

        progressObservation = nil
        titleObservation = nil
        urlObservation = nil
        canGoBackObservation = nil
        canGoForwardObservation = nil

        AutoFillPopoverController.shared.dismiss()
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.uiDelegate = nil
        if !isPrivateTab {
            webView?.configuration.userContentController.removeScriptMessageHandler(
                forName: WebSessionStorageStore.messageHandlerName,
                contentWorld: .defaultClient
            )
        }
        webView?.configuration.userContentController.removeScriptMessageHandler(
            forName: ExtensionRuntimeBridge.messageHandlerName,
            contentWorld: ExtensionRuntimeBridge.contentScriptWorld
        )
        if hasRegisteredPageExtensionBridge {
            webView?.configuration.userContentController.removeScriptMessageHandler(
                forName: ExtensionRuntimeBridge.messageHandlerName,
                contentWorld: .page
            )
            hasRegisteredPageExtensionBridge = false
        }
        webView?.configuration.userContentController.removeScriptMessageHandler(
            forName: "zhuoAutoFill",
            contentWorld: .defaultClient
        )
        webView?.configuration.userContentController.removeAllUserScripts()
        webView?.removeFromSuperview()
        webView = nil
        hasCommittedNavigation = false
        lastMainFrameMIMEType = nil
    }

    // MARK: - Document Save & Download

    public var isCurrentDocumentPDF: Bool {
        Self.isPDFDocument(mimeType: lastMainFrameMIMEType, url: webView?.url ?? lastTargetURL)
    }

    public static func isPDFDocument(mimeType: String?, url: URL?) -> Bool {
        if let mime = mimeType?.lowercased(), mime == "application/pdf" {
            return true
        }
        return url?.pathExtension.lowercased() == "pdf"
    }

    public static func shouldCloseTransientDownloadTab(
        hasCommittedNavigation: Bool,
        canGoBack: Bool,
        backListEmpty: Bool,
        hasCurrentBackForwardItem: Bool
    ) -> Bool {
        !hasCommittedNavigation && !canGoBack && backListEmpty && !hasCurrentBackForwardItem
    }

    public func downloadCurrentDocument() {
        guard let webView,
              let url = webView.url ?? lastTargetURL,
              !URLPolicy.isBlankURL(url.absoluteString),
              !URLPolicy.isHomeURL(url.absoluteString) else {
            return
        }
        webView.startDownload(using: URLRequest(url: url)) { wkDownload in
            MainActor.assumeIsolated {
                DownloadManager.shared.handleWebKitDownload(wkDownload, fallbackURL: url)
            }
        }
    }

    public func saveCurrentDocumentAs() {
        guard let webView,
              let url = webView.url ?? lastTargetURL,
              !URLPolicy.isBlankURL(url.absoluteString),
              !URLPolicy.isHomeURL(url.absoluteString) else {
            return
        }

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.pdf]

        let rawTitle = (webView.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let urlFilename = url.lastPathComponent
        let baseName: String
        if isCurrentDocumentPDF {
            if !urlFilename.isEmpty, urlFilename != "/" {
                baseName = urlFilename.lowercased().hasSuffix(".pdf") ? urlFilename : "\(urlFilename).pdf"
            } else if !rawTitle.isEmpty {
                baseName = rawTitle.lowercased().hasSuffix(".pdf") ? rawTitle : "\(rawTitle).pdf"
            } else {
                baseName = "document.pdf"
            }
        } else {
            let stem = !rawTitle.isEmpty ? rawTitle : (url.host ?? "page")
            baseName = stem.lowercased().hasSuffix(".pdf") ? stem : "\(stem).pdf"
        }
        panel.nameFieldStringValue = DownloadPolicy.sanitizeFilename(baseName, fallback: "document.pdf")

        let presentPanel: () -> Void = {
            if let window = webView.window {
                panel.beginSheetModal(for: window) { [weak self, weak webView] response in
                    guard response == .OK, let destinationURL = panel.url, let self, let webView else { return }
                    self.performSave(of: webView, sourceURL: url, to: destinationURL)
                }
            } else if panel.runModal() == .OK, let destinationURL = panel.url {
                self.performSave(of: webView, sourceURL: url, to: destinationURL)
            }
        }
        presentPanel()
    }

    private func performSave(of webView: WKWebView, sourceURL: URL, to destinationURL: URL) {
        if isCurrentDocumentPDF {
            webView.startDownload(using: URLRequest(url: sourceURL)) { wkDownload in
                MainActor.assumeIsolated {
                    DownloadManager.shared.handleWebKitDownload(
                        wkDownload,
                        fallbackURL: sourceURL,
                        customDestinationURL: destinationURL
                    )
                }
            }
            return
        }

        let pdfConfig = WKPDFConfiguration()
        webView.createPDF(configuration: pdfConfig) { result in
            if case .success(let data) = result {
                try? data.write(to: destinationURL, options: .atomic)
            }
        }
    }

    // MARK: - WKNavigationDelegate

    public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        AutoFillPopoverController.shared.dismiss()
        lastMainFrameMIMEType = nil
        session?.updateTab(tabID) { tab in
            tab.isLoading = true
            tab.loadingProgress = 0.1
            tab.loadErrorDescription = nil
        }
    }

    public func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        hasCommittedNavigation = true
        session?.updateTab(tabID) { tab in
            tab.loadErrorDescription = nil
        }
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        restoreWatchdog?.cancel()
        restoreWatchdog = nil
        let wasRestoring = isRestoringFromSnapshot
        isRestoringFromSnapshot = false

        let finishedURL = webView.url?.absoluteString ?? ""
        if URLPolicy.isBlankURL(finishedURL) {
            if wasRestoring, !didAttemptRestoreFallback,
               let fallback = restoreFallbackURL ?? lastTargetURL ?? session?.tab(for: tabID).flatMap({ URL(string: $0.url) }),
               !URLPolicy.isBlankURL(fallback.absoluteString),
               !URLPolicy.isHomeURL(fallback.absoluteString) {
                didAttemptRestoreFallback = true
                restoreFallbackURL = nil
                load(url: fallback)
                return
            }
            session?.updateTab(tabID) { tab in
                tab.isLoading = false
                tab.loadingProgress = 1.0
                if URLPolicy.isBlankURL(tab.url),
                   let preserved = self.lastTargetURL?.absoluteString,
                   !URLPolicy.isBlankURL(preserved) {
                    tab.url = preserved
                }
            }
            return
        }

        restoreFallbackURL = nil
        didAttemptRestoreFallback = false
        lastNavigationFailed = false
        if let committedURL = webView.url {
            lastTargetURL = committedURL
        }

        let resolvedTitle = (webView.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let restoredScrollY = lastKnownScrollPositionY
        session?.updateTab(tabID) { tab in
            tab.isLoading = false
            tab.loadingProgress = 1.0
            if !resolvedTitle.isEmpty {
                tab.title = resolvedTitle
            }
            if !finishedURL.isEmpty {
                tab.url = finishedURL
            }
            if wasRestoring {
                tab.isHibernated = false
                // Keep the stale marker: it describes the snapshot we just revived and
                // should survive until a real navigation brings fresh content.
            } else {
                tab.isSnapshotStale = false
            }
            if restoredScrollY > 0 {
                tab.scrollPositionY = restoredScrollY
            }
        }

        // Record browsing history for real navigations only. Reviving a frozen page is
        // not a visit and must not inflate history counters.
        if !wasRestoring, let tab = session?.tab(for: tabID), !tab.isPrivate && !tab.isHome {
            session?.recordHistory(url: tab.url, title: resolvedTitle)
        }

        // Restore scroll position only for snapshot revival / explicit reloads, never
        // for a fresh navigation (that would jump a brand-new page to an old offset).
        if shouldRestoreScrollAfterLoad, lastKnownScrollPositionY > 0 {
            shouldRestoreScrollAfterLoad = false
            restoreScrollPosition(lastKnownScrollPositionY)
        }

        // A long-frozen page is shown instantly and then refreshed transparently so the
        // user never stares at a spinner but also never keeps week-old content.
        if wasRestoring, shouldAutoRefreshAfterRestore {
            shouldAutoRefreshAfterRestore = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                guard let self, let webView = self.webView, webView.url != nil else { return }
                self.shouldRestoreScrollAfterLoad = true
                webView.reload()
            }
        }

        resolveSiteIcon()
    }

    public func resolveSiteIcon() {
        guard let session, let tab = session.tab(for: tabID), !tab.isPrivate, !tab.isHome else { return }
        guard let script = InjectedScripts.shared.scriptContent(named: "read-favicon") else { return }
        webView?.evaluateJavaScript(script) { [weak self] result, _ in
            guard let self else { return }
            let declaredURL = (result as? String) ?? ""
            self.session?.refreshSiteIcon(tabID: self.tabID, declaredURL: declaredURL)
        }
    }

    /// Extracts the failing navigation URL from a WebKit / NSURLError failure payload.
    public static func extractFailingURL(from error: Error) -> URL? {
        let nsError = error as NSError
        if let failingURL = nsError.userInfo[NSURLErrorFailingURLErrorKey] as? URL,
           !URLPolicy.isBlankURL(failingURL.absoluteString) {
            return failingURL
        }
        if let failingString = nsError.userInfo[NSURLErrorFailingURLStringErrorKey] as? String,
           !URLPolicy.isBlankURL(failingString),
           let parsed = URL(string: failingString) {
            return parsed
        }
        return nil
    }

    public static func userFacingErrorMessage(for error: Error) -> String? {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            return nil
        }
        // WebKit frame-load interrupted by policy change (e.g. download handoff)
        if nsError.domain == "WebKitErrorDomain" && nsError.code == 102 {
            return nil
        }
        switch (nsError.domain, nsError.code) {
        case (NSURLErrorDomain, NSURLErrorNotConnectedToInternet):
            return "似乎已断开与互联网的连接，请检查网络设置后重试。"
        case (NSURLErrorDomain, NSURLErrorCannotFindHost), (NSURLErrorDomain, NSURLErrorDNSLookupFailed):
            return "找不到该服务器域名，请检查网址拼写或 DNS 设置。"
        case (NSURLErrorDomain, NSURLErrorTimedOut):
            return "请求超时，目标服务器响应时间过长。"
        case (NSURLErrorDomain, NSURLErrorSecureConnectionFailed),
             (NSURLErrorDomain, NSURLErrorServerCertificateUntrusted),
             (NSURLErrorDomain, NSURLErrorServerCertificateHasBadDate),
             (NSURLErrorDomain, NSURLErrorServerCertificateHasUnknownRoot):
            return "安全连接 (HTTPS) 验证失败，证书不受信任或已过期。"
        default:
            return nsError.localizedDescription.isEmpty ? "无法打开该网页。" : nsError.localizedDescription
        }
    }

    /// Handles a navigation failure while preserving the intended target URL on the tab
    /// so the address bar never reverts to `about:blank` and `Cmd+R` can retry the URL.
    public func handleNavigationFailure(_ error: Error, wasRestoring: Bool = false) {
        restoreWatchdog?.cancel()
        restoreWatchdog = nil
        isRestoringFromSnapshot = false
        lastNavigationFailed = true

        if let failingURL = Self.extractFailingURL(from: error) {
            lastTargetURL = failingURL
        }

        let willFallbackFromRestore = wasRestoring && !didAttemptRestoreFallback && restoreFallbackURL != nil
        let errorMessage = willFallbackFromRestore ? nil : Self.userFacingErrorMessage(for: error)

        let preservedURLString = lastTargetURL?.absoluteString
        session?.updateTab(tabID) { tab in
            tab.isLoading = false
            if let errorMessage {
                tab.loadErrorDescription = errorMessage
            }
            if let preserved = preservedURLString,
               !preserved.isEmpty,
               !URLPolicy.isBlankURL(preserved),
               (tab.url.isEmpty || URLPolicy.isBlankURL(tab.url) || tab.url != preserved) {
                tab.url = preserved
            }
        }

        // A failed restore must degrade into a normal load, silently and exactly once.
        if wasRestoring, !didAttemptRestoreFallback, let fallback = restoreFallbackURL {
            didAttemptRestoreFallback = true
            restoreFallbackURL = nil
            load(url: fallback)
        }
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleNavigationFailure(error, wasRestoring: false)
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let wasRestoring = isRestoringFromSnapshot
        handleNavigationFailure(error, wasRestoring: wasRestoring)
    }

    public func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if navigationAction.shouldPerformDownload {
            decisionHandler(.download)
            return
        }
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            if !URLPolicy.isBlankURL(url.absoluteString) {
                lastTargetURL = url
                lastNavigationFailed = false
                MainActor.assumeIsolated {
                    if OAuthPolicy.isOAuthOrLoginURL(url) {
                        WebPopupWindowManager.shared.openPopup(
                            url: url,
                            parentWindow: webView.window,
                            websiteDataStore: webView.configuration.websiteDataStore
                        )
                    } else {
                        session?.createTab(url: url.absoluteString, select: true)
                    }
                }
            }
            decisionHandler(.cancel)
            return
        }
        if navigationAction.targetFrame?.isMainFrame == true,
           let url = navigationAction.request.url,
           !URLPolicy.isBlankURL(url.absoluteString) {
            // Divert explicit OAuth popup requests (e.g. `ux_mode=popup`) to standalone popup window
            // so they don't hijack the main tab and render blank due to missing window.opener.
            if let query = url.query?.lowercased(), query.contains("ux_mode=popup") || query.contains("display=popup") {
                decisionHandler(.cancel)
                MainActor.assumeIsolated {
                    _ = WebPopupWindowManager.shared.openPopup(
                        url: url,
                        parentWindow: webView.window,
                        websiteDataStore: webView.configuration.websiteDataStore
                    )
                }
                return
            }

            let effectiveSettings = session?.settings ?? BrowserSettings.shared
            if effectiveSettings.alwaysUseSecureConnections,
               url.scheme?.lowercased() == "http",
               let host = url.host,
               !URLPolicy.isLocalOrIPHost(host),
               let upgraded = URL(string: URLPolicy.upgradeToHTTPSIfPublicHost(url.absoluteString)),
               upgraded != url {
                decisionHandler(.cancel)
                load(url: upgraded)
                return
            }
            lastTargetURL = url
            refreshContentProtectionIfNeeded(for: url)
            ensurePageExtensionBridgeIfNeeded(for: url, on: webView.configuration.userContentController)
        }
        decisionHandler(.allow)
    }

    public func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        if navigationResponse.isForMainFrame {
            lastMainFrameMIMEType = navigationResponse.response.mimeType?.lowercased()
        }
        if DownloadPolicy.shouldDownloadResponse(
            navigationResponse.response,
            canShowMIMEType: navigationResponse.canShowMIMEType
        ) {
            decisionHandler(.download)
            return
        }
        decisionHandler(.allow)
    }

    public func webView(
        _ webView: WKWebView,
        navigationAction: WKNavigationAction,
        didBecome download: WKDownload
    ) {
        session?.updateTab(tabID) { tab in
            tab.isLoading = false
        }
        let fallbackURL = navigationAction.request.url
        MainActor.assumeIsolated {
            DownloadManager.shared.handleWebKitDownload(download, fallbackURL: fallbackURL)
            closeIfTransientDownloadTab()
        }
    }

    public func webView(
        _ webView: WKWebView,
        navigationResponse: WKNavigationResponse,
        didBecome download: WKDownload
    ) {
        session?.updateTab(tabID) { tab in
            tab.isLoading = false
        }
        let fallbackURL = navigationResponse.response.url
        MainActor.assumeIsolated {
            DownloadManager.shared.handleWebKitDownload(download, fallbackURL: fallbackURL)
            closeIfTransientDownloadTab()
        }
    }

    private func closeIfTransientDownloadTab() {
        guard let webView,
              Self.shouldCloseTransientDownloadTab(
                  hasCommittedNavigation: hasCommittedNavigation,
                  canGoBack: webView.canGoBack,
                  backListEmpty: webView.backForwardList.backList.isEmpty,
                  hasCurrentBackForwardItem: webView.backForwardList.currentItem != nil
              ) else {
            return
        }
        let targetSession = session
        let targetTabID = tabID
        Task { @MainActor in
            targetSession?.closeTab(id: targetTabID, recordHistory: false)
        }
    }

    public func webView(
        _ webView: WKWebView,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if let customHandler = authChallengeHandler {
            let (disposition, credential) = customHandler(challenge)
            completionHandler(disposition, credential)
            return
        }

        let authMethod = challenge.protectionSpace.authenticationMethod
        guard authMethod == NSURLAuthenticationMethodHTTPBasic ||
              authMethod == NSURLAuthenticationMethodHTTPDigest ||
              authMethod == NSURLAuthenticationMethodDefault else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let alert = NSAlert()
        alert.messageText = "需要身份验证"
        let host = challenge.protectionSpace.host
        let realm = challenge.protectionSpace.realm ?? ""
        alert.informativeText = realm.isEmpty
            ? "\(host) 请求输入用户名和密码或访问令牌 (Token)："
            : "\(host) (\(realm)) 请求输入用户名和密码或访问令牌 (Token)："
        alert.alertStyle = .informational
        alert.addButton(withTitle: "登录")
        alert.addButton(withTitle: "取消")

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 60))
        let userField = NSTextField(frame: NSRect(x: 0, y: 32, width: 280, height: 24))
        userField.placeholderString = "用户名 / Token"
        let passField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        passField.placeholderString = "密码 / Token"
        container.addSubview(userField)
        container.addSubview(passField)
        alert.accessoryView = container

        if let window = webView.window {
            alert.beginSheetModal(for: window) { response in
                if response == .alertFirstButtonReturn {
                    let user = userField.stringValue
                    let pass = passField.stringValue
                    let credential = URLCredential(user: user, password: pass, persistence: .forSession)
                    completionHandler(.useCredential, credential)
                } else {
                    completionHandler(.cancelAuthenticationChallenge, nil)
                }
            }
            alert.window.initialFirstResponder = userField
        } else {
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                let user = userField.stringValue
                let pass = passField.stringValue
                let credential = URLCredential(user: user, password: pass, persistence: .forSession)
                completionHandler(.useCredential, credential)
            } else {
                completionHandler(.cancelAuthenticationChallenge, nil)
            }
        }
    }

    // MARK: - WKUIDelegate

    public func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        var targetURL = navigationAction.request.url
        if let currentURL = webView.url, let rawURL = targetURL, rawURL.scheme == nil {
            targetURL = URL(string: rawURL.absoluteString, relativeTo: currentURL)?.absoluteURL
        }

        if OAuthPolicy.shouldOpenAsPopup(features: windowFeatures, url: targetURL) {
            return WebPopupWindowManager.shared.presentPopup(
                configuration: configuration,
                features: windowFeatures,
                initialURL: targetURL,
                parentWindow: webView.window
            )
        }

        if let url = targetURL, !URLPolicy.isBlankURL(url.absoluteString) {
            MainActor.assumeIsolated {
                session?.createTab(url: url.absoluteString, select: true)
            }
        }
        return nil
    }

    public func webViewDidClose(_ webView: WKWebView) {
        MainActor.assumeIsolated {
            session?.closeTab(id: tabID)
        }
    }

    public func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        if let customHandler = alertHandler {
            customHandler(message)
            completionHandler()
            return
        }

        let alert = NSAlert()
        let host = frame.request.url?.host ?? webView.url?.host ?? "网页提示"
        alert.messageText = host
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "确定")

        if let window = webView.window {
            alert.beginSheetModal(for: window) { _ in
                completionHandler()
            }
        } else {
            alert.runModal()
            completionHandler()
        }
    }

    public func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        if let customHandler = confirmHandler {
            completionHandler(customHandler(message))
            return
        }

        let alert = NSAlert()
        let host = frame.request.url?.host ?? webView.url?.host ?? "网页提示"
        alert.messageText = host
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")

        if let window = webView.window {
            alert.beginSheetModal(for: window) { response in
                completionHandler(response == .alertFirstButtonReturn)
            }
        } else {
            let response = alert.runModal()
            completionHandler(response == .alertFirstButtonReturn)
        }
    }

    public func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (String?) -> Void
    ) {
        if let customHandler = promptHandler {
            completionHandler(customHandler(prompt, defaultText))
            return
        }

        let alert = NSAlert()
        let host = frame.request.url?.host ?? webView.url?.host ?? "网页提示"
        alert.messageText = host
        alert.informativeText = prompt
        alert.alertStyle = .informational
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        input.stringValue = defaultText ?? ""
        alert.accessoryView = input

        if let window = webView.window {
            alert.beginSheetModal(for: window) { response in
                if response == .alertFirstButtonReturn {
                    completionHandler(input.stringValue)
                } else {
                    completionHandler(nil)
                }
            }
            alert.window.initialFirstResponder = input
        } else {
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                completionHandler(input.stringValue)
            } else {
                completionHandler(nil)
            }
        }
    }

    public func webView(
        _ webView: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping ([URL]?) -> Void
    ) {
        let openPanel = NSOpenPanel()
        openPanel.allowsMultipleSelection = parameters.allowsMultipleSelection
        openPanel.canChooseDirectories = parameters.allowsDirectories
        openPanel.canChooseFiles = true
        if let window = webView.window {
            openPanel.beginSheetModal(for: window) { response in
                if response == .OK {
                    completionHandler(openPanel.urls)
                } else {
                    completionHandler(nil)
                }
            }
        } else {
            if openPanel.runModal() == .OK {
                completionHandler(openPanel.urls)
            } else {
                completionHandler(nil)
            }
        }
    }

    public func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {
        let resourceName: String
        switch type {
        case .camera:
            resourceName = "摄像头"
        case .microphone:
            resourceName = "麦克风"
        case .cameraAndMicrophone:
            resourceName = "摄像头和麦克风"
        @unknown default:
            resourceName = "音视频设备"
        }

        let host = origin.host.isEmpty ? (webView.url?.host ?? "此网站") : origin.host
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "“\(host)”请求使用您的\(resourceName)"
        alert.informativeText = "允许后，该网站将可以在当前会话中访问您的\(resourceName)。"
        alert.addButton(withTitle: "允许")
        alert.addButton(withTitle: "拒绝")

        if let window = webView.window {
            alert.beginSheetModal(for: window) { response in
                decisionHandler(response == .alertFirstButtonReturn ? .grant : .deny)
            }
        } else {
            let response = alert.runModal()
            decisionHandler(response == .alertFirstButtonReturn ? .grant : .deny)
        }
    }

    fileprivate func handleSessionStorageMessage(_ message: WKScriptMessage) {
        guard !isPrivateTab,
              let payload = message.body as? [String: Any],
              let origin = payload["origin"] as? String,
              let rawEntries = payload["entries"] as? [String: Any] else {
            return
        }
        var entries: [String: String] = [:]
        for (key, value) in rawEntries {
            if let str = value as? String {
                entries[key] = str
            }
        }
        let sessionStorageStore = session?.webSessionStorageStore ?? WebSessionStorageStore.shared
        sessionStorageStore.updateEntries(entries, forOrigin: origin)
    }

    fileprivate func handleExtensionBridgeMessage(_ message: WKScriptMessage) {
        let extManager = session?.extensionManager ?? ExtensionManager.shared
        extManager.handleScriptMessage(message, sourceWebView: webView, tabID: tabID)
    }

    fileprivate func handleAutoFillMessage(action: String, payload: [String: Any]) {
        guard let webView = webView else { return }

        switch action {
        case "focus":
            guard let rectDict = payload["rect"] as? [String: Any],
                  let x = (rectDict["x"] as? NSNumber)?.doubleValue,
                  let y = (rectDict["y"] as? NSNumber)?.doubleValue,
                  let width = (rectDict["width"] as? NSNumber)?.doubleValue,
                  let height = (rectDict["height"] as? NSNumber)?.doubleValue else {
                return
            }

            // Only top-level login forms get suggestions. Filling a cross-origin iframe would mean
            // broadcasting the password into frames chosen by the page, not by the user.
            let isTopFrame = (rectDict["isTopFrame"] as? Bool) ?? true
            guard isTopFrame else {
                AutoFillPopoverController.shared.dismiss()
                return
            }

            let hostname = (payload["hostname"] as? String) ?? webView.url?.host ?? ""
            let matched = CredentialStore.shared.credentials(for: hostname)

            // With no saved secret for this site, stay out of the way instead of showing a menu
            // whose only entries would have to be fabricated.
            guard !matched.isEmpty else {
                AutoFillPopoverController.shared.dismiss()
                return
            }

            AutoFillPopoverController.shared.show(
                in: webView,
                fieldRect: CGRect(x: x, y: y, width: width, height: height),
                hostname: hostname,
                credentials: matched,
                onSelect: { [weak self] credential in
                    self?.authorizeAndFill(credential)
                }
            )

        case "blur":
            AutoFillPopoverController.shared.dismiss()

        case "submitted":
            // Private browsing must not leave a password behind.
            guard !isPrivateTab else { return }
            if let user = payload["username"] as? String,
               let pass = payload["password"] as? String,
               !pass.isEmpty {
                let host = (payload["hostname"] as? String) ?? webView.url?.host ?? ""
                promptToSavePassword(hostname: host, username: user, password: pass)
            }

        default:
            break
        }
    }

    /// Releases a saved password only after Touch ID or the Mac login password confirms the person
    /// at the keyboard. Safari asks for the same proof before AutoFill inserts a password; without
    /// it, a click alone would expose the secret to anyone using an unlocked Mac.
    private func authorizeAndFill(_ credential: SavedCredential) {
        let context = LAContext()
        context.localizedFallbackTitle = "使用登录密码"
        var policyError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &policyError) else {
            NSSound.beep()
            return
        }

        context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: "自动填充 \(credential.domain) 的已保存密码"
        ) { [weak self, context] success, _ in
            // Keep the context alive until the evaluation finishes.
            _ = context
            guard success else { return }
            DispatchQueue.main.async {
                guard let self else { return }
                // Read the secret only after the user passed verification.
                guard let password = CredentialStore.shared.password(for: credential) else {
                    NSSound.beep()
                    return
                }
                self.fillCredentialIntoWebPage(credential, password: password)
            }
        }
    }

    private func fillCredentialIntoWebPage(_ credential: SavedCredential, password: String) {
        guard let webView = webView, SavedCredential.isFillablePassword(password) else { return }
        let js = """
        (() => {
            if (window.__zhuoAutoFill) {
                window.__zhuoAutoFill.fill(\(Self.javaScriptString(credential.username)), \(Self.javaScriptString(password)));
            }
        })();
        """
        webView.evaluateJavaScript(js, in: nil, in: .defaultClient, completionHandler: nil)
    }

    /// JSON-encodes a Swift string so quotes, backslashes, newlines and U+2028/U+2029 cannot break
    /// out of an injected script — passwords may legitimately contain any of them.
    private static func javaScriptString(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let encoded = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return encoded
    }

    /// Asks before writing a password into the system keychain. The old build stored every submitted
    /// password silently, including failed logins; a browser must never do that.
    private func promptToSavePassword(hostname: String, username: String, password: String) {
        guard !hostname.isEmpty, SavedCredential.isFillablePassword(password) else { return }

        let account = username.isEmpty ? "未命名账户" : username
        let isUpdate = CredentialStore.shared.hasCredential(domain: hostname, username: account)
        let activeSettings = session?.settings ?? BrowserSettings.shared
        let isCompromised = activeSettings.leakedPasswordDetectionEnabled
            && SecurityRuntimeService.isPasswordKnownCompromised(password)

        let alert = NSAlert()
        alert.alertStyle = isCompromised ? .warning : .informational
        alert.messageText = isUpdate
            ? "要更新“\(hostname)”的密码吗？"
            : "要存储“\(hostname)”的密码吗？"
        var details = "账户：\(account)\n密码将保存到 macOS 登录钥匙串（钥匙串访问 → 密码），只有本应用可以读取。"
        if isCompromised {
            details += "\n\n⚠️ 安全预警：检测到此密码属于常见高危或已知泄露弱口令，建议登录后尽快更换为独立强密码。"
        }
        alert.informativeText = details
        alert.addButton(withTitle: isUpdate ? "更新密码" : "存储密码")
        alert.addButton(withTitle: "稍后")

        let save = {
            CredentialStore.shared.save(domain: hostname, username: account, password: password)
        }

        if let window = webView?.window {
            alert.beginSheetModal(for: window) { response in
                if response == .alertFirstButtonReturn { _ = save() }
            }
        } else if alert.runModal() == .alertFirstButtonReturn {
            _ = save()
        }
    }
}

private final class WeakAutoFillMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var target: TabController?

    init(target: TabController) {
        self.target = target
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? [String: Any],
              let action = body["action"] as? String else { return }
        target?.handleAutoFillMessage(action: action, payload: body)
    }
}

private final class WeakSessionStorageMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var target: TabController?

    init(target: TabController) {
        self.target = target
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        target?.handleSessionStorageMessage(message)
    }
}

private final class WeakExtensionBridgeMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var target: TabController?

    init(target: TabController) {
        self.target = target
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        target?.handleExtensionBridgeMessage(message)
    }
}
