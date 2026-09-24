import AppKit
import SwiftUI
import WebKit

/// NSViewRepresentable hosting the active TabController's WKWebView on macOS.
/// Uses AutoLayout to anchor the WKWebView to the container bounds,
/// avoiding unnecessary subview tearing/flickering on SwiftUI updates.
public struct WebContainerView: NSViewRepresentable {
    public let controller: TabController?

    public init(controller: TabController?) {
        self.controller = controller
    }

    public final class HostView: NSView {
        private weak var currentWebView: WKWebView?

        func attach(webView: WKWebView?) {
            if currentWebView === webView && webView?.superview === self {
                return
            }

            currentWebView?.removeFromSuperview()
            currentWebView = webView

            guard let webView = webView else { return }
            webView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(webView)

            NSLayoutConstraint.activate([
                webView.leadingAnchor.constraint(equalTo: leadingAnchor),
                webView.trailingAnchor.constraint(equalTo: trailingAnchor),
                webView.topAnchor.constraint(equalTo: topAnchor),
                webView.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }
    }

    public func makeNSView(context: Context) -> HostView {
        let host = HostView()
        host.attach(webView: controller?.webView)
        return host
    }

    public func updateNSView(_ host: HostView, context: Context) {
        host.attach(webView: controller?.webView)
    }
}
