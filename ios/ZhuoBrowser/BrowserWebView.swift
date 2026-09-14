import SwiftUI
import WebKit

struct BrowserWebView: UIViewRepresentable {
    let webView: WKWebView
    let isPageLoading: Bool
    let isRefreshEnabled: Bool
    let onFocus: () -> Void
    let onScroll: (CGFloat) -> Void
    let onRefresh: () -> Void

    init(
        webView: WKWebView,
        isPageLoading: Bool = false,
        isRefreshEnabled: Bool = true,
        onFocus: @escaping () -> Void = {},
        onScroll: @escaping (CGFloat) -> Void = { _ in },
        onRefresh: @escaping () -> Void = {}
    ) {
        self.webView = webView
        self.isPageLoading = isPageLoading
        self.isRefreshEnabled = isRefreshEnabled
        self.onFocus = onFocus
        self.onScroll = onScroll
        self.onRefresh = onRefresh
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onFocus: onFocus, onScroll: onScroll, onRefresh: onRefresh)
    }

    func makeUIView(context: Context) -> WKWebView {
        let recognizer = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.focus))
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = context.coordinator
        webView.addGestureRecognizer(recognizer)
        webView.scrollView.delegate = context.coordinator
        context.coordinator.installRefreshControl(on: webView.scrollView)
        context.coordinator.recognizer = recognizer
        updateRefreshControl(on: webView, coordinator: context.coordinator)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.onFocus = onFocus
        context.coordinator.onScroll = onScroll
        context.coordinator.onRefresh = onRefresh
        updateRefreshControl(on: uiView, coordinator: context.coordinator)
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        if let recognizer = coordinator.recognizer {
            uiView.removeGestureRecognizer(recognizer)
        }
        if uiView.scrollView.delegate === coordinator {
            uiView.scrollView.delegate = nil
        }
        coordinator.removeRefreshControl(from: uiView.scrollView)
    }

    private func updateRefreshControl(on webView: WKWebView, coordinator: Coordinator) {
        coordinator.refreshControl.isEnabled = isRefreshEnabled
        webView.scrollView.alwaysBounceVertical =
            isRefreshEnabled || coordinator.originalAlwaysBounceVertical
        if !isPageLoading, coordinator.refreshControl.isRefreshing {
            coordinator.refreshControl.endRefreshing()
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate, UIScrollViewDelegate {
        var onFocus: () -> Void
        var onScroll: (CGFloat) -> Void
        var onRefresh: () -> Void
        weak var recognizer: UITapGestureRecognizer?
        let refreshControl = UIRefreshControl()
        private(set) var originalAlwaysBounceVertical = false

        init(
            onFocus: @escaping () -> Void,
            onScroll: @escaping (CGFloat) -> Void,
            onRefresh: @escaping () -> Void
        ) {
            self.onFocus = onFocus
            self.onScroll = onScroll
            self.onRefresh = onRefresh
            super.init()
            refreshControl.accessibilityIdentifier = "page-pull-refresh"
            refreshControl.accessibilityLabel = "下拉刷新"
            refreshControl.addTarget(
                self,
                action: #selector(refresh),
                for: .valueChanged
            )
        }

        @objc func focus() {
            onFocus()
        }

        @objc private func refresh() {
            guard refreshControl.isEnabled else {
                refreshControl.endRefreshing()
                return
            }
            onFocus()
            onRefresh()
        }

        func installRefreshControl(on scrollView: UIScrollView) {
            originalAlwaysBounceVertical = scrollView.alwaysBounceVertical
            scrollView.refreshControl = refreshControl
        }

        func removeRefreshControl(from scrollView: UIScrollView) {
            if scrollView.refreshControl === refreshControl {
                scrollView.refreshControl = nil
            }
            scrollView.alwaysBounceVertical = originalAlwaysBounceVertical
            refreshControl.removeTarget(self, action: #selector(refresh), for: .valueChanged)
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
