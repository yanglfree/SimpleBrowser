import AppKit
import SwiftUI
import WebKit

/// NSViewRepresentable hosting a tab's `WKWebView` on macOS.
///
/// The host view is intentionally *stable*: it is created once per window and only
/// swaps which WebView it displays. Combined with keeping warm WebViews alive, this
/// means a tab switch is a single subview re-parenting instead of a full page load.
///
/// Layout is pure AutoLayout pinned to the host bounds, so every window size (small
/// split, full screen, multi-display scaling) resolves identically for background and
/// foreground tabs — a tab that was resized while hidden comes back correctly sized.
public struct WebContainerView: NSViewRepresentable {
    public let controller: TabController?

    public init(controller: TabController?) {
        self.controller = controller
    }

    public final class HostView: NSView {
        private weak var currentWebView: WKWebView?

        public override var isFlipped: Bool { true }
        public override var isOpaque: Bool { false }

        public override func resizeSubviews(withOldSize oldSize: NSSize) {
            super.resizeSubviews(withOldSize: oldSize)
            let targetBounds = bounds
            for subview in subviews where subview.frame != targetBounds {
                subview.frame = targetBounds
            }
        }

        func attach(webView: WKWebView?) {
            if currentWebView === webView, let webView, webView.superview === self {
                if webView.isHidden {
                    webView.isHidden = false
                }
                if webView.frame != bounds {
                    webView.frame = bounds
                }
                return
            }

            let previous = currentWebView
            currentWebView = webView

            guard let webView else {
                previous?.isHidden = true
                return
            }

            if let superview = webView.superview, superview !== self {
                webView.removeFromSuperview()
            }

            webView.translatesAutoresizingMaskIntoConstraints = true
            webView.autoresizingMask = [.width, .height]
            webView.frame = bounds

            if webView.superview !== self {
                addSubview(webView)
            }
            webView.isHidden = false

            if let previous, previous !== webView {
                previous.isHidden = true
            }
        }

        func detachAll() {
            currentWebView = nil
            for subview in subviews {
                subview.isHidden = true
                subview.removeFromSuperview()
            }
        }
    }

    public func makeNSView(context: Context) -> HostView {
        let host = HostView()
        host.autoresizesSubviews = true
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.clear.cgColor
        host.attach(webView: controller?.webView)
        return host
    }

    public func updateNSView(_ host: HostView, context: Context) {
        host.attach(webView: controller?.webView)
    }

    public static func dismantleNSView(_ host: HostView, coordinator: ()) {
        // Detach without destroying: the WebView lives on inside its TabController and
        // must keep its state for the next time the tab becomes visible.
        host.detachAll()
    }
}
