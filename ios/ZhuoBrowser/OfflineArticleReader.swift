import SwiftUI
import WebKit

struct OfflineArticleReader: UIViewRepresentable {
    let article: SavedArticle
    let fileURL: URL
    var targetHighlightID: String? = nil
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
            context.coordinator.applyHighlights(in: webView, targetID: targetHighlightID)
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
            applyHighlights(in: webView, targetID: parent.targetHighlightID)
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

        func applyHighlights(in webView: WKWebView, targetID: String? = nil) {
            struct HighlightItem: Codable {
                let id: String
                let quote: String
                let prefix: String
                let suffix: String
            }
            let items = parent.article.highlights.map {
                HighlightItem(id: $0.id, quote: $0.quote, prefix: $0.prefix, suffix: $0.suffix)
            }
            guard let itemsData = try? JSONEncoder().encode(items),
                  let itemsJSON = String(data: itemsData, encoding: .utf8),
                  let targetData = try? JSONEncoder().encode(targetID ?? ""),
                  let targetJSON = String(data: targetData, encoding: .utf8) else { return }

            let script = """
            (function(items, target) {
              var root = document.querySelector('article') || document.querySelector('main') || document.body;
              if (!root) return false;
              root.querySelectorAll('mark[data-article-highlight]').forEach(function(mark) {
                mark.replaceWith(document.createTextNode(mark.textContent || ''));
              });
              root.normalize();
              items.forEach(function(item) {
                var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
                var nodes = [], text = '', node;
                while ((node = walker.nextNode())) {
                  nodes.push({node: node, start: text.length});
                  text += node.textContent;
                }
                var quote = item.quote || '';
                var escaped = quote.replace(/[.*+?^${}()|[\\]\\\\]/g, '\\\\$&').trim().split(/\\s+/).join('\\\\s+');
                if (!escaped) return;
                var pattern = new RegExp(escaped, 'g');
                var match, bestMatch = null, bestScore = -1;
                while ((match = pattern.exec(text))) {
                  var before = text.substring(0, match.index).replace(/\\s+/g, ' ');
                  var after = text.substring(match.index + match[0].length).replace(/\\s+/g, ' ');
                  var score = 0;
                  if (item.prefix && before.endsWith(item.prefix.trim())) score += 2;
                  if (item.suffix && after.startsWith(item.suffix.trim())) score += 2;
                  if (score > bestScore) {
                    bestScore = score;
                    bestMatch = match;
                    if ((!item.prefix || before.endsWith(item.prefix.trim())) && (!item.suffix || after.startsWith(item.suffix.trim()))) break;
                  }
                }
                match = bestMatch || match;
                if (!match) return;
                var start = match.index, end = start + match[0].length;
                nodes.forEach(function(entry) {
                  var left = Math.max(0, start - entry.start);
                  var right = Math.min(entry.node.length, end - entry.start);
                  if (left >= right) return;
                  var range = document.createRange();
                  range.setStart(entry.node, left);
                  range.setEnd(entry.node, right);
                  var mark = document.createElement('mark');
                  mark.setAttribute('data-article-highlight', item.id);
                  try {
                    range.surroundContents(mark);
                  } catch(e) {}
                });
              });
              if (target) {
                var marks = root.querySelectorAll('mark[data-article-highlight="' + target + '"]');
                if (marks.length > 0) {
                  marks[0].scrollIntoView({behavior: 'smooth', block: 'center'});
                  marks.forEach(function(m) {
                    m.style.transition = 'outline 0.3s ease';
                    m.style.outline = '3px solid #ff9800';
                    setTimeout(function() { m.style.outline = ''; }, 1500);
                  });
                  return true;
                }
                return false;
              }
              if (!window.__zhuoSelectionInstalled) {
                window.__zhuoSelectionInstalled = true;
                document.addEventListener('selectionchange', () => {
                  const selection = window.getSelection();
                  const quote = (selection?.toString() || '').trim();
                  if (!quote || !selection.rangeCount) {
                    window.webkit.messageHandlers.articleSelection.postMessage({});
                    return;
                  }
                  const range = selection.getRangeAt(0);
                  const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
                  let text = '', n, start = -1, end = -1;
                  while ((n = walker.nextNode())) {
                    if (n === range.startContainer) {
                      start = text.length + range.startOffset;
                    }
                    if (n === range.endContainer) {
                      end = text.length + range.endOffset;
                    }
                    text += n.textContent;
                  }
                  if (start < 0 || end < 0) {
                    const idx = text.indexOf(quote);
                    start = idx;
                    end = idx + quote.length;
                  }
                  const prefix = start > 0 ? text.slice(Math.max(0, start - 80), start).replace(/\\s+/g, ' ') : '';
                  const suffix = end >= 0 ? text.slice(end, Math.min(text.length, end + 80)).replace(/\\s+/g, ' ') : '';
                  window.webkit.messageHandlers.articleSelection.postMessage({
                    quote: quote.slice(0, 500),
                    prefix: prefix,
                    suffix: suffix
                  });
                });
              }
              return true;
            })(\(itemsJSON), \(targetJSON));
            """
            webView.evaluateJavaScript(script, completionHandler: nil)
        }
    }
}
