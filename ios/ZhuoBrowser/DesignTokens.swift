import SwiftUI
import UIKit

/// Semantic tokens aligned with `core/tokens/color.json` and HarmonyOS `color.json`.
enum DesignTokens {
    static let pageBackground = dynamic(light: 0xFAF9F7, dark: 0x131311)
    static let surfacePanel = dynamic(light: 0xFFFFFF, dark: 0x1D1D1A)
    static let surfaceSubtle = dynamic(light: 0xF1EFEA, dark: 0x26251F)
    static let textPrimary = dynamic(light: 0x1A1A18, dark: 0xF5F3EE)
    static let textSecondary = dynamic(light: 0x8B877F, dark: 0x8B877F)
    static let border = dynamic(light: 0xE5E2DB, dark: 0x26251F)
    static let dockIcon = dynamic(light: 0x6E6A62, dark: 0xC2BDB3)
    static let accent = dynamic(light: 0x2E6B5C, dark: 0x84A794)
    static let accentFill = dynamic(light: 0x2E6B5C, dark: 0x2E6B5C)
    static let accentStrong = dynamic(light: 0x2E6B5C, dark: 0x84A794)
    static let accentForeground = dynamic(light: 0xFFFFFF, dark: 0xF5F3EE)
    static let danger = dynamic(light: 0xB3483B, dark: 0xB3483B)
    static let capsuleBackground = dynamicARGB(light: 0xB8FFFFFF, dark: 0xB81D1D1A)
    static let handle = dynamic(light: 0xE5E2DB, dark: 0x3A382F)
    static let scrim = dynamicARGB(light: 0x2E1A1A18, dark: 0x6B000000)
    static let homeScrim = dynamicARGB(light: 0x24000000, dark: 0x32000000)
    static let homeChromeBackground = dynamicARGB(light: 0xC7293029, dark: 0xC7293029)
    static let homeMenuBackground = dynamic(light: 0x202320, dark: 0x202320)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    private static func dynamicARGB(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            UIColor(argb: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }

    convenience init(argb: UInt32) {
        self.init(
            red: CGFloat((argb >> 16) & 0xFF) / 255,
            green: CGFloat((argb >> 8) & 0xFF) / 255,
            blue: CGFloat(argb & 0xFF) / 255,
            alpha: CGFloat((argb >> 24) & 0xFF) / 255
        )
    }
}
