import Foundation
import WebKit

/// Custom `WKURLSchemeHandler` serving extension pages and assets over `zhuo-extension://<extension-id>/<path>`.
public final class ExtensionSchemeHandler: NSObject, WKURLSchemeHandler {
    public static let scheme = "zhuo-extension"

    private weak var extensionManager: ExtensionManager?
    private var activeTaskIDs = Set<ObjectIdentifier>()
    private let lock = NSLock()

    public init(extensionManager: ExtensionManager? = nil) {
        self.extensionManager = extensionManager
        super.init()
    }

    public func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        let taskID = ObjectIdentifier(urlSchemeTask)
        lock.lock()
        activeTaskIDs.insert(taskID)
        lock.unlock()

        guard let url = urlSchemeTask.request.url,
              let host = url.host,
              !host.isEmpty else {
            failTask(urlSchemeTask, taskID: taskID, statusCode: 400, message: "Invalid extension URL")
            return
        }

        let manager = extensionManager ?? ExtensionManager.shared
        guard let ext = manager.extensionItem(forID: host) else {
            failTask(urlSchemeTask, taskID: taskID, statusCode: 404, message: "Extension not found: \(host)")
            return
        }

        let rawPath = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let relativePath = rawPath.isEmpty ? (ext.effectivePopupRelativePath ?? "popup.html") : rawPath

        // Guard against directory traversal
        let components = relativePath.split(separator: "/").map(String.init)
        if components.contains("..") || components.contains(".") {
            failTask(urlSchemeTask, taskID: taskID, statusCode: 403, message: "Forbidden path")
            return
        }

        let baseDir = URL(fileURLWithPath: ext.directoryPath, isDirectory: true).standardizedFileURL
        let fileURL = components.reduce(baseDir) { partial, comp in
            partial.appendingPathComponent(comp)
        }.standardizedFileURL

        guard fileURL.path.hasPrefix(baseDir.path),
              FileManager.default.fileExists(atPath: fileURL.path),
              let rawData = try? Data(contentsOf: fileURL) else {
            failTask(urlSchemeTask, taskID: taskID, statusCode: 404, message: "Resource not found: \(relativePath)")
            return
        }

        let extLower = fileURL.pathExtension.lowercased()
        let mimeType = Self.mimeType(forExtension: extLower)
        let responseData: Data

        if extLower == "html" || extLower == "htm",
           let htmlString = String(data: rawData, encoding: .utf8) {
            let isOptions = (ext.manifest.optionsPage.map { relativePath.hasSuffix($0) } == true)
                || relativePath.lowercased().contains("options")
            let contextType: ExtensionRuntimeBridge.ContextType = isOptions ? .options : .popup
            let activeTabNumID = manager.activeTabNumericID()
            let localStore = manager.storageSnapshot(forExtensionID: ext.id, area: "local")
            let syncStore = manager.storageSnapshot(forExtensionID: ext.id, area: "sync")
            let i18n = ExtensionI18nCatalog.load(from: baseDir, defaultLocale: ext.manifest.defaultLocale)
            let polyfill = ExtensionRuntimeBridge.makePolyfillScript(
                extensionItem: ext,
                contextType: contextType,
                tabNumericID: activeTabNumID,
                initialLocalStore: localStore,
                initialSyncStore: syncStore,
                i18nCatalog: i18n
            )
            let resolvedHTML = i18n.resolvePlaceholders(in: htmlString)
            let injectedHTML = Self.injectBootstrapScript(polyfill, intoHTML: resolvedHTML)
            responseData = Data(injectedHTML.utf8)
        } else {
            responseData = rawData
        }

        let headers: [String: String] = [
            "Content-Type": mimeType,
            "Content-Length": "\(responseData.count)",
            "Access-Control-Allow-Origin": "*",
            "Cache-Control": "no-store"
        ]

        guard isTaskActive(taskID) else { return }
        if let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        ) {
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(responseData)
            urlSchemeTask.didFinish()
        } else {
            let fallback = URLResponse(
                url: url,
                mimeType: mimeType,
                expectedContentLength: responseData.count,
                textEncodingName: "utf-8"
            )
            urlSchemeTask.didReceive(fallback)
            urlSchemeTask.didReceive(responseData)
            urlSchemeTask.didFinish()
        }
        removeTask(taskID)
    }

    public func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        let taskID = ObjectIdentifier(urlSchemeTask)
        removeTask(taskID)
    }

    private func isTaskActive(_ taskID: ObjectIdentifier) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return activeTaskIDs.contains(taskID)
    }

    private func removeTask(_ taskID: ObjectIdentifier) {
        lock.lock()
        activeTaskIDs.remove(taskID)
        lock.unlock()
    }

    private func failTask(_ task: WKURLSchemeTask, taskID: ObjectIdentifier, statusCode: Int, message: String) {
        guard isTaskActive(taskID) else { return }
        removeTask(taskID)
        let url = task.request.url ?? URL(string: "zhuo-extension://invalid")!
        let body = Data(message.utf8)
        if let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": "text/plain; charset=utf-8",
                "Access-Control-Allow-Origin": "*"
            ]
        ) {
            task.didReceive(response)
            task.didReceive(body)
            task.didFinish()
        } else {
            task.didFailWithError(URLError(.fileDoesNotExist))
        }
    }

    public static func injectBootstrapScript(_ scriptSource: String, intoHTML html: String) -> String {
        let tag = "<script data-zhuo-extension-bootstrap=\"true\">\n\(scriptSource)\n</script>\n"
        if let headRange = html.range(of: "<head>", options: .caseInsensitive) {
            var copy = html
            copy.insert(contentsOf: "\n" + tag, at: headRange.upperBound)
            return copy
        } else if let htmlRange = html.range(of: "<html>", options: .caseInsensitive) {
            var copy = html
            copy.insert(contentsOf: "\n<head>" + tag + "</head>", at: htmlRange.upperBound)
            return copy
        } else {
            return tag + html
        }
    }

    public static func mimeType(forExtension ext: String) -> String {
        switch ext.lowercased() {
        case "html", "htm":
            return "text/html; charset=utf-8"
        case "js", "mjs":
            return "application/javascript; charset=utf-8"
        case "css":
            return "text/css; charset=utf-8"
        case "json":
            return "application/json; charset=utf-8"
        case "svg":
            return "image/svg+xml"
        case "png":
            return "image/png"
        case "jpg", "jpeg":
            return "image/jpeg"
        case "gif":
            return "image/gif"
        case "webp":
            return "image/webp"
        case "ico":
            return "image/x-icon"
        case "woff":
            return "font/woff"
        case "woff2":
            return "font/woff2"
        case "ttf":
            return "font/ttf"
        case "wasm":
            return "application/wasm"
        default:
            return "application/octet-stream"
        }
    }
}
