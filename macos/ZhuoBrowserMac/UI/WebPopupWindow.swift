import AppKit
import Foundation
import WebKit

/// Dedicated auxiliary window controller hosting a single popup or third-party OAuth login page.
///
/// Contains ONLY the target web view with a subtle top progress bar and native titlebar.
/// Does not contain tab bars, duplicate session tabs, or extraneous chrome.
/// Automatically closes itself when the login flow completes (`window.close()` / `webViewDidClose`).
@MainActor
public final class WebPopupWindowController: NSWindowController, NSWindowDelegate, WKUIDelegate, WKNavigationDelegate {

    public let webView: WKWebView
    private let progressBar: NSProgressIndicator

    private var titleObservation: NSKeyValueObservation?
    private var progressObservation: NSKeyValueObservation?
    private var loadingObservation: NSKeyValueObservation?
    private var isTornDown: Bool = false

    public init(window: NSWindow, webView: WKWebView) {
        self.webView = webView
        self.progressBar = NSProgressIndicator(frame: .zero)
        super.init(window: window)

        setupUI()
        setupObservers()
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        // Observers automatically invalidate on deinit in Swift 5.0+
    }

    private func setupUI() {
        guard let window = self.window else { return }

        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.title = "登录"

        let container = NSView(frame: window.contentView?.bounds ?? .zero)
        container.autoresizingMask = [.width, .height]

        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.uiDelegate = self
        webView.navigationDelegate = self
        container.addSubview(webView)

        progressBar.translatesAutoresizingMaskIntoConstraints = false
        progressBar.style = .bar
        progressBar.isIndeterminate = false
        progressBar.minValue = 0.0
        progressBar.maxValue = 1.0
        progressBar.doubleValue = 0.05
        progressBar.isHidden = true
        container.addSubview(progressBar)

        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            progressBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            progressBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            progressBar.topAnchor.constraint(equalTo: container.topAnchor),
            progressBar.heightAnchor.constraint(equalToConstant: 2)
        ])

        window.contentView = container
    }

    private func setupObservers() {
        titleObservation = webView.observe(\.title, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.updateTitle()
            }
        }

        progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] wv, _ in
            DispatchQueue.main.async {
                self?.updateProgress(wv.estimatedProgress)
            }
        }

        loadingObservation = webView.observe(\.isLoading, options: [.new]) { [weak self] wv, _ in
            DispatchQueue.main.async {
                self?.updateLoading(wv.isLoading)
            }
        }
    }

    private func updateTitle() {
        if let title = webView.title, !title.isEmpty {
            window?.title = title
        } else if let host = webView.url?.host, !host.isEmpty {
            window?.title = host
        } else {
            window?.title = "第三方登录"
        }
    }

    private func updateProgress(_ progress: Double) {
        progressBar.doubleValue = max(0.05, progress)
    }

    private func updateLoading(_ isLoading: Bool) {
        progressBar.isHidden = !isLoading
        if !isLoading {
            updateTitle()
        }
    }

    public func teardown() {
        guard !isTornDown else { return }
        isTornDown = true

        titleObservation?.invalidate()
        titleObservation = nil
        progressObservation?.invalidate()
        progressObservation = nil
        loadingObservation?.invalidate()
        loadingObservation = nil

        webView.uiDelegate = nil
        webView.navigationDelegate = nil
        webView.stopLoading()

        WebPopupWindowManager.shared.remove(self)
    }

    // MARK: - NSWindowDelegate

    public func windowWillClose(_ notification: Notification) {
        teardown()
    }

    // MARK: - WKUIDelegate

    public func webViewDidClose(_ webView: WKWebView) {
        window?.close()
        teardown()
    }

    public func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = frame.request.url?.host ?? webView.url?.host ?? "提示"
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "确定")

        if let window = self.window {
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
        let alert = NSAlert()
        alert.messageText = frame.request.url?.host ?? webView.url?.host ?? "提示"
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")

        if let window = self.window {
            alert.beginSheetModal(for: window) { response in
                completionHandler(response == .alertFirstButtonReturn)
            }
        } else {
            let response = alert.runModal()
            completionHandler(response == .alertFirstButtonReturn)
        }
    }

    // MARK: - WKNavigationDelegate

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        updateTitle()
    }
}

/// Central manager tracking and displaying popup windows and third-party login flows.
@MainActor
public final class WebPopupWindowManager: NSObject {
    public static let shared = WebPopupWindowManager()

    public static let defaultPopupWidth: CGFloat = 520
    public static let defaultPopupHeight: CGFloat = 640

    public private(set) var activeControllers: [WebPopupWindowController] = []

    public var openPopupCount: Int {
        activeControllers.count
    }

    private override init() {
        super.init()
    }

    /// Presents a popup `WKWebView` in a dedicated standalone window matching the requested window features.
    /// Returns the created `WKWebView` so WebKit can bind `window.opener` and target frame navigation.
    @discardableResult
    public func presentPopup(
        configuration: WKWebViewConfiguration,
        features: WKWindowFeatures,
        initialURL: URL? = nil,
        parentWindow: NSWindow? = nil
    ) -> WKWebView {
        let rawWidth = features.width.map { CGFloat($0.doubleValue) } ?? Self.defaultPopupWidth
        let rawHeight = features.height.map { CGFloat($0.doubleValue) } ?? Self.defaultPopupHeight

        let clampedWidth = min(max(rawWidth, 380), 1200)
        let clampedHeight = min(max(rawHeight, 400), 1000)

        var frameOrigin: NSPoint?
        if let x = features.x?.doubleValue, let y = features.y?.doubleValue {
            frameOrigin = NSPoint(x: CGFloat(x), y: CGFloat(y))
        }

        let contentRect = NSRect(x: 0, y: 0, width: clampedWidth, height: clampedHeight)
        let window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        if let origin = frameOrigin {
            window.setFrameOrigin(origin)
        } else if let parent = parentWindow {
            let parentFrame = parent.frame
            let x = parentFrame.midX - clampedWidth / 2
            let y = parentFrame.midY - clampedHeight / 2
            window.setFrameOrigin(NSPoint(x: max(0, x), y: max(0, y)))
        } else {
            window.center()
        }

        let webView = WKWebView(frame: contentRect, configuration: configuration)
        let controller = WebPopupWindowController(window: window, webView: webView)
        activeControllers.append(controller)

        if let url = initialURL, !URLPolicy.isBlankURL(url.absoluteString) {
            webView.load(URLRequest(url: url))
        }

        controller.showWindow(self)
        window.makeKeyAndOrderFront(self)

        return webView
    }

    /// Opens a third-party login or OAuth URL in a dedicated popup window.
    @discardableResult
    public func openPopup(url: URL, parentWindow: NSWindow? = nil) -> WebPopupWindowController {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.applicationNameForUserAgent = "Version/17.0 Safari/605.1.15 ZhuoBrowser/1.0"

        let contentRect = NSRect(x: 0, y: 0, width: Self.defaultPopupWidth, height: Self.defaultPopupHeight)
        let window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        if let parent = parentWindow {
            let parentFrame = parent.frame
            let x = parentFrame.midX - Self.defaultPopupWidth / 2
            let y = parentFrame.midY - Self.defaultPopupHeight / 2
            window.setFrameOrigin(NSPoint(x: max(0, x), y: max(0, y)))
        } else {
            window.center()
        }

        let webView = WKWebView(frame: contentRect, configuration: config)
        let controller = WebPopupWindowController(window: window, webView: webView)
        activeControllers.append(controller)

        webView.load(URLRequest(url: url))
        controller.showWindow(self)
        window.makeKeyAndOrderFront(self)

        return controller
    }

    public func closeAllPopups() {
        let controllers = activeControllers
        activeControllers.removeAll()
        for controller in controllers {
            controller.window?.close()
            controller.teardown()
        }
    }

    fileprivate func remove(_ controller: WebPopupWindowController) {
        activeControllers.removeAll { $0 === controller }
    }
}
