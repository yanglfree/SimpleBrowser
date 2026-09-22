import Foundation
import WebKit

enum ArticleCaptureError: LocalizedError {
    case scriptMissing
    case extractionFailed
    case unreadable
    case timedOut

    var errorDescription: String? {
        switch self {
        case .scriptMissing: return "文章提取组件不可用"
        case .extractionFailed: return "无法提取此页面正文"
        case .unreadable: return "页面正文不足，无法离线保存"
        case .timedOut: return "文章提取超时"
        }
    }

    var failureKind: ArticleSaveFailure {
        switch self {
        case .scriptMissing: return .extractionUnavailable
        case .extractionFailed: return .extractionUnavailable
        case .unreadable: return .captureInvalid
        case .timedOut: return .stalled
        }
    }
}

enum ArticleCapture {
    static func capture(from webView: WKWebView) async throws -> ArticleCaptureSnapshot {
        try await captureWithRetries(from: webView, timeoutSeconds: 8)
    }

    static func captureWithRetries(
        from webView: WKWebView,
        timeoutSeconds: TimeInterval = 8
    ) async throws -> ArticleCaptureSnapshot {
        guard let script = WebKernel.loadScript(named: "article-capture") else {
            throw ArticleCaptureError.scriptMissing
        }

        let deadline = Date().addingTimeInterval(timeoutSeconds)
        var previousText = ""
        var latest: ArticleCaptureSnapshot?

        for attempt in 0..<6 {
            if Date() >= deadline {
                if let latest, ArticlePolicy.validate(latest) {
                    return latest
                }
                throw ArticleCaptureError.timedOut
            }

            if let snapshot = try? await readSnapshot(from: webView, script: script) {
                if ArticlePolicy.validate(snapshot) && snapshot.text == previousText {
                    return snapshot
                }
                previousText = snapshot.text
                latest = snapshot
            }

            if attempt < 5 {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }

        if let latest, ArticlePolicy.validate(latest) {
            return latest
        }

        if latest != nil {
            throw ArticleCaptureError.unreadable
        }

        throw ArticleCaptureError.extractionFailed
    }

    private static func readSnapshot(from webView: WKWebView, script: String) async throws -> ArticleCaptureSnapshot {
        let result = try await webView.evaluateJavaScript(script)
        guard let json = result as? String,
              let data = json.data(using: .utf8),
              let snapshot = try? JSONDecoder().decode(ArticleCaptureSnapshot.self, from: data) else {
            throw ArticleCaptureError.extractionFailed
        }
        return snapshot
    }
}
