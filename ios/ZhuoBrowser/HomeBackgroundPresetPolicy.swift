import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum HomePortraitBackgroundPreset: String, Codable, CaseIterable, Identifiable {
    case mountain
    case alley
    case river

    var id: String { rawValue }

    var label: String {
        switch self {
        case .mountain: return "山色"
        case .alley: return "静巷"
        case .river: return "河岸"
        }
    }
}

enum HomeLandscapeBackgroundPreset: String, Codable, CaseIterable, Identifiable {
    case arch
    case roof
    case wood

    var id: String { rawValue }

    var label: String {
        switch self {
        case .arch: return "拱廊"
        case .roof: return "屋顶"
        case .wood: return "木纹"
        }
    }
}

enum HomeBackgroundPresetChoice: Equatable, Identifiable {
    case portrait(HomePortraitBackgroundPreset)
    case landscape(HomeLandscapeBackgroundPreset)

    var id: String {
        switch self {
        case let .portrait(preset): return "portrait-\(preset.rawValue)"
        case let .landscape(preset): return "landscape-\(preset.rawValue)"
        }
    }

    var label: String {
        switch self {
        case let .portrait(preset): return preset.label
        case let .landscape(preset): return preset.label
        }
    }

    static func choices(isLandscape: Bool) -> [HomeBackgroundPresetChoice] {
        if isLandscape {
            return HomeLandscapeBackgroundPreset.allCases.map(HomeBackgroundPresetChoice.landscape)
        }
        return HomePortraitBackgroundPreset.allCases.map(HomeBackgroundPresetChoice.portrait)
    }

    func isSelected(in settings: BrowserSettings) -> Bool {
        guard settings.homeBackgroundStyle.isBuiltIn else { return false }
        switch self {
        case let .portrait(preset): return settings.homePortraitPreset == preset
        case let .landscape(preset): return settings.homeLandscapePreset == preset
        }
    }
}

enum HomeBackgroundPresetPolicy {
    static func resourceName(
        portrait: HomePortraitBackgroundPreset,
        landscape: HomeLandscapeBackgroundPreset,
        isLandscape: Bool
    ) -> String {
        isLandscape ? "landscape-\(landscape.rawValue)" : "portrait-\(portrait.rawValue)"
    }

    static func legacyPortraitPreset(for style: HomeBackgroundStyle) -> HomePortraitBackgroundPreset {
        switch style {
        case .dusk: return .alley
        case .ocean: return .river
        default: return .mountain
        }
    }

    static func legacyLandscapePreset(for style: HomeBackgroundStyle) -> HomeLandscapeBackgroundPreset {
        switch style {
        case .dusk: return .roof
        case .ocean: return .wood
        default: return .arch
        }
    }
}

#if canImport(UIKit)
enum HomeBackgroundPresetImageStore {
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 2
        cache.totalCostLimit = 40 * 1024 * 1024
        return cache
    }()

    static func image(
        portrait: HomePortraitBackgroundPreset,
        landscape: HomeLandscapeBackgroundPreset,
        isLandscape: Bool
    ) -> UIImage? {
        let name = HomeBackgroundPresetPolicy.resourceName(
            portrait: portrait,
            landscape: landscape,
            isLandscape: isLandscape
        )
        if let cached = cache.object(forKey: name as NSString) {
            return cached
        }
        guard let url = Bundle.main.url(
            forResource: name,
            withExtension: "jpg",
            subdirectory: "backgrounds"
        ), let image = UIImage(contentsOfFile: url.path) else {
            return nil
        }
        let cost = (image.cgImage?.bytesPerRow ?? 0) * (image.cgImage?.height ?? 0)
        cache.setObject(image, forKey: name as NSString, cost: cost)
        return image
    }
}
#endif
