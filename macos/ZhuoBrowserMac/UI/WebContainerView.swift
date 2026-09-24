import AppKit
import SwiftUI
import WebKit

/// NSViewRepresentable wrapping the active WKWebView for macOS SwiftUI hierarchy.
public struct WebContainerView: NSViewRepresentable {
    public let controller: TabController?

    public init(controller: TabController?) {
        self.controller = controller
    }

    public func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        updateView(container)
        return container
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        updateView(nsView)
    }

    private func updateView(_ container: NSView) {
        // Remove old subviews
        container.subviews.forEach { $0.removeFromSuperview() }

        // Attach controller's webView if present
        guard let webView = controller?.webView else { return }
        webView.frame = container.bounds
        webView.autoresizingMask = [.width, .height]
        container.addSubview(webView)
    }
}
