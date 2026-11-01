import AppKit
import Foundation
import ImageIO

public actor SiteIconStore {
    public static let shared = SiteIconStore()
    private static let browserUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    private let session: URLSession
    private var resolved: [String: Data] = [:]
    private var unavailableHosts = Set<String>()

    public init(session: URLSession? = nil) {
        if let session {
            self.session = session
            return
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 12
        self.session = URLSession(configuration: configuration)
    }

    public func iconData(for pageURL: String, declaredURL: String? = nil) async -> Data? {
        let host = URLPolicy.rawHost(pageURL)
        guard !host.isEmpty else { return nil }
        if let cached = resolved[host] {
            return cached
        }
        if unavailableHosts.contains(host), declaredURL?.isEmpty != false {
            return nil
        }
        if declaredURL?.isEmpty == false {
            unavailableHosts.remove(host)
        }
        if let cached = cachedData(for: host) {
            resolved[host] = cached
            return cached
        }

        // Try direct candidates (declared URL and root fallbacks)
        let initialCandidates = SiteIconPolicy.candidates(pageURL: pageURL, declaredURL: declaredURL, html: nil)
        for candidate in initialCandidates {
            if let data = await fetch(candidate, maximumBytes: SiteIconPolicy.maximumIconBytes),
               isSupportedImage(data) {
                resolved[host] = data
                persist(data, for: host)
                return data
            }
        }

        // Fallback: fetch HTML and extract link icon tags
        let html = await pageHTML(for: pageURL)
        let metadataCandidates = SiteIconPolicy.candidates(pageURL: pageURL, declaredURL: declaredURL, html: html)
        for candidate in metadataCandidates where !initialCandidates.contains(candidate) {
            if let data = await fetch(candidate, maximumBytes: SiteIconPolicy.maximumIconBytes),
               isSupportedImage(data) {
                resolved[host] = data
                persist(data, for: host)
                return data
            }
        }

        unavailableHosts.insert(host)
        return nil
    }

    public func clearMemoryCache() {
        resolved.removeAll()
        unavailableHosts.removeAll()
    }

    private func pageHTML(for rawURL: String) async -> String? {
        guard let url = URL(string: rawURL) else { return nil }
        var request = URLRequest(url: url)
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue(Self.browserUserAgent, forHTTPHeaderField: "User-Agent")
        guard let data = await fetch(request, maximumBytes: SiteIconPolicy.maximumPageBytes) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    private func fetch(_ url: URL, maximumBytes: Int) async -> Data? {
        var request = URLRequest(url: url)
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        request.setValue(Self.browserUserAgent, forHTTPHeaderField: "User-Agent")
        return await fetch(request, maximumBytes: maximumBytes)
    }

    private func fetch(_ request: URLRequest, maximumBytes: Int) async -> Data? {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                (200..<300).contains(http.statusCode),
                data.count > 0,
                data.count <= maximumBytes
            else {
                return nil
            }
            return data
        } catch {
            return nil
        }
    }

    private func cachedData(for host: String) -> Data? {
        guard let fileURL = cacheURL(for: host),
            let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
            let modifiedAt = values.contentModificationDate,
            SiteIconPolicy.isCacheFresh(modifiedAt: modifiedAt),
            let fileSize = values.fileSize,
            fileSize > 0,
            fileSize <= SiteIconPolicy.maximumIconBytes,
            let data = try? Data(contentsOf: fileURL),
            isSupportedImage(data)
        else {
            return nil
        }
        return data
    }

    private func persist(_ data: Data, for host: String) {
        guard let fileURL = cacheURL(for: host) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func cacheURL(for host: String) -> URL? {
        guard let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        let directory = root.appendingPathComponent("site-icons-v1", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileName = SiteIconPolicy.cacheFileName(for: host)
        return fileName.isEmpty ? nil : directory.appendingPathComponent(fileName, isDirectory: false)
    }

    private func isSupportedImage(_ data: Data) -> Bool {
        if let source = CGImageSourceCreateWithData(data as CFData, nil),
            CGImageSourceGetCount(source) > 0,
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
            let height = properties[kCGImagePropertyPixelHeight] as? NSNumber {
            let shortest = min(width.intValue, height.intValue)
            let longest = max(width.intValue, height.intValue)
            return shortest >= 12 && longest <= 2_048
        }
        if let image = NSImage(data: data) {
            return image.isValid && image.size.width >= 12 && image.size.height >= 12
        }
        return false
    }
}
