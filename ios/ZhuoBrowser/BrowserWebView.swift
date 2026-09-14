import SwiftUI
import WebKit

struct BrowserWebView: UIViewRepresentable {
    let webView: WKWebView
    let onFocus: () -> Void

    init(webView: WKWebView, onFocus: @escaping () -> Void = {}) {
        self.webView = webView
        self.onFocus = onFocus
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onFocus: onFocus)
    }

    func makeUIView(context: Context) -> WKWebView {
        let recognizer = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.focus))
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = context.coordinator
        webView.addGestureRecognizer(recognizer)
        context.coordinator.recognizer = recognizer
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.onFocus = onFocus
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        if let recognizer = coordinator.recognizer {
            uiView.removeGestureRecognizer(recognizer)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onFocus: () -> Void
        weak var recognizer: UITapGestureRecognizer?

        init(onFocus: @escaping () -> Void) {
            self.onFocus = onFocus
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
    }
}
