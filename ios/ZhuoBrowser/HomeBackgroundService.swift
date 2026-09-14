import Foundation
import ImageIO
import UIKit

enum HomeBackgroundService {
    private static let customFileName = "custom.jpg"
    private static let dailyFileName = "bing-daily.jpg"
    private static let maximumCustomSourceBytes = 100 * 1_024 * 1_024

    static func cachedImageData(for style: HomeBackgroundStyle) -> Data? {
        guard let url = cacheURL(for: style) else { return nil }
        return try? Data(contentsOf: url, options: [.mappedIfSafe])
    }

    static func importCustomImage(_ sourceData: Data) throws -> Data {
        guard sourceData.count <= maximumCustomSourceBytes,
              let source = CGImageSourceCreateWithData(sourceData as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 4_096
                ] as CFDictionary
              ),
              let normalized = UIImage(cgImage: thumbnail).jpegData(compressionQuality: 0.9) else {
            throw HomeBackgroundError.unsupportedImage
        }
        try write(normalized, to: cacheURL(for: .custom)!)
        return normalized
    }

    static func dailyImageData(now: Date = Date()) async -> Data? {
        let target = cacheURL(for: .daily)!
        if let cached = validCachedJPEG(at: target), isFresh(target, now: now) {
            return cached
        }
        let stale = validCachedJPEG(at: target)
        guard let metadata = await fetch(BingDailyWallpaperPolicy.archiveURL, accepting: "application/json"),
              let imageURL = BingDailyWallpaperPolicy.resolveImageURL(from: metadata),
              let image = await fetch(imageURL, accepting: "image/jpeg"),
              BingDailyWallpaperPolicy.isSupportedJPEG(image) else {
            return stale
        }
        do {
            try write(image, to: target)
            return image
        } catch {
            return stale
        }
    }

    private static func fetch(_ url: URL, accepting contentType: String) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue(contentType, forHTTPHeaderField: "Accept")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 18
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  data.count <= BingDailyWallpaperPolicy.maximumImageBytes else { return nil }
            return data
        } catch {
            return nil
        }
    }

    private static func validCachedJPEG(at url: URL) -> Data? {
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]),
              BingDailyWallpaperPolicy.isSupportedJPEG(data) else { return nil }
        return data
    }

    private static func isFresh(_ url: URL, now: Date) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modifiedAt = attributes[.modificationDate] as? Date else { return false }
        return BingDailyWallpaperPolicy.isFresh(modifiedAt: modifiedAt, now: now)
    }

    private static func cacheURL(for style: HomeBackgroundStyle) -> URL? {
        let name: String
        switch style {
        case .custom: name = customFileName
        case .daily: name = dailyFileName
        default: return nil
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ZhuoBrowser/HomeBackgrounds", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent(name, isDirectory: false)
    }

    private static func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: [.atomic])
    }
}

enum HomeBackgroundError: Error {
    case unsupportedImage
}
