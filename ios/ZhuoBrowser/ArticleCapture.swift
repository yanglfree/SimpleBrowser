import Foundation
import WebKit

enum ArticleCaptureError: LocalizedError {
    case scriptMissing
    case extractionFailed
    case unreadable

    var errorDescription: String? {
        switch self {
        case .scriptMissing: return "文章提取组件不可用"
        case .extractionFailed: return "无法提取此页面"
        case .unreadable: return "页面正文不足，无法离线保存"
        }
    }
}

enum ArticleCapture {
    static func capture(from webView: WKWebView) async throws -> ArticleCaptureSnapshot {
        guard let script = WebKernel.loadScript(named: "article-capture") else {
            throw ArticleCaptureError.scriptMissing
        }
        let result: Any?
        do {
            result = try await webView.evaluateJavaScript(script)
        } catch {
            throw ArticleCaptureError.extractionFailed
        }
        guard let json = result as? String,
              let data = json.data(using: .utf8),
              let snapshot = try? JSONDecoder().decode(ArticleCaptureSnapshot.self, from: data) else {
            throw ArticleCaptureError.extractionFailed
        }
        guard ArticlePolicy.validate(snapshot) else {
            throw ArticleCaptureError.unreadable
        }
        return snapshot
    }
}
