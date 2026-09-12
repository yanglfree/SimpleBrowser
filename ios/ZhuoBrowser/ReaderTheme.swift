import SwiftUI

enum ReaderPaper: Int, Codable, CaseIterable {
    case white = 0
    case sepia = 1
    case night = 2
}

struct ReaderTheme {
    let background: String
    let pillBackground: String
    let pillBorder: String
    let textPrimary: String
    let textSecondary: String
    let border: String
    let isDark: Bool
    let body: String
    let title: String
    let accent: String = "#2E6B5C"

    static func theme(for paper: ReaderPaper) -> ReaderTheme {
        switch paper {
        case .white:
            return ReaderTheme(
                background: "#FFFFFF",
                pillBackground: "#F4F3EF",
                pillBorder: "#E6E3DC",
                textPrimary: "#1A1A18",
                textSecondary: "#7A7870",
                border: "#EAE7E1",
                isDark: false,
                body: "#3A3934",
                title: "#1A1A18"
            )
        case .night:
            return ReaderTheme(
                background: "#26251F",
                pillBackground: "#33322B",
                pillBorder: "#424037",
                textPrimary: "#F5F3EE",
                textSecondary: "#8E8B82",
                border: "#383630",
                isDark: true,
                body: "#C9C6BE",
                title: "#F5F3EE"
            )
        case .sepia:
            return ReaderTheme(
                background: "#F1EFEA",
                pillBackground: "#E6E3DC",
                pillBorder: "#D8D4CA",
                textPrimary: "#1A1A18",
                textSecondary: "#7A7870",
                border: "#E2DDD5",
                isDark: false,
                body: "#3A3934",
                title: "#1A1A18"
            )
        }
    }
}

struct ReaderSettings: Codable, Equatable {
    var fontSize: Int = 17
    var lineHeightIndex: Int = 1
    var paper: ReaderPaper = .sepia

    static let fontMin = 15
    static let fontMax = 21
    static let fontStep = 2
    static let lineHeights = [170, 205, 240]

    var canShrink: Bool { fontSize - Self.fontStep >= Self.fontMin }
    var canGrow: Bool { fontSize + Self.fontStep <= Self.fontMax }
    var lineHeightCSS: String {
        let value = Double(Self.lineHeights[min(max(lineHeightIndex, 0), Self.lineHeights.count - 1)]) / 100
        return String(format: "%.2f", value)
    }

    mutating func shrink() {
        if canShrink {
            fontSize -= Self.fontStep
        }
    }

    mutating func grow() {
        if canGrow {
            fontSize += Self.fontStep
        }
    }

    mutating func cycleLineHeight() {
        lineHeightIndex = (lineHeightIndex + 1) % Self.lineHeights.count
    }
}

extension Color {
    init(hex: String) {
        let trimmed = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: trimmed).scanHexInt64(&value)
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
