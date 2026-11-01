import AppKit
import Foundation
import WebKit

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
            CookieSessionStore.shared.performWhenReady(startNavigation)
        }
    }

    private func setupWebView(isPrivate: Bool) {
        let config = WKWebViewConfiguration()
        // Append standard Safari version/token so search engines (e.g. Google) do not
        // downgrade bare WKWebView User-Agent requests to legacy basic HTML pipelines.
        config.applicationNameForUserAgent = Self.safariApplicationNameForUserAgent

        // Shared or private data store
        config.websiteDataStore = isPrivate ? .nonPersistent() : .default()

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
                name: WebSessionStorageStore.messageHandlerName
            )
        }
        userContentController.add(
            WeakExtensionBridgeMessageHandler(target: self),
            name: ExtensionRuntimeBridge.messageHandlerName
        )
        applyContentProtection(to: userContentController)

        // Initialize passkey manager authorization check
        Task { @MainActor in
            _ = await PasskeyManager.shared.requestAuthorizationIfNeeded()
        }

        // Preferences for performance
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs

        let wv = WKWebView(frame: .zero, configuration: config)
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

        titleObservation = wv.observe(\.title, options: [.new]) { [weak self] _, change in
            guard let self = self, let title = change.newValue, let title = title, !title.isEmpty else { return }
            self.session?.updateTab(self.tabID) { tab in
                tab.title = title
            }
        }

        urlObservation = wv.observe(\.url, options: [.new]) { [weak self] _, change in
            guard let self = self, let url = change.newValue, let urlString = url?.absoluteString else { return }
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

    public func applyContentProtectionSettings(evaluateLiveScripts: Bool = false) {
        guard let userContentController = webView?.configuration.userContentController else { return }
        applyContentProtection(to: userContentController)

        guard evaluateLiveScripts, let webView, webView.url != nil else { return }
        let cosmeticEnabled = session?.settings.cosmeticCleanupEnabled ?? BrowserSettings.shared.cosmeticCleanupEnabled
        if cosmeticEnabled {
            if let script = InjectedScripts.shared.scriptContent(named: "content-cleanup-standard") {
                webView.evaluateJavaScript(script, completionHandler: nil)
            }
        } else {
            if let restoreScript = InjectedScripts.shared.scriptContent(named: "restore-hidden") {
                webView.evaluateJavaScript(restoreScript, completionHandler: nil)
            }
        }
        let extManager = session?.extensionManager ?? ExtensionManager.shared
        extManager.evaluateEnabledExtensions(on: webView, tabID: tabID, isPrivate: isPrivateTab)
    }

    private func applyContentProtection(to userContentController: WKUserContentController) {
        let activeSettings = session?.settings ?? BrowserSettings.shared
        userContentController.removeAllUserScripts()
        if !isPrivateTab, let sessionStorageScript = WebSessionStorageStore.shared.makeBootstrapUserScript() {
            userContentController.addUserScript(sessionStorageScript)
        }
        if activeSettings.adBlockEnabled, let trackerScript = InjectedScripts.shared.makeTrackerBlockScript() {
            userContentController.addUserScript(trackerScript)
        }
        if activeSettings.cosmeticCleanupEnabled, let cosmeticScript = InjectedScripts.shared.makeCosmeticCleanupScript() {
            userContentController.addUserScript(cosmeticScript)
        }
        if let passkeyScript = InjectedScripts.shared.makePasskeyAdapterScript() {
            userContentController.addUserScript(passkeyScript)
        }

        // Install user scripts from enabled Chrome / UserScript extensions
        let extManager = session?.extensionManager ?? ExtensionManager.shared
        for extScript in extManager.makeUserScripts(forTabID: tabID, isPrivate: isPrivateTab) {
            userContentController.addUserScript(extScript)
        }

        userContentController.removeAllContentRuleLists()
        if activeSettings.adBlockEnabled {
            ContentBlocker.shared.install(on: userContentController)
        }
    }

    public func load(url: URL) {
        guard let webView = webView else { return }
        cancelRestoration()
        // A typed/open navigation is an explicit intent: never restore an old offset.
        shouldRestoreScrollAfterLoad = false
        let request = URLRequest(url: url)
        webView.load(request)
    }

    public func reload() {
        guard let webView else { return }
        cancelRestoration()
        shouldRestoreScrollAfterLoad = lastKnownScrollPositionY > 0
        session?.updateTab(tabID) { $0.isSnapshotStale = false }
        if let currentURLString = webView.url?.absoluteString ?? session?.tab(for: tabID)?.url {
            let upgraded = URLPolicy.upgradeToHTTPSIfPublicHost(currentURLString)
            if upgraded != currentURLString, let httpsURL = URL(string: upgraded) {
                session?.updateTab(tabID) { $0.url = upgraded }
                webView.load(URLRequest(url: httpsURL))
                return
            }
        }
        webView.reload()
    }

    /// Forces a full reload from the origin server, bypassing local WebKit caches and
    /// upgrading any plain-HTTP public domain to HTTPS.
    public func reloadFromOrigin() {
        guard let webView else { return }
        cancelRestoration()
        shouldRestoreScrollAfterLoad = lastKnownScrollPositionY > 0
        session?.updateTab(tabID) { $0.isSnapshotStale = false }

        let currentURLString = webView.url?.absoluteString ?? session?.tab(for: tabID)?.url ?? ""
        let upgradedString = URLPolicy.upgradeToHTTPSIfPublicHost(currentURLString)
        let didUpgradeScheme = upgradedString != currentURLString
        if didUpgradeScheme {
            session?.updateTab(tabID) { $0.url = upgradedString }
        }
        let host = URLPolicy.rawHost(upgradedString)

        let performReload = { [weak webView] in
            guard let webView else { return }
            if didUpgradeScheme, let httpsURL = URL(string: upgradedString) {
                let request = URLRequest(url: httpsURL, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
                webView.load(request)
            } else if webView.url != nil {
                webView.reloadFromOrigin()
            } else if let targetURL = URL(string: upgradedString), !upgradedString.isEmpty {
                let request = URLRequest(url: targetURL, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
                webView.load(request)
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

    // MARK: - Snapshot / Restore

    /// Captures the page state synchronously (interaction state read is cheap and
    /// main-thread safe), which is what makes "freeze without losing anything" work.
    public func makeSnapshot(scrollPositionY: Double? = nil) -> TabStateSnapshot? {
        guard let webView else { return nil }
        let tab = session?.tab(for: tabID)
        let rawState = webView.interactionState
        return TabStateSnapshot(
            url: webView.url?.absoluteString ?? tab?.url ?? "",
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
            // A restore that never produced a URL silently failed (corrupt/stale
            // archive): fall back to a real navigation instead of showing a blank page.
            if self.webView?.url == nil, let fallback = self.restoreFallbackURL {
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

        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.uiDelegate = nil
        if !isPrivateTab {
            webView?.configuration.userContentController.removeScriptMessageHandler(
                forName: WebSessionStorageStore.messageHandlerName
            )
        }
        webView?.configuration.userContentController.removeScriptMessageHandler(
            forName: ExtensionRuntimeBridge.messageHandlerName
        )
        webView?.configuration.userContentController.removeAllUserScripts()
        webView?.removeFromSuperview()
        webView = nil
    }

    // MARK: - WKNavigationDelegate

    public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        session?.updateTab(tabID) { tab in
            tab.isLoading = true
            tab.loadingProgress = 0.1
        }
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        restoreWatchdog?.cancel()
        restoreWatchdog = nil
        let wasRestoring = isRestoringFromSnapshot
        isRestoringFromSnapshot = false
        restoreFallbackURL = nil
        didAttemptRestoreFallback = false

        let restoredScrollY = lastKnownScrollPositionY
        session?.updateTab(tabID) { tab in
            tab.isLoading = false
            tab.loadingProgress = 1.0
            if let title = webView.title, !title.isEmpty {
                tab.title = title
            }
            if let url = webView.url?.absoluteString, !url.isEmpty {
                tab.url = url
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
            session?.recordHistory(url: tab.url, title: tab.title)
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

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        restoreWatchdog?.cancel()
        restoreWatchdog = nil
        isRestoringFromSnapshot = false
        session?.updateTab(tabID) { tab in
            tab.isLoading = false
        }
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        restoreWatchdog?.cancel()
        restoreWatchdog = nil
        let wasRestoring = isRestoringFromSnapshot
        isRestoringFromSnapshot = false
        session?.updateTab(tabID) { tab in
            tab.isLoading = false
        }

        // A failed restore must degrade into a normal load, silently and exactly once.
        if wasRestoring, !didAttemptRestoreFallback, let fallback = restoreFallbackURL {
            didAttemptRestoreFallback = true
            restoreFallbackURL = nil
            load(url: fallback)
        }
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
            webView.load(URLRequest(url: url))
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    public func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
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
        let fallbackURL = navigationAction.request.url
        Task { @MainActor in
            DownloadManager.shared.handleWebKitDownload(download, fallbackURL: fallbackURL)
        }
    }

    public func webView(
        _ webView: WKWebView,
        navigationResponse: WKNavigationResponse,
        didBecome download: WKDownload
    ) {
        let fallbackURL = navigationResponse.response.url
        Task { @MainActor in
            DownloadManager.shared.handleWebKitDownload(download, fallbackURL: fallbackURL)
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
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
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
        WebSessionStorageStore.shared.updateEntries(entries, forOrigin: origin)
    }

    fileprivate func handleExtensionBridgeMessage(_ message: WKScriptMessage) {
        let extManager = session?.extensionManager ?? ExtensionManager.shared
        extManager.handleScriptMessage(message, sourceWebView: webView, tabID: tabID)
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
