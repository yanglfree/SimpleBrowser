import Foundation
import WebKit

enum WebKernel {
    static let homeURL = "browser://home"
    static let documentStartFiles = [
        "blocked-link-guard",
        "long-press-target",
        "password-field-watcher"
    ]

    static func isHomeURL(_ value: String) -> Bool {
        value.isEmpty || value == homeURL
    }

    static func makeConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.websiteDataStore = .default()
        let controller = configuration.userContentController
        for name in documentStartFiles {
            if let script = loadScript(named: name) {
                controller.addUserScript(
                    WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: false)
                )
            }
        }
        return configuration
    }

    static func loadScript(named name: String) -> String? {
        if let url = Bundle.main.url(forResource: name, withExtension: "js", subdirectory: "js") {
            return try? String(contentsOf: url, encoding: .utf8)
        }
        if let url = Bundle.main.url(forResource: name, withExtension: "js") {
            return try? String(contentsOf: url, encoding: .utf8)
        }
        return nil
    }
}

final class BrowserWebViewController: NSObject, ObservableObject, WKNavigationDelegate {
    @Published var displayedURL: String = WebKernel.homeURL
    @Published var canGoBack = false
    @Published var isLoading = false

    let webView: WKWebView

    override init() {
        webView = WKWebView(frame: .zero, configuration: WebKernel.makeConfiguration())
        super.init()
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
    }

    func open(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if WebKernel.isHomeURL(trimmed) {
            displayedURL = WebKernel.homeURL
            webView.stopLoading()
            return
        }
        let target = Self.normalizedURL(from: trimmed)
        displayedURL = target.absoluteString
        webView.load(URLRequest(url: target))
    }

    func goBack() {
        if webView.canGoBack {
            webView.goBack()
            return
        }
        displayedURL = WebKernel.homeURL
    }

    func reload() {
        webView.reload()
    }

    func stop() {
        webView.stopLoading()
        isLoading = false
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isLoading = true
        canGoBack = webView.canGoBack || !WebKernel.isHomeURL(displayedURL)
        if let url = webView.url?.absoluteString {
            displayedURL = url
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false
        canGoBack = webView.canGoBack || !WebKernel.isHomeURL(displayedURL)
        if let url = webView.url?.absoluteString {
            displayedURL = url
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        isLoading = false
    }

    private static func normalizedURL(from input: String) -> URL {
        if let url = URL(string: input), url.scheme != nil {
            return url
        }
        return URL(string: "https://\(input)") ?? URL(string: "https://www.bing.com")!
    }
}
