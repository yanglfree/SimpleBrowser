import Foundation
import WebKit

final class TabController: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    let id: String
    let isPrivate: Bool
    let webView: WKWebView
    weak var session: BrowserSession?
    private var installedRuleLists: Set<String>
    private let pageStateMessageHandler: WeakScriptMessageHandler
    private let securityMessageHandler: WeakScriptMessageHandler

    init(tab: BrowserTab, session: BrowserSession, dataStore: WKWebsiteDataStore) {
        self.id = tab.id
        self.isPrivate = tab.isPrivate
        let configuration = WebKernel.makeConfiguration(
            isPrivate: tab.isPrivate,
            dataStore: dataStore,
            blockAds: session.adsBlockEnabled(for: tab.url),
            minimumFontSize: session.settings.minimumFontSize
        )
        let pageStateMessageHandler = WeakScriptMessageHandler()
        let securityMessageHandler = WeakScriptMessageHandler()
        configuration.userContentController.add(
            pageStateMessageHandler,
            contentWorld: .defaultClient,
            name: PageStatePolicy.messageHandlerName
        )
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: PageStatePolicy.formDraftWatcherScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true,
                in: .defaultClient
            )
        )
        configuration.userContentController.add(
            securityMessageHandler,
            name: SiteSecurityPolicy.messageHandlerName
        )
        self.installedRuleLists = WebKernel.installedRuleLists(from: configuration)
        self.pageStateMessageHandler = pageStateMessageHandler
        self.securityMessageHandler = securityMessageHandler
        self.webView = WKWebView(frame: .zero, configuration: configuration)
        self.session = session
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        pageStateMessageHandler.delegate = self
        securityMessageHandler.delegate = self
        applyUserAgent(isDesktop: tab.isDesktop)
        applyWebAppearance(for: tab.url)
        if !URLPolicy.isHomeURL(tab.url) {
            let target = tab.isDesktop ? URLPolicy.desktopURL(for: tab.url) : tab.url
            load(target, rewriteDesktop: false)
        }
    }

    deinit {
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: PageStatePolicy.messageHandlerName,
            contentWorld: .defaultClient
        )
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: SiteSecurityPolicy.messageHandlerName
        )
    }

    func load(_ raw: String, rewriteDesktop: Bool = true) {
        var address = URLPolicy.normalizeAddress(
            raw,
            engine: session?.settings.searchEngine ?? .bing,
            customTemplate: session?.settings.customSearchTemplate ?? ""
        )
        let desktop = session?.tab(id)?.isDesktop == true
        if rewriteDesktop && desktop {
            address = URLPolicy.desktopURL(for: address)
        }
        session?.update(tabID: id) { tab in
            tab.url = address
            tab.lastVisitedAt = Date().timeIntervalSince1970
            tab.isReader = false
        }
        if URLPolicy.isHomeURL(address) {
            webView.stopLoading()
            session?.update(tabID: id) { tab in
                tab.isLoading = false
                tab.canGoBack = false
                tab.canGoForward = webView.canGoForward
                tab.title = tab.isPrivate ? "无痕" : "新标签页"
            }
            return
        }
        guard let url = URL(string: address) else {
            return
        }
        applyUserAgent(isDesktop: desktop)
        webView.load(URLRequest(url: url))
    }

    func goBack() {
        if webView.canGoBack {
            webView.goBack()
            return
        }
        load(URLPolicy.homeURL)
    }

    func goForward() {
        guard webView.canGoForward else {
            return
        }
        webView.goForward()
    }

    func navigationHistory() -> [NavigationHistoryEntry] {
        let back = webView.backForwardList.backList.reversed().enumerated().map { index, item in
            NavigationHistoryEntry(
                title: item.title ?? URLPolicy.displayHost(item.url.absoluteString),
                url: item.url.absoluteString,
                offset: -(index + 1),
                direction: .back
            )
        }
        let forward = webView.backForwardList.forwardList.enumerated().map { index, item in
            NavigationHistoryEntry(
                title: item.title ?? URLPolicy.displayHost(item.url.absoluteString),
                url: item.url.absoluteString,
                offset: index + 1,
                direction: .forward
            )
        }
        return back + forward
    }

    func navigateHistory(to offset: Int) {
        guard offset != 0, let item = webView.backForwardList.item(at: offset) else {
            return
        }
        webView.go(to: item)
    }

    func reload() {
        if URLPolicy.isHomeURL(session?.tab(id)?.url ?? "") {
            return
        }
        webView.reload()
    }

    func stop() {
        webView.stopLoading()
        session?.update(tabID: id) { tab in
            tab.isLoading = false
            tab.canGoBack = webView.canGoBack
            tab.canGoForward = webView.canGoForward
        }
    }

    func applyUserAgent(isDesktop: Bool) {
        webView.customUserAgent = isDesktop ? WebKernel.desktopUserAgent : nil
    }

    func applyWebAppearance(for rawURL: String? = nil) {
        guard let session else {
            return
        }
        let url = rawURL ?? session.tab(id)?.url ?? ""
        webView.configuration.preferences.minimumFontSize = CGFloat(session.settings.minimumFontSize)
        webView.pageZoom = CGFloat(session.zoomPercent(for: url)) / 100
        if session.isWebDarkModeExcluded(for: url) {
            webView.overrideUserInterfaceStyle = .light
            return
        }
        switch session.settings.webDarkMode {
        case .system:
            webView.overrideUserInterfaceStyle = .unspecified
        case .light:
            webView.overrideUserInterfaceStyle = .light
        case .dark:
            webView.overrideUserInterfaceStyle = .dark
        }
    }

    func applyDesktopViewportIfNeeded() {
        guard session?.tab(id)?.isDesktop == true,
              let script = WebKernel.loadScript(named: "desktop-viewport") else {
            return
        }
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    func applyReader(settings: ReaderSettings, completion: @escaping (Bool) -> Void) {
        let theme = ReaderTheme.theme(for: settings.paper)
        let script = ReaderScripts.apply(
            fontSize: settings.fontSize,
            lineHeightCSS: settings.lineHeightCSS,
            paperBackground: theme.background,
            bodyColor: theme.body,
            titleColor: theme.title,
            accentColor: theme.accent
        )
        webView.evaluateJavaScript(script) { result, _ in
            let payload = Self.jsonObject(from: result)
            let status = payload?["status"] as? String
            DispatchQueue.main.async {
                completion(status == "reader")
            }
        }
    }

    func exitReader(completion: (() -> Void)? = nil) {
        webView.evaluateJavaScript(ReaderScripts.exit) { _, _ in
            DispatchQueue.main.async {
                completion?()
            }
        }
    }

    func currentScrollPosition() -> Double {
        max(0, webView.scrollView.contentOffset.y)
    }

    func captureLongScreenshot() async throws -> LongScreenshotResult {
        try await LongScreenshotService.capture(webView, isReader: session?.tab(id)?.isReader == true)
    }

    func captureFormDraft(completion: @escaping (String) -> Void) {
        webView.evaluateJavaScript(
            PageStatePolicy.captureFormDraftScript,
            in: nil,
            in: .defaultClient
        ) { result in
            let raw = (try? result.get()) as? String ?? ""
            DispatchQueue.main.async {
                completion(raw)
            }
        }
    }

    func restoreScrollPosition(_ position: Double) {
        let offset = CGPoint(x: 0, y: max(0, position))
        webView.scrollView.setContentOffset(offset, animated: false)
        webView.evaluateJavaScript(PageStatePolicy.restoreScrollScript(position: position), completionHandler: nil)
    }

    func restoreFormDraft(_ draft: String) {
        guard let script = PageStatePolicy.restoreFormDraftScript(draft) else {
            return
        }
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    func countMatches(_ query: String, completion: @escaping (Int) -> Void) {
        webView.evaluateJavaScript(ReaderScripts.findCount(query)) { result, _ in
            if let value = result as? String, let count = Int(value) {
                completion(count)
                return
            }
            if let value = result as? Int {
                completion(value)
                return
            }
            completion(0)
        }
    }

    func find(_ query: String, backwards: Bool, completion: @escaping (Bool) -> Void) {
        let configuration = WKFindConfiguration()
        configuration.backwards = backwards
        configuration.wraps = true
        configuration.caseSensitive = false
        webView.find(query, configuration: configuration) { result in
            completion(result.matchFound)
        }
    }

    func applyContentBlocker(for url: String? = nil) {
        let controller = webView.configuration.userContentController
        let target = url ?? session?.tab(id)?.url ?? ""
        if session?.adsBlockEnabled(for: target) != true {
            controller.removeAllContentRuleLists()
            installedRuleLists = []
            WebKernel.storeInstalledRuleLists([], on: webView.configuration)
            return
        }
        var installed = installedRuleLists
        ContentBlocker.shared.install(on: controller, installed: &installed)
        installedRuleLists = installed
        WebKernel.storeInstalledRuleLists(installed, on: webView.configuration)
    }

    func replaceContentBlockerLists() {
        let controller = webView.configuration.userContentController
        controller.removeAllContentRuleLists()
        installedRuleLists = []
        WebKernel.storeInstalledRuleLists([], on: webView.configuration)
        applyContentBlocker()
    }

    func runObservableBlockingPass(for rawURL: String) {
        guard let session, !session.isBlockingAllowListed(for: rawURL) else { return }
        let control = session.effectiveSiteControl(for: rawURL)
        if control.trackerBlockingEnabled, let script = WebKernel.loadScript(named: "tracker-block") {
            webView.evaluateJavaScript(script) { [weak self] result, _ in
                guard let self, let payload = Self.jsonObject(from: result) else { return }
                let stats = BlockStats(trackers: Self.integer(payload["trackers"]))
                DispatchQueue.main.async {
                    self.session?.recordObservedBlocking(tabID: self.id, url: rawURL, stats: stats)
                }
            }
        }
        if control.cosmeticCleanupEnabled {
            let name = session.settings.ruleStrength == .strict
                ? "content-cleanup-strict"
                : "content-cleanup-standard"
            if let script = WebKernel.loadScript(named: name) {
                webView.evaluateJavaScript(script) { [weak self] result, _ in
                    guard let self, let payload = Self.jsonObject(from: result) else { return }
                    let stats = BlockStats(
                        ads: Self.integer(payload["ads"]),
                        popups: Self.integer(payload["popups"]),
                        cookieBanners: Self.integer(payload["cookieBanners"])
                    )
                    DispatchQueue.main.async {
                        self.session?.recordObservedBlocking(tabID: self.id, url: rawURL, stats: stats)
                    }
                }
            }
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == SiteSecurityPolicy.messageHandlerName {
            guard message.frameInfo.isMainFrame,
                  let payload = message.body as? [String: Any],
                  payload["type"] as? String == "password-focus",
                  let url = payload["url"] as? String else {
                return
            }
            session?.handlePasswordFocus(tabID: id, url: url)
            return
        }
        guard message.name == PageStatePolicy.messageHandlerName,
              message.frameInfo.isMainFrame,
              let payload = message.body as? [String: Any],
              let url = payload["url"] as? String,
              let rawDraft = payload["draft"] as? String else {
            return
        }
        session?.updateCapturedFormDraft(tabID: id, url: url, rawDraft: rawDraft)
    }

    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {
        var kinds: [SitePermissionKind] = []
        switch type {
        case .camera:
            kinds = [.camera]
        case .microphone:
            kinds = [.microphone]
        case .cameraAndMicrophone:
            kinds = [.camera, .microphone]
        @unknown default:
            decisionHandler(.deny)
            return
        }
        session?.requestSitePermission(origin: Self.originString(origin), kinds: kinds, persist: !isPrivate) { allowed in
            decisionHandler(allowed ? .grant : .deny)
        }
    }

    func webView(
        _ webView: WKWebView,
        requestGeolocationPermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {
        session?.requestSitePermission(origin: Self.originString(origin), kinds: [.location], persist: !isPrivate) { allowed in
            decisionHandler(allowed ? .grant : .deny)
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if let rawURL = navigationAction.request.url?.absoluteString {
            let sourceURL = session?.tab(id)?.url ?? webView.url?.absoluteString ?? ""
            let externalDecision = ExternalProtocolPolicy.decision(for: rawURL, sourceURL: sourceURL)
            if externalDecision != .allow {
                if navigationAction.targetFrame?.isMainFrame != false {
                    _ = session?.handleExternalNavigation(rawURL, sourceURL: sourceURL)
                }
                decisionHandler(.cancel)
                return
            }
        }
        if navigationAction.targetFrame?.isMainFrame == true {
            if let url = navigationAction.request.url?.absoluteString {
                applyContentBlocker(for: url)
                applyWebAppearance(for: url)
                session?.prepareNavigation(tabID: id, to: url)
            }
            if navigationAction.navigationType != .reload {
                switch navigationAction.navigationType {
                case .other:
                    break
                default:
                    session?.update(tabID: id) { tab in
                        tab.isReader = false
                    }
                }
            }
        }
        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard navigationAction.targetFrame == nil,
              let rawURL = navigationAction.request.url?.absoluteString,
              ExternalProtocolPolicy.decision(for: rawURL, sourceURL: webView.url?.absoluteString ?? "") == .allow else {
            return nil
        }
        load(rawURL)
        return nil
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        if Self.shouldDownload(navigationResponse) {
            decisionHandler(.download)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        session?.downloads.begin(download, sourceURL: navigationResponse.response.url?.absoluteString ?? "")
        session?.flash("已开始下载")
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        session?.downloads.begin(download, sourceURL: navigationAction.request.url?.absoluteString ?? "")
        session?.flash("已开始下载")
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        session?.resetObservedBlocking(tabID: id)
        session?.update(tabID: id) { tab in
            tab.isLoading = true
            if let url = webView.url?.absoluteString, !url.isEmpty {
                tab.url = url
            }
            tab.canGoBack = webView.canGoBack
            tab.canGoForward = webView.canGoForward
            tab.lastVisitedAt = Date().timeIntervalSince1970
            tab.loadError = .none
            tab.securityState = SiteSecurityPolicy.provisionalState(
                for: webView.url?.absoluteString ?? tab.url
            )
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        session?.update(tabID: id) { tab in
            tab.isLoading = false
            if let url = webView.url?.absoluteString, !url.isEmpty {
                tab.url = url
            }
            if let title = webView.title, !title.isEmpty {
                tab.title = title
            }
            tab.canGoBack = webView.canGoBack
            tab.canGoForward = webView.canGoForward
            tab.loadError = .none
            tab.securityState = SiteSecurityPolicy.state(
                for: webView.url?.absoluteString ?? tab.url,
                hasOnlySecureContent: webView.hasOnlySecureContent
            )
        }
        applyDesktopViewportIfNeeded()
        let finishedURL = webView.url?.absoluteString ?? session?.tab(id)?.url ?? ""
        runObservableBlockingPass(for: finishedURL)
        if session?.tab(id)?.isReader == true {
            let settings = session?.readerSettings ?? ReaderSettings()
            applyReader(settings: settings) { [weak self] ok in
                guard let self else {
                    return
                }
                if !ok {
                    self.session?.update(tabID: self.id) { tab in
                        tab.isReader = false
                    }
                }
                self.session?.restorePageStateAfterLoad(tabID: self.id)
            }
        } else {
            session?.restorePageStateAfterLoad(tabID: id)
        }
        if let tab = session?.tab(id) {
            session?.recordVisit(of: tab)
        }
        session?.handleFinishedPageLoad(tabID: id)
        session?.persist()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        let loadError = PageLoadErrorKind.classify(error)
        session?.update(tabID: id) { tab in
            tab.isLoading = false
            tab.canGoBack = webView.canGoBack
            tab.canGoForward = webView.canGoForward
            if loadError != .none {
                tab.loadError = loadError
            }
            if loadError == .certificate || SiteSecurityPolicy.isCertificateError(error) {
                tab.securityState = .certificateError
            }
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let loadError = PageLoadErrorKind.classify(error)
        session?.update(tabID: id) { tab in
            tab.isLoading = false
            tab.canGoBack = webView.canGoBack
            tab.canGoForward = webView.canGoForward
            if loadError != .none {
                tab.loadError = loadError
            }
            if loadError == .certificate || SiteSecurityPolicy.isCertificateError(error) {
                tab.securityState = .certificateError
            }
        }
    }

    private static func originString(_ origin: WKSecurityOrigin) -> String {
        SitePermissionPolicy.origin(protocol: origin.protocol, host: origin.host, port: Int(origin.port))
    }

    private static func shouldDownload(_ response: WKNavigationResponse) -> Bool {
        if !response.canShowMIMEType {
            return true
        }
        guard let http = response.response as? HTTPURLResponse else {
            return false
        }
        let disposition = http.value(forHTTPHeaderField: "Content-Disposition")?.lowercased() ?? ""
        return disposition.contains("attachment")
    }

    private static func jsonObject(from result: Any?) -> [String: Any]? {
        if let object = result as? [String: Any] {
            return object
        }
        guard let text = result as? String, let data = text.data(using: .utf8) else {
            return nil
        }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func integer(_ value: Any?) -> Int {
        if let value = value as? Int { return max(0, value) }
        if let value = value as? NSNumber { return max(0, value.intValue) }
        if let value = value as? String, let parsed = Int(value) { return max(0, parsed) }
        return 0
    }
}

private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}
