import Foundation
import WebKit

final class TabController: NSObject, WKNavigationDelegate {
    let id: String
    let isPrivate: Bool
    let webView: WKWebView
    weak var session: BrowserSession?
    private var installedRuleLists: Set<String>

    init(tab: BrowserTab, session: BrowserSession, dataStore: WKWebsiteDataStore) {
        self.id = tab.id
        self.isPrivate = tab.isPrivate
        let configuration = WebKernel.makeConfiguration(isPrivate: tab.isPrivate, dataStore: dataStore)
        self.installedRuleLists = WebKernel.installedRuleLists(from: configuration)
        self.webView = WKWebView(frame: .zero, configuration: configuration)
        self.session = session
        super.init()
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        applyUserAgent(isDesktop: tab.isDesktop)
        if !URLPolicy.isHomeURL(tab.url) {
            let target = tab.isDesktop ? URLPolicy.desktopURL(for: tab.url) : tab.url
            load(target, rewriteDesktop: false)
        }
    }

    func load(_ raw: String, rewriteDesktop: Bool = true) {
        var address = URLPolicy.normalizeAddress(raw)
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
        }
    }

    func applyUserAgent(isDesktop: Bool) {
        webView.customUserAgent = isDesktop ? WebKernel.desktopUserAgent : nil
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

    func exitReader() {
        webView.evaluateJavaScript(ReaderScripts.exit, completionHandler: nil)
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

    func applyContentBlocker() {
        var installed = installedRuleLists
        ContentBlocker.shared.install(on: webView.configuration.userContentController, installed: &installed)
        installedRuleLists = installed
        WebKernel.storeInstalledRuleLists(installed, on: webView.configuration)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if navigationAction.targetFrame?.isMainFrame == true && navigationAction.navigationType != .reload {
            switch navigationAction.navigationType {
            case .other:
                break
            default:
                session?.update(tabID: id) { tab in
                    tab.isReader = false
                }
            }
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        session?.update(tabID: id) { tab in
            tab.isLoading = true
            if let url = webView.url?.absoluteString, !url.isEmpty {
                tab.url = url
            }
            tab.canGoBack = true
            tab.lastVisitedAt = Date().timeIntervalSince1970
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
            tab.canGoBack = true
        }
        applyDesktopViewportIfNeeded()
        if session?.tab(id)?.isReader == true {
            let settings = session?.readerSettings ?? ReaderSettings()
            applyReader(settings: settings) { [weak self] ok in
                if !ok {
                    self?.session?.update(tabID: self?.id ?? "") { tab in
                        tab.isReader = false
                    }
                }
            }
        }
        session?.persist()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        session?.update(tabID: id) { tab in
            tab.isLoading = false
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        session?.update(tabID: id) { tab in
            tab.isLoading = false
        }
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
}
