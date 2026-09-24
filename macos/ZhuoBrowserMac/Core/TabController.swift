import Foundation
import WebKit

/// Manages the live WKWebView for a BrowserTab.
/// Can be torn down when hibernating to free memory, and recreated on demand.
public final class TabController: NSObject, WKNavigationDelegate, WKUIDelegate {
    public let tabID: String
    public private(set) var webView: WKWebView?
    public weak var session: BrowserSession?

    private var progressObservation: NSKeyValueObservation?
    private var titleObservation: NSKeyValueObservation?
    private var urlObservation: NSKeyValueObservation?
    private var canGoBackObservation: NSKeyValueObservation?
    private var canGoForwardObservation: NSKeyValueObservation?

    public init(tabID: String, session: BrowserSession, initialURL: URL?, isPrivate: Bool) {
        self.tabID = tabID
        self.session = session
        super.init()
        setupWebView(isPrivate: isPrivate)
        if let initialURL = initialURL {
            load(url: initialURL)
        }
    }

    private func setupWebView(isPrivate: Bool) {
        let config = WKWebViewConfiguration()

        // Shared or private data store
        config.websiteDataStore = isPrivate ? .nonPersistent() : .default()

        // Install injected scripts
        let userContentController = config.userContentController
        if let trackerScript = InjectedScripts.shared.makeTrackerBlockScript() {
            userContentController.addUserScript(trackerScript)
        }
        if let cosmeticScript = InjectedScripts.shared.makeCosmeticCleanupScript() {
            userContentController.addUserScript(cosmeticScript)
        }

        // Install native content blocker rules
        ContentBlocker.shared.install(on: userContentController)

        // Preferences for performance
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = self
        wv.uiDelegate = self
        self.webView = wv

        // Setup KVO
        progressObservation = wv.observe(\.estimatedProgress, options: [.new]) { [weak self] _, change in
            guard let self = self, let progress = change.newValue else { return }
            self.session?.updateTab(self.tabID) { tab in
                tab.loadingProgress = progress
                tab.isLoading = progress < 1.0
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

    public func load(url: URL) {
        guard let webView = webView else { return }
        let request = URLRequest(url: url)
        webView.load(request)
    }

    public func reload() {
        webView?.reload()
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

    /// Captures the current scroll position before tab eviction
    public func captureScrollPosition(completion: @escaping (Double) -> Void) {
        guard let webView = webView else {
            completion(0)
            return
        }
        webView.evaluateJavaScript("window.scrollY || window.pageYOffset || 0") { result, _ in
            let y = (result as? NSNumber)?.doubleValue ?? 0.0
            completion(y)
        }
    }

    /// Restores the scroll position after webview recreation
    public func restoreScrollPosition(_ y: Double) {
        guard y > 0, let webView = webView else { return }
        let js = "window.scrollTo(0, \(y));"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    /// Completely destroys the WKWebView and its observers to release memory to the system
    public func destroy() {
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
        session?.updateTab(tabID) { tab in
            tab.isLoading = false
            tab.loadingProgress = 1.0
            if let title = webView.title, !title.isEmpty {
                tab.title = title
            }
            if let url = webView.url?.absoluteString, !url.isEmpty {
                tab.url = url
            }
        }
        // Restore scroll position if previously saved
        if let tab = session?.tab(for: tabID), tab.scrollPositionY > 0 {
            restoreScrollPosition(tab.scrollPositionY)
        }
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        session?.updateTab(tabID) { tab in
            tab.isLoading = false
        }
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        session?.updateTab(tabID) { tab in
            tab.isLoading = false
        }
    }

    public func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
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
}
