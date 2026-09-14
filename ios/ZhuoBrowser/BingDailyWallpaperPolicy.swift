import Foundation

enum BingDailyWallpaperPolicy {
    static let archiveURL = URL(
        string: "https://www.bing.com/HPImageArchive.aspx?format=js&idx=0&n=1&mkt=zh-CN"
    )!
    static let maximumImageBytes = 20 * 1_024 * 1_024

    static func shouldRefresh(
        backgroundEnabled: Bool,
        dailySelected: Bool,
        privacyConsentAccepted: Bool,
        onboardingCompleted: Bool
    ) -> Bool {
        backgroundEnabled && dailySelected && privacyConsentAccepted && onboardingCompleted
    }

    static func resolveImageURL(from data: Data) -> URL? {
        guard let archive = try? JSONDecoder().decode(BingArchive.self, from: data),
              let path = archive.images.first?.url,
              let components = URLComponents(string: "https://www.bing.com\(path)"),
              components.scheme == "https",
              components.host == "www.bing.com",
              components.path == "/th",
              components.queryItems?.contains(where: { $0.name == "id" && !($0.value ?? "").isEmpty }) == true else {
            return nil
        }
        return components.url
    }

    static func isFresh(modifiedAt: Date, now: Date, calendar: Calendar = .current) -> Bool {
        modifiedAt <= now && calendar.isDate(modifiedAt, inSameDayAs: now)
    }

    static func isSupportedJPEG(_ data: Data) -> Bool {
        guard data.count >= 4, data.count <= maximumImageBytes else { return false }
        return data.starts(with: [0xFF, 0xD8]) && data.suffix(2) == Data([0xFF, 0xD9])
    }

    private struct BingArchive: Decodable {
        let images: [Image]

        struct Image: Decodable {
            let url: String
        }
    }
}
