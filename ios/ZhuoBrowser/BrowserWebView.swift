import SwiftUI
import WebKit

struct BrowserWebView: UIViewRepresentable {
    let webView: WKWebView
    let onFocus: () -> Void
    let onScroll: (CGFloat) -> Void

    init(
        webView: WKWebView,
        onFocus: @escaping () -> Void = {},
        onScroll: @escaping (CGFloat) -> Void = { _ in }
    ) {
        self.webView = webView
        self.onFocus = onFocus
        self.onScroll = onScroll
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onFocus: onFocus, onScroll: onScroll)
    }

    func makeUIView(context: Context) -> WKWebView {
        let recognizer = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.focus))
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = context.coordinator
        webView.addGestureRecognizer(recognizer)
        webView.scrollView.delegate = context.coordinator
        context.coordinator.recognizer = recognizer
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.onFocus = onFocus
        context.coordinator.onScroll = onScroll
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        if let recognizer = coordinator.recognizer {
            uiView.removeGestureRecognizer(recognizer)
        }
        if uiView.scrollView.delegate === coordinator {
            uiView.scrollView.delegate = nil
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate, UIScrollViewDelegate {
        var onFocus: () -> Void
        var onScroll: (CGFloat) -> Void
        weak var recognizer: UITapGestureRecognizer?

        init(onFocus: @escaping () -> Void, onScroll: @escaping (CGFloat) -> Void) {
            self.onFocus = onFocus
            self.onScroll = onScroll
        }

        @objc func focus() {
            onFocus()
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            onScroll(scrollView.contentOffset.y + scrollView.adjustedContentInset.top)
        }
    }
}
