import SwiftUI
import WebKit

struct OfflineArticleReader: UIViewRepresentable {
    let article: SavedArticle
    let fileURL: URL
    let onSelection: (ArticleHighlightSelection?) -> Void
    let onPositionChange: (Double) -> Void
    let onOpenExternal: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.add(context.coordinator, name: "articleSelection")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.delegate = context.coordinator
        webView.isOpaque = false
        context.coordinator.loadedArticleID = article.id
        webView.loadFileURL(fileURL, allowingReadAccessTo: fileURL.deletingLastPathComponent())
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.loadedArticleID != article.id {
            context.coordinator.loadedArticleID = article.id
            webView.loadFileURL(fileURL, allowingReadAccessTo: fileURL.deletingLastPathComponent())
        } else {
            context.coordinator.applyHighlights(in: webView)
        }
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "articleSelection")
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler, UIScrollViewDelegate {
        var parent: OfflineArticleReader
        var loadedArticleID = ""
        private var restoredPosition = false

        init(parent: OfflineArticleReader) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            applyHighlights(in: webView)
            let position = min(max(parent.article.readingPosition, 0), 1)
            webView.evaluateJavaScript("window.scrollTo(0, Math.max(0, (document.documentElement.scrollHeight - innerHeight) * \(position)));", completionHandler: nil)
            restoredPosition = true
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard navigationAction.navigationType == .linkActivated,
                  let url = navigationAction.request.url,
                  ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
                decisionHandler(navigationAction.request.url?.isFileURL == false && navigationAction.targetFrame?.isMainFrame == true ? .cancel : .allow)
                return
            }
            parent.onOpenExternal(url.absoluteString)
            decisionHandler(.cancel)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let payload = message.body as? [String: String],
                  let quote = payload["quote"], !quote.isEmpty else {
                parent.onSelection(nil)
                return
            }
            parent.onSelection(ArticleHighlightSelection(
                quote: quote,
                prefix: payload["prefix"] ?? "",
                suffix: payload["suffix"] ?? ""
            ))
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard restoredPosition else { return }
            let scrollable = max(1, scrollView.contentSize.height - scrollView.bounds.height)
            parent.onPositionChange(Double(min(max(scrollView.contentOffset.y / scrollable, 0), 1)))
        }

        func applyHighlights(in webView: WKWebView) {
            let quotes = parent.article.highlights.map(\.quote)
            guard let data = try? JSONEncoder().encode(quotes),
                  let json = String(data: data, encoding: .utf8) else { return }
            let script = """
            (() => {
              document.querySelectorAll('mark[data-zhuo]').forEach(mark => mark.replaceWith(document.createTextNode(mark.textContent || '')));
              const quotes = \(json);
              const walker = document.createTreeWalker(document.querySelector('main') || document.body, NodeFilter.SHOW_TEXT);
              const nodes = []; while (walker.nextNode()) nodes.push(walker.currentNode);
              quotes.forEach(quote => {
                for (const node of nodes) {
                  if (!node.parentNode || node.parentElement?.closest('mark[data-zhuo]')) continue;
                  const index = (node.nodeValue || '').indexOf(quote);
                  if (index < 0) continue;
                  const range = document.createRange(); range.setStart(node, index); range.setEnd(node, index + quote.length);
                  const mark = document.createElement('mark'); mark.setAttribute('data-zhuo', '1'); range.surroundContents(mark); break;
                }
              });
              if (!window.__zhuoSelectionInstalled) {
                window.__zhuoSelectionInstalled = true;
                document.addEventListener('selectionchange', () => {
                  const selection = window.getSelection(); const quote = (selection?.toString() || '').trim();
                  if (!quote || !selection.rangeCount) { window.webkit.messageHandlers.articleSelection.postMessage({}); return; }
                  const text = document.body.innerText || ''; const index = text.indexOf(quote);
                  window.webkit.messageHandlers.articleSelection.postMessage({quote: quote.slice(0,500), prefix: index < 0 ? '' : text.slice(Math.max(0,index-80),index), suffix: index < 0 ? '' : text.slice(index+quote.length,index+quote.length+80)});
                });
              }
            })();
            """
            webView.evaluateJavaScript(script, completionHandler: nil)
        }
    }
}
