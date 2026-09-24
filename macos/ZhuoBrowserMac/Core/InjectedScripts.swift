import Foundation
import WebKit

/// Manages injected JavaScript scripts from core/js
public final class InjectedScripts: @unchecked Sendable {
    public static let shared = InjectedScripts()

    private var cachedScripts: [String: String] = [:]
    private let lock = NSLock()

    public func scriptContent(named name: String) -> String? {
        lock.lock()
        defer { lock.unlock() }

        if let cached = cachedScripts[name] {
            return cached
        }

        // Try direct resource or js subfolder
        let bundle = Bundle.main
        var fileURL = bundle.url(forResource: name, withExtension: "js", subdirectory: "js")
        if fileURL == nil {
            fileURL = bundle.url(forResource: name, withExtension: "js")
        }

        guard let url = fileURL, let content = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }

        cachedScripts[name] = content
        return content
    }

    /// User script for cosmetic cleanup (ad element hiding) injected at document end
    public func makeCosmeticCleanupScript() -> WKUserScript? {
        guard let source = scriptContent(named: "content-cleanup-standard") else { return nil }
        return WKUserScript(
            source: source,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
    }

    /// User script for tracker protection injected at document start
    public func makeTrackerBlockScript() -> WKUserScript? {
        guard let source = scriptContent(named: "tracker-block") else { return nil }
        return WKUserScript(
            source: source,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
    }
}
