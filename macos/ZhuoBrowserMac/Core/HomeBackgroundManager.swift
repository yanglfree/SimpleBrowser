import AppKit
import Combine
import Foundation
import ImageIO

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

/// Metadata for a single Bing daily wallpaper (today or archived historical entry).
public struct BingWallpaperItem: Codable, Identifiable, Equatable, Hashable {
    public let date: String
    public let startDate: String?
    public let title: String
    public let copyright: String
    public let copyrightLink: String?
    public let imageUrl: String
    public let thumbnailUrl: String
    public let bingImageUrl: String?
    public let bingThumbnailUrl: String?

    public var id: String { date }

    public init(
        date: String,
        startDate: String? = nil,
        title: String,
        copyright: String = "",
        copyrightLink: String? = nil,
        imageUrl: String,
        thumbnailUrl: String,
        bingImageUrl: String? = nil,
        bingThumbnailUrl: String? = nil
    ) {
        self.date = date
        self.startDate = startDate
        self.title = title
        self.copyright = copyright
        self.copyrightLink = copyrightLink
        self.imageUrl = imageUrl
        self.thumbnailUrl = thumbnailUrl
        self.bingImageUrl = bingImageUrl
        self.bingThumbnailUrl = bingThumbnailUrl
    }

    /// Short display date such as "11-01".
    public var formattedShortDate: String {
        guard date.count == 8 else { return date }
        let mStart = date.index(date.startIndex, offsetBy: 4)
        let dStart = date.index(date.startIndex, offsetBy: 6)
        return "\(date[mStart..<dStart])-\(date[dStart...])"
    }

    /// Full ISO-like display date such as "2026-11-01".
    public var formattedFullDate: String {
        guard date.count == 8 else { return date }
        let yEnd = date.index(date.startIndex, offsetBy: 4)
        let mEnd = date.index(date.startIndex, offsetBy: 6)
        return "\(date[..<yEnd])-\(date[yEnd..<mEnd])-\(date[mEnd...])"
    }

    public var resolvedImageURL: URL? {
        if imageUrl.hasPrefix("http://") || imageUrl.hasPrefix("https://") {
            return URL(string: imageUrl)
        }
        return URL(string: "\(AccountManager.serverBaseURL)\(imageUrl)")
    }

    public var resolvedThumbnailURL: URL? {
        if thumbnailUrl.hasPrefix("http://") || thumbnailUrl.hasPrefix("https://") {
            return URL(string: thumbnailUrl)
        }
        return URL(string: "\(AccountManager.serverBaseURL)\(thumbnailUrl)")
    }

    public var fallbackBingImageURL: URL? {
        guard let bingImageUrl, !bingImageUrl.isEmpty else { return nil }
        return URL(string: bingImageUrl)
    }

    public var fallbackBingThumbnailURL: URL? {
        guard let bingThumbnailUrl, !bingThumbnailUrl.isEmpty else { return nil }
        return URL(string: bingThumbnailUrl)
    }
}

/// Manages background wallpapers for the minimal home start page,
/// supporting Cloudflare-archived Bing daily wallpaper history and bundled presets.
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

    private let bingArchiveURLBatch0 = URL(string: "https://www.bing.com/HPImageArchive.aspx?format=js&idx=0&n=8&mkt=zh-CN")!
    private let bingArchiveURLBatch1 = URL(string: "https://www.bing.com/HPImageArchive.aspx?format=js&idx=7&n=8&mkt=zh-CN")!
    private let userDefaults: UserDefaults
    private let isPersistenceEnabled: Bool

    private let sourceKey = "ZhuoBrowser_WallpaperSource"
    private let presetIdKey = "ZhuoBrowser_WallpaperPresetID"
    private let bingSelectedDateKey = "ZhuoBrowser_WallpaperBingDate"
    private let customImageFileName = "home_background_custom.image"
    private let dailyImageFileName = "home_background_bing_daily.jpg"
    private let bingHistoryCacheFileName = "bing_history_cache.json"

    @Published public private(set) var source: WallpaperSource = .daily
    @Published public private(set) var selectedPresetId: String = "arch"
    /// `nil` means automatically follow today's latest Bing wallpaper;
    /// a `YYYYMMDD` value pins a specific historical Bing wallpaper.
    @Published public private(set) var selectedBingDate: String? = nil
    @Published public private(set) var bingHistory: [BingWallpaperItem] = []
    @Published public private(set) var bingThumbnails: [String: NSImage] = [:]
    @Published public private(set) var presetThumbnails: [String: NSImage] = [:]
    @Published public private(set) var currentImage: NSImage?
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var isLoadingHistory: Bool = false

    private let storageDirectory: URL
    private let bingCacheDirectory: URL
    private var wallpaperMemoryCache: [String: NSImage] = [:]
    private var wallpaperLoadGeneration: UInt64 = 0
    private var isPreloadingPresetThumbnails: Bool = false

    public var activeBingWallpaper: BingWallpaperItem? {
        if let selectedBingDate,
           let item = bingHistory.first(where: { $0.date == selectedBingDate }) {
            return item
        }
        return bingHistory.first
    }

    public init(isPersistenceEnabled: Bool = !RuntimeEnvironment.isRunningUnitTests) {
        self.isPersistenceEnabled = isPersistenceEnabled
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupport = paths[0].appendingPathComponent("ZhuoBrowserMac", isDirectory: true)
        let bingDir = appSupport.appendingPathComponent("bing_cache", isDirectory: true)
        self.storageDirectory = appSupport
        self.bingCacheDirectory = bingDir
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: bingDir, withIntermediateDirectories: true)

        if isPersistenceEnabled {
            self.userDefaults = .standard
        } else {
            self.userDefaults = UserDefaults(suiteName: "com.youdroid.zhuobrowser.mac.wallpaper-tests.\(UUID().uuidString)") ?? .standard
        }
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

        if let savedDate = userDefaults.string(forKey: bingSelectedDateKey),
           savedDate.count == 8 {
            self.selectedBingDate = savedDate
        } else {
            self.selectedBingDate = nil
        }

        loadCachedBingHistory()
        loadPresetThumbnailsAsync()
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

    /// Selects a specific Bing wallpaper by `YYYYMMDD` date, or `nil` to follow today's daily wallpaper automatically.
    public func selectBingWallpaper(date: String?) {
        let normalized = (date?.isEmpty == false) ? date : nil
        selectedBingDate = normalized
        if let normalized {
            userDefaults.set(normalized, forKey: bingSelectedDateKey)
        } else {
            userDefaults.removeObject(forKey: bingSelectedDateKey)
        }
        source = .daily
        userDefaults.set(WallpaperSource.daily.rawValue, forKey: sourceKey)
        loadDailyImage(forceNetwork: false)
    }

    /// Steps backward (`offset = 1`, older) or forward (`offset = -1`, newer) in the Bing wallpaper history.
    public func stepBingWallpaper(offset: Int) {
        guard !bingHistory.isEmpty else { return }
        let currentIndex: Int = {
            if let selectedBingDate,
               let idx = bingHistory.firstIndex(where: { $0.date == selectedBingDate }) {
                return idx
            }
            return 0
        }()
        let nextIndex = max(0, min(bingHistory.count - 1, currentIndex + offset))
        let targetDate = bingHistory[nextIndex].date
        selectBingWallpaper(date: targetDate)
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
        Task {
            await refreshBingHistory(force: true)
            if source == .daily {
                await fetchAndApplyActiveBingWallpaper(force: true)
            }
        }
    }

    public func refreshBingHistoryIfNeeded() {
        if bingHistory.isEmpty {
            Task {
                await refreshBingHistory(force: false)
            }
        } else {
            preloadMissingBingThumbnails()
        }
    }

    // MARK: - Parsing Helpers (Testable)

    nonisolated public static func parseServerWallpapersJSON(_ data: Data) -> [BingWallpaperItem] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = root["wallpapers"] as? [[String: Any]] else {
            return []
        }
        var items: [BingWallpaperItem] = []
        var seen = Set<String>()
        for entry in list {
            guard let date = entry["date"] as? String,
                  date.count == 8,
                  !seen.contains(date),
                  let imageUrl = entry["imageUrl"] as? String,
                  let thumbnailUrl = entry["thumbnailUrl"] as? String else {
                continue
            }
            seen.insert(date)
            let title = (entry["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "必应每日壁纸"
            let copyright = (entry["copyright"] as? String) ?? ""
            let copyrightLink = entry["copyrightLink"] as? String
            let startDate = entry["startDate"] as? String
            let bingImageUrl = entry["bingImageUrl"] as? String
            let bingThumbnailUrl = entry["bingThumbnailUrl"] as? String

            items.append(
                BingWallpaperItem(
                    date: date,
                    startDate: startDate,
                    title: title.isEmpty ? "必应每日壁纸" : title,
                    copyright: copyright,
                    copyrightLink: copyrightLink,
                    imageUrl: imageUrl,
                    thumbnailUrl: thumbnailUrl,
                    bingImageUrl: bingImageUrl,
                    bingThumbnailUrl: bingThumbnailUrl
                )
            )
        }
        return items.sorted { $0.date > $1.date }
    }

    nonisolated public static func parseBingArchiveJSON(_ data: Data) -> [BingWallpaperItem] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let images = root["images"] as? [[String: Any]] else {
            return []
        }
        var items: [BingWallpaperItem] = []
        var seen = Set<String>()
        for entry in images {
            guard let endDate = entry["enddate"] as? String,
                  endDate.count == 8,
                  !seen.contains(endDate) else {
                continue
            }
            let urlBase: String? = {
                if let base = entry["urlbase"] as? String, base.hasPrefix("/th?id=") {
                    return base
                }
                if let rel = entry["url"] as? String,
                   let range = rel.range(of: "_1920x1080") ?? rel.range(of: "_UHD") {
                    return String(rel[..<range.lowerBound])
                }
                return nil
            }()
            guard let resolvedBase = urlBase else { continue }
            seen.insert(endDate)

            let fullURL = "https://www.bing.com\(resolvedBase)_1920x1080.jpg"
            let thumbURL = "https://www.bing.com\(resolvedBase)_400x240.jpg"
            let title = (entry["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "必应每日壁纸"
            let copyright = (entry["copyright"] as? String) ?? ""
            let copyrightLink = entry["copyrightlink"] as? String
            let startDate = entry["startdate"] as? String

            items.append(
                BingWallpaperItem(
                    date: endDate,
                    startDate: startDate,
                    title: title.isEmpty ? "必应每日壁纸" : title,
                    copyright: copyright,
                    copyrightLink: copyrightLink,
                    imageUrl: fullURL,
                    thumbnailUrl: thumbURL,
                    bingImageUrl: fullURL,
                    bingThumbnailUrl: thumbURL
                )
            )
        }
        return items.sorted { $0.date > $1.date }
    }

    // MARK: - Internal Loading

    private func loadCurrentWallpaper() {
        wallpaperLoadGeneration &+= 1
        switch source {
        case .none:
            currentImage = nil
        case .preset:
            loadPresetImage(id: selectedPresetId)
        case .custom:
            loadCustomImage()
        case .daily:
            loadDailyImage(forceNetwork: false)
        }
    }

    nonisolated private static func resolvePresetFileURL(filename: String) -> URL? {
        if let imageURL = Bundle.main.url(forResource: filename, withExtension: nil, subdirectory: "wallpapers") ??
            Bundle.main.url(forResource: filename, withExtension: nil) {
            return imageURL
        }
        if let resPath = Bundle.main.resourcePath {
            let directURL = URL(fileURLWithPath: resPath)
                .appendingPathComponent("wallpapers")
                .appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: directURL.path) {
                return directURL
            }
        }
        return nil
    }

    private func loadPresetThumbnailsAsync() {
        guard presetThumbnails.count < Self.presets.count, !isPreloadingPresetThumbnails else { return }
        isPreloadingPresetThumbnails = true
        let presetsToLoad = Self.presets.filter { presetThumbnails[$0.id] == nil }
        Task.detached(priority: .utility) { [weak self] in
            var loaded: [String: NSImage] = [:]
            for preset in presetsToLoad {
                guard let url = Self.resolvePresetFileURL(filename: preset.filename) else { continue }
                if let thumb = Self.downsampleImage(at: url, maxPixelSize: 240) {
                    loaded[preset.id] = thumb
                }
            }
            await MainActor.run { [weak self, loaded] in
                guard let self else { return }
                self.isPreloadingPresetThumbnails = false
                if !loaded.isEmpty {
                    var updated = self.presetThumbnails
                    for (k, v) in loaded {
                        updated[k] = v
                    }
                    self.presetThumbnails = updated
                }
            }
        }
    }

    private func loadPresetImage(id: String) {
        guard let preset = Self.presets.first(where: { $0.id == id }) else {
            currentImage = nil
            return
        }
        let cacheKey = "preset:\(id)"
        if let cached = wallpaperMemoryCache[cacheKey] {
            self.currentImage = cached
            return
        }
        if let thumb = presetThumbnails[id] {
            self.currentImage = thumb
        }
        guard let url = Self.resolvePresetFileURL(filename: preset.filename) else {
            self.currentImage = nil
            return
        }
        let generation = wallpaperLoadGeneration
        Task.detached(priority: .userInitiated) { [weak self] in
            let decoded = Self.downsampleImage(at: url, maxPixelSize: 2880) ?? NSImage(contentsOf: url)
            await MainActor.run { [weak self] in
                guard let self, let decoded else { return }
                self.wallpaperMemoryCache[cacheKey] = decoded
                if self.wallpaperLoadGeneration == generation && self.source == .preset && self.selectedPresetId == id {
                    self.currentImage = decoded
                }
            }
        }
    }

    private func loadCustomImage() {
        let fileURL = storageDirectory.appendingPathComponent(customImageFileName)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            self.currentImage = nil
            return
        }
        let cacheKey = "custom"
        if let cached = wallpaperMemoryCache[cacheKey] {
            self.currentImage = cached
            return
        }
        let generation = wallpaperLoadGeneration
        Task.detached(priority: .userInitiated) { [weak self] in
            let decoded = Self.downsampleImage(at: fileURL, maxPixelSize: 2880) ?? NSImage(contentsOf: fileURL)
            await MainActor.run { [weak self] in
                guard let self else { return }
                if let decoded {
                    self.wallpaperMemoryCache[cacheKey] = decoded
                }
                if self.wallpaperLoadGeneration == generation && self.source == .custom {
                    self.currentImage = decoded
                }
            }
        }
    }

    private func loadDailyImage(forceNetwork: Bool) {
        // 1. If a specific date (or today's top item) is already cached in memory or on disk, apply without blocking the main thread.
        let targetDate = selectedBingDate ?? bingHistory.first?.date
        if !forceNetwork, let targetDate {
            let cacheKey = "bing:\(targetDate)"
            if let memCached = wallpaperMemoryCache[cacheKey] {
                self.currentImage = memCached
                if selectedBingDate == nil && !isDateTodayInBeijing(targetDate) {
                    Task {
                        await refreshBingHistory(force: false)
                        await fetchAndApplyActiveBingWallpaper(force: false)
                    }
                }
                return
            }
            if let thumb = bingThumbnails[targetDate] {
                self.currentImage = thumb
            }
            let cachedDateFile = bingFullCacheURL(for: targetDate)
            if FileManager.default.fileExists(atPath: cachedDateFile.path) {
                let generation = wallpaperLoadGeneration
                let needsBackgroundRefresh = (selectedBingDate == nil && !isDateTodayInBeijing(targetDate))
                Task.detached(priority: .userInitiated) { [weak self] in
                    let decoded = Self.downsampleImage(at: cachedDateFile, maxPixelSize: 2880) ?? NSImage(contentsOf: cachedDateFile)
                    await MainActor.run { [weak self] in
                        guard let self else { return }
                        if let decoded {
                            self.wallpaperMemoryCache[cacheKey] = decoded
                            if self.wallpaperLoadGeneration == generation && self.source == .daily {
                                self.currentImage = decoded
                            }
                        }
                        if needsBackgroundRefresh {
                            Task {
                                await self.refreshBingHistory(force: false)
                                await self.fetchAndApplyActiveBingWallpaper(force: false)
                            }
                        }
                    }
                }
                return
            }
        } else if !forceNetwork && selectedBingDate == nil {
            let legacyURL = storageDirectory.appendingPathComponent(dailyImageFileName)
            if FileManager.default.fileExists(atPath: legacyURL.path),
               isFileFresh(url: legacyURL) {
                let generation = wallpaperLoadGeneration
                Task.detached(priority: .userInitiated) { [weak self] in
                    let decoded = Self.downsampleImage(at: legacyURL, maxPixelSize: 2880) ?? NSImage(contentsOf: legacyURL)
                    await MainActor.run { [weak self] in
                        guard let self, let decoded else { return }
                        if self.wallpaperLoadGeneration == generation && self.source == .daily {
                            self.currentImage = decoded
                        }
                    }
                }
            }
        }

        Task {
            if bingHistory.isEmpty || (selectedBingDate == nil && !isDateTodayInBeijing(bingHistory.first?.date ?? "")) {
                await refreshBingHistory(force: forceNetwork)
            }
            await fetchAndApplyActiveBingWallpaper(force: forceNetwork)
        }
    }

    private func importCustomImage(from url: URL) {
        do {
            let targetURL = storageDirectory.appendingPathComponent(customImageFileName)
            if FileManager.default.fileExists(atPath: targetURL.path) {
                try FileManager.default.removeItem(at: targetURL)
            }
            try FileManager.default.copyItem(at: url, to: targetURL)
            self.wallpaperMemoryCache.removeValue(forKey: "custom")
            self.source = .custom
            self.userDefaults.set(WallpaperSource.custom.rawValue, forKey: sourceKey)
            loadCustomImage()
        } catch {
            print("Failed to import custom background image: \(error)")
        }
    }

    // MARK: - Bing History & Image Fetching

    public func refreshBingHistory(force: Bool = false) async {
        if isLoadingHistory && !force { return }
        isLoadingHistory = true
        defer { isLoadingHistory = false }

        var fetchedItems: [BingWallpaperItem] = []

        // 1. Primary: Cloudflare Worker D1 + R2 Wallpaper Archive API
        if let serverURL = URL(string: "\(AccountManager.serverBaseURL)/api/wallpapers/bing?limit=30") {
            var request = URLRequest(url: serverURL)
            request.timeoutInterval = 10
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            if let (data, response) = try? await URLSession.shared.data(for: request),
               let http = response as? HTTPURLResponse,
               (200..<300).contains(http.statusCode) {
                fetchedItems = Self.parseServerWallpapersJSON(data)
            }
        }

        // 2. Fallback: Direct Microsoft Bing HPImageArchive (up to 15 days)
        if fetchedItems.isEmpty {
            var combined: [BingWallpaperItem] = []
            var seen = Set<String>()
            for archiveURL in [bingArchiveURLBatch0, bingArchiveURLBatch1] {
                if let (data, _) = try? await URLSession.shared.data(from: archiveURL) {
                    for item in Self.parseBingArchiveJSON(data) where !seen.contains(item.date) {
                        seen.insert(item.date)
                        combined.append(item)
                    }
                }
            }
            fetchedItems = combined.sorted { $0.date > $1.date }
        }

        guard !fetchedItems.isEmpty else { return }

        // Merge with existing cached history so older dates are never lost locally
        var mergedByDate: [String: BingWallpaperItem] = [:]
        for old in bingHistory {
            mergedByDate[old.date] = old
        }
        for fresh in fetchedItems {
            mergedByDate[fresh.date] = fresh
        }
        let sortedHistory = mergedByDate.values.sorted { $0.date > $1.date }
        self.bingHistory = sortedHistory
        saveCachedBingHistory(sortedHistory)
        preloadMissingBingThumbnails()
    }

    private func fetchAndApplyActiveBingWallpaper(force: Bool) async {
        let item: BingWallpaperItem? = {
            if let selectedBingDate {
                return bingHistory.first(where: { $0.date == selectedBingDate }) ?? activeBingWallpaper
            }
            return bingHistory.first
        }()

        guard let targetItem = item else { return }

        let dateFileURL = bingFullCacheURL(for: targetItem.date)
        let legacyFileURL = storageDirectory.appendingPathComponent(dailyImageFileName)
        let cacheKey = "bing:\(targetItem.date)"

        if !force, let memCached = wallpaperMemoryCache[cacheKey] {
            if source == .daily {
                self.currentImage = memCached
            }
            return
        }

        if !force && FileManager.default.fileExists(atPath: dateFileURL.path) {
            let decoded = await Task.detached(priority: .userInitiated) {
                Self.downsampleImage(at: dateFileURL, maxPixelSize: 2880) ?? NSImage(contentsOf: dateFileURL)
            }.value
            if let decoded {
                wallpaperMemoryCache[cacheKey] = decoded
                if source == .daily {
                    self.currentImage = decoded
                }
                return
            }
        }

        self.isLoading = true
        defer { self.isLoading = false }

        let shouldWriteLegacy = (selectedBingDate == nil || selectedBingDate == bingHistory.first?.date)
        let needsThumb = (bingThumbnails[targetItem.date] == nil)
        let candidateURLs = [targetItem.resolvedImageURL, targetItem.fallbackBingImageURL].compactMap { $0 }
        for url in candidateURLs {
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 15
                let (imageData, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode) else {
                    continue
                }
                let processed = await Task.detached(priority: .userInitiated) { () -> (NSImage?, NSImage?) in
                    let full = Self.downsampleImage(data: imageData, maxPixelSize: 2880) ?? NSImage(data: imageData)
                    guard full != nil else { return (nil, nil) }
                    try? imageData.write(to: dateFileURL, options: .atomic)
                    if shouldWriteLegacy {
                        try? imageData.write(to: legacyFileURL, options: .atomic)
                    }
                    let thumb = needsThumb ? Self.downsampleImage(data: imageData, maxPixelSize: 280) : nil
                    return (full, thumb)
                }.value
                guard let image = processed.0 else { continue }
                wallpaperMemoryCache[cacheKey] = image
                if let thumb = processed.1, bingThumbnails[targetItem.date] == nil {
                    bingThumbnails[targetItem.date] = thumb
                }
                if source == .daily {
                    self.currentImage = image
                }
                return
            } catch {
                continue
            }
        }

        // Fallback to cached file if network failed
        let fallbackImage = await Task.detached(priority: .utility) {
            Self.downsampleImage(at: dateFileURL, maxPixelSize: 2880)
                ?? Self.downsampleImage(at: legacyFileURL, maxPixelSize: 2880)
        }.value
        if let fallbackImage, source == .daily {
            self.currentImage = fallbackImage
        }
    }

    private func preloadMissingBingThumbnails() {
        let missingItems = bingHistory.filter { bingThumbnails[$0.date] == nil }
        guard !missingItems.isEmpty else { return }
        let cacheDir = bingCacheDirectory

        Task.detached(priority: .utility) { [weak self] in
            var diskLoaded: [String: NSImage] = [:]
            var needsNetwork: [BingWallpaperItem] = []

            for item in missingItems {
                let thumbFile = cacheDir.appendingPathComponent("thumb_\(item.date).jpg")
                if FileManager.default.fileExists(atPath: thumbFile.path),
                   let diskThumb = Self.downsampleImage(at: thumbFile, maxPixelSize: 280) ?? NSImage(contentsOf: thumbFile) {
                    diskLoaded[item.date] = diskThumb
                    continue
                }

                let fullFile = cacheDir.appendingPathComponent("full_\(item.date).jpg")
                if FileManager.default.fileExists(atPath: fullFile.path),
                   let downsampled = Self.downsampleImage(at: fullFile, maxPixelSize: 280) {
                    diskLoaded[item.date] = downsampled
                    continue
                }

                needsNetwork.append(item)
            }

            if !diskLoaded.isEmpty {
                await MainActor.run { [weak self, diskLoaded] in
                    guard let self else { return }
                    var updated = self.bingThumbnails
                    for (k, v) in diskLoaded where updated[k] == nil {
                        updated[k] = v
                    }
                    self.bingThumbnails = updated
                }
            }

            for item in needsNetwork {
                guard let self else { break }
                await self.fetchThumbnail(for: item)
            }
        }
    }

    private func fetchThumbnail(for item: BingWallpaperItem) async {
        let thumbFile = bingThumbCacheURL(for: item.date)
        let candidateURLs = [item.resolvedThumbnailURL, item.fallbackBingThumbnailURL].compactMap { $0 }
        for url in candidateURLs {
            var request = URLRequest(url: url)
            request.timeoutInterval = 12
            if let (data, response) = try? await URLSession.shared.data(for: request),
               let http = response as? HTTPURLResponse,
               (200..<300).contains(http.statusCode) {
                let image = await Task.detached(priority: .utility) { () -> NSImage? in
                    guard let decoded = Self.downsampleImage(data: data, maxPixelSize: 280) ?? NSImage(data: data) else {
                        return nil
                    }
                    try? data.write(to: thumbFile, options: .atomic)
                    return decoded
                }.value
                if let image {
                    self.bingThumbnails[item.date] = image
                    return
                }
            }
        }
    }

    // MARK: - Cache & Storage Utilities

    private func loadCachedBingHistory() {
        let fileURL = storageDirectory.appendingPathComponent(bingHistoryCacheFileName)
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([BingWallpaperItem].self, from: data),
              !decoded.isEmpty else {
            return
        }
        self.bingHistory = decoded.sorted { $0.date > $1.date }
        preloadMissingBingThumbnails()
    }

    private func saveCachedBingHistory(_ items: [BingWallpaperItem]) {
        let fileURL = storageDirectory.appendingPathComponent(bingHistoryCacheFileName)
        Task.detached(priority: .utility) {
            if let data = try? JSONEncoder().encode(items) {
                try? data.write(to: fileURL, options: .atomic)
            }
        }
    }

    private func isDateTodayInBeijing(_ dateStr: String) -> Bool {
        guard dateStr.count == 8 else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600) ?? .current
        let comps = calendar.dateComponents([.year, .month, .day], from: Date())
        guard let y = comps.year, let m = comps.month, let d = comps.day else { return false }
        let todayStr = String(format: "%04d%02d%02d", y, m, d)
        return dateStr >= todayStr
    }

    private func isFileFresh(url: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modDate = attributes[.modificationDate] as? Date else {
            return false
        }
        return Calendar.current.isDateInToday(modDate)
    }

    private func bingFullCacheURL(for date: String) -> URL {
        bingCacheDirectory.appendingPathComponent("full_\(date).jpg")
    }

    private func bingThumbCacheURL(for date: String) -> URL {
        bingCacheDirectory.appendingPathComponent("thumb_\(date).jpg")
    }

    nonisolated private static func downsampleImage(at url: URL, maxPixelSize: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return downsampleImage(source: source, maxPixelSize: maxPixelSize)
    }

    nonisolated private static func downsampleImage(data: Data, maxPixelSize: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return downsampleImage(source: source, maxPixelSize: maxPixelSize)
    }

    nonisolated private static func downsampleImage(source: CGImageSource, maxPixelSize: Int) -> NSImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}
