import AppKit
import Foundation
import WebKit

/// Manages the live WKWebView for a BrowserTab.
/// Can be torn down when hibernating to free memory, and recreated on demand.
public final class TabController: NSObject, WKNavigationDelegate, WKUIDelegate {
    public let tabID: String
    public private(set) var webView: WKWebView?
    public weak var session: BrowserSession?

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
        if let passkeyScript = InjectedScripts.shared.makePasskeyAdapterScript() {
            userContentController.addUserScript(passkeyScript)
        }

        // Initialize passkey manager authorization check
        Task { @MainActor in
            _ = await PasskeyManager.shared.requestAuthorizationIfNeeded()
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
        // Record browsing history for normal tabs
        if let tab = session?.tab(for: tabID), !tab.isPrivate && !tab.isHome {
            session?.recordHistory(url: tab.url, title: tab.title)
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
}
