import SwiftUI
import UIKit

/// Semantic tokens derived from `core/tokens/color.json` / DESIGN.md.
enum DesignTokens {
    static let pageBackground = dynamic(light: 0xFAF9F7, dark: 0x171816)
    static let surfacePanel = dynamic(light: 0xFFFFFF, dark: 0x232521)
    static let surfaceSubtle = dynamic(light: 0xF1EFEA, dark: 0x30332E)
    static let textPrimary = dynamic(light: 0x1A1A18, dark: 0xF5F3EE)
    static let textSecondary = dynamic(light: 0x8B877F, dark: 0xAAA69D)
    static let border = dynamic(light: 0xE5E2DB, dark: 0x3B3E38)
    static let accent = dynamic(light: 0x2E6B5C, dark: 0x79B8A6)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
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
}
