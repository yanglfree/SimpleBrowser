import AppKit
import Combine
import Foundation

/// Represents the source of the start page background wallpaper.
public enum WallpaperSource: String, Codable, CaseIterable {
    case daily = "daily"
    case preset = "preset"
    case custom = "custom"
    case none = "none"
}

/// Information about a bundled preset wallpaper.
public struct PresetWallpaper: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let filename: String

    public init(id: String, name: String, filename: String) {
        self.id = id
        self.name = name
        self.filename = filename
    }
}

/// Manages background wallpapers for the minimal home start page,
/// matching the data sources and caching model of HarmonyOS client.
@MainActor
public final class HomeBackgroundManager: ObservableObject {
    public static let shared = HomeBackgroundManager()

    public static let presets: [PresetWallpaper] = [
        PresetWallpaper(id: "arch", name: "拱廊之境", filename: "pexels-lana-154214216-38140707.jpg"),
        PresetWallpaper(id: "roof", name: "屋脊晨曦", filename: "pexels-henry-acevedo-382866382-38767492.jpg"),
        PresetWallpaper(id: "wood", name: "静谧之森", filename: "pexels-jan-van-der-wolf-11680885-38008702.jpg"),
        PresetWallpaper(id: "mountain", name: "雪山远眺", filename: "pexels-damiendufourartiste-27961888.jpg"),
        PresetWallpaper(id: "alley", name: "幽静街巷", filename: "pexels-ersin-1398102958-28351624.jpg")
    ]

    private let bingArchiveURL = URL(string: "https://www.bing.com/HPImageArchive.aspx?format=js&idx=0&n=1&mkt=zh-CN")!
    private let userDefaults = UserDefaults.standard

    private let sourceKey = "ZhuoBrowser_WallpaperSource"
    private let presetIdKey = "ZhuoBrowser_WallpaperPresetID"
    private let customImageFileName = "home_background_custom.image"
    private let dailyImageFileName = "home_background_bing_daily.jpg"

    @Published public private(set) var source: WallpaperSource = .daily
    @Published public private(set) var selectedPresetId: String = "arch"
    @Published public private(set) var currentImage: NSImage?
    @Published public private(set) var isLoading: Bool = false

    public init() {
        if let savedSource = userDefaults.string(forKey: sourceKey),
           let resolvedSource = WallpaperSource(rawValue: savedSource) {
            self.source = resolvedSource
        } else {
            self.source = .daily
        }

        if let savedPreset = userDefaults.string(forKey: presetIdKey),
           Self.presets.contains(where: { $0.id == savedPreset }) {
            self.selectedPresetId = savedPreset
        } else {
            self.selectedPresetId = "arch"
        }

        loadCurrentWallpaper()
    }

    public func setSource(_ newSource: WallpaperSource) {
        source = newSource
        userDefaults.set(newSource.rawValue, forKey: sourceKey)
        loadCurrentWallpaper()
    }

    public func selectPreset(id: String) {
        guard Self.presets.contains(where: { $0.id == id }) else { return }
        selectedPresetId = id
        userDefaults.set(id, forKey: presetIdKey)
        setSource(.preset)
    }

    public func chooseCustomImage() {
        let openPanel = NSOpenPanel()
        openPanel.prompt = "选择壁纸"
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.allowsMultipleSelection = false
        openPanel.allowedContentTypes = [.image, .jpeg, .png]

        if openPanel.runModal() == .OK, let selectedURL = openPanel.url {
            importCustomImage(from: selectedURL)
        }
    }

    public func refreshDaily() {
        guard source == .daily else { return }
        Task {
            await fetchBingDailyImage(force: true)
        }
    }

    private func loadCurrentWallpaper() {
        switch source {
        case .none:
            currentImage = nil
        case .preset:
            loadPresetImage(id: selectedPresetId)
        case .custom:
            loadCustomImage()
        case .daily:
            loadDailyImage()
        }
    }

    private func loadPresetImage(id: String) {
        guard let preset = Self.presets.first(where: { $0.id == id }) else {
            currentImage = nil
            return
        }

        // Try bundle resource
        if let imageURL = Bundle.main.url(forResource: preset.filename, withExtension: nil, subdirectory: "wallpapers") ??
            Bundle.main.url(forResource: preset.filename, withExtension: nil) {
            if let image = NSImage(contentsOf: imageURL) {
                self.currentImage = image
                return
            }
        }

        // Fallback: search in bundle Resources directory directly
        if let resPath = Bundle.main.resourcePath {
            let directURL = URL(fileURLWithPath: resPath).appendingPathComponent("wallpapers").appendingPathComponent(preset.filename)
            if let image = NSImage(contentsOf: directURL) {
                self.currentImage = image
                return
            }
        }

        self.currentImage = nil
    }

    private func loadCustomImage() {
        let fileURL = storageDirectory.appendingPathComponent(customImageFileName)
        if FileManager.default.fileExists(atPath: fileURL.path),
           let image = NSImage(contentsOf: fileURL) {
            self.currentImage = image
        } else {
            self.currentImage = nil
        }
    }

    private func loadDailyImage() {
        let fileURL = storageDirectory.appendingPathComponent(dailyImageFileName)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            // Check cache freshness
            if isFileFresh(url: fileURL), let image = NSImage(contentsOf: fileURL) {
                self.currentImage = image
                return
            }
        }

        // Fetch fresh Bing wallpaper
        Task {
            await fetchBingDailyImage(force: false)
        }
    }

    private func importCustomImage(from url: URL) {
        do {
            let targetURL = storageDirectory.appendingPathComponent(customImageFileName)
            if FileManager.default.fileExists(atPath: targetURL.path) {
                try FileManager.default.removeItem(at: targetURL)
            }
            try FileManager.default.copyItem(at: url, to: targetURL)
            if let image = NSImage(contentsOf: targetURL) {
                self.currentImage = image
                self.source = .custom
                self.userDefaults.set(WallpaperSource.custom.rawValue, forKey: sourceKey)
            }
        } catch {
            print("Failed to import custom background image: \(error)")
        }
    }

    private func fetchBingDailyImage(force: Bool) async {
        let fileURL = storageDirectory.appendingPathComponent(dailyImageFileName)
        if !force && FileManager.default.fileExists(atPath: fileURL.path) && isFileFresh(url: fileURL) {
            if let image = NSImage(contentsOf: fileURL) {
                self.currentImage = image
                return
            }
        }

        self.isLoading = true
        defer { self.isLoading = false }

        do {
            let (data, _) = try await URLSession.shared.data(from: bingArchiveURL)
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let images = json["images"] as? [[String: Any]],
                  let first = images.first,
                  let relativeURL = first["url"] as? String else {
                return
            }

            let absoluteURLString = relativeURL.hasPrefix("http") ? relativeURL : "https://www.bing.com\(relativeURL)"
            guard let imageURL = URL(string: absoluteURLString) else { return }

            let (imageData, _) = try await URLSession.shared.data(from: imageURL)
            try imageData.write(to: fileURL, options: .atomic)

            if let image = NSImage(data: imageData) {
                self.currentImage = image
            }
        } catch {
            print("Failed to fetch daily Bing wallpaper: \(error)")
            // Fallback to existing cached file if available
            if let cached = NSImage(contentsOf: fileURL) {
                self.currentImage = cached
            }
        }
    }

    private func isFileFresh(url: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modDate = attributes[.modificationDate] as? Date else {
            return false
        }
        return Calendar.current.isDateInToday(modDate)
    }

    private var storageDirectory: URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupport = paths[0].appendingPathComponent("ZhuoBrowserMac", isDirectory: true)
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return appSupport
    }
}
