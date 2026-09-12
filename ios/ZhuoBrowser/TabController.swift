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
        if !URLPolicy.isHomeURL(tab.url) {
            load(tab.url)
        }
    }

    func load(_ raw: String) {
        let address = URLPolicy.normalizeAddress(raw)
        session?.update(tabID: id) { tab in
            tab.url = address
            tab.lastVisitedAt = Date().timeIntervalSince1970
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

    func applyContentBlocker() {
        var installed = installedRuleLists
        ContentBlocker.shared.install(on: webView.configuration.userContentController, installed: &installed)
        installedRuleLists = installed
        WebKernel.storeInstalledRuleLists(installed, on: webView.configuration)
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
}
