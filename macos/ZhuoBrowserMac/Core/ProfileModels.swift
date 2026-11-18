import AppKit
import Foundation
import SwiftUI

/// Represents a Chrome-style browser profile with isolated WebKit data, cookies,
/// session storage, bookmarks, history, and open tab state.
public struct BrowserProfile: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var avatarSymbol: String
    public var colorHex: String
    public let isDefault: Bool
    public let createdAt: Date
    public var lastActiveAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        avatarSymbol: String = ProfilePalette.defaultSymbol,
        colorHex: String = ProfilePalette.defaultColorHex,
        isDefault: Bool = false,
        createdAt: Date = Date(),
        lastActiveAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.avatarSymbol = avatarSymbol
        self.colorHex = colorHex
        self.isDefault = isDefault
        self.createdAt = createdAt
        self.lastActiveAt = lastActiveAt
    }

    public var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? (isDefault ? "个人" : "个人资料") : trimmed
    }

    public var shortInitial: String {
        let first = displayName.prefix(1)
        return first.isEmpty ? "P" : String(first).uppercased()
    }

    public var tintColor: Color {
        ProfilePalette.color(fromHex: colorHex)
    }

    public var nsTintColor: NSColor {
        ProfilePalette.nsColor(fromHex: colorHex)
    }
}

/// Persisted container for all browser profiles and the most recently focused profile ID.
public struct PersistedProfileRegistry: Codable, Equatable {
    public var profiles: [BrowserProfile]
    public var lastActiveProfileID: UUID?

    public init(profiles: [BrowserProfile], lastActiveProfileID: UUID? = nil) {
        self.profiles = profiles
        self.lastActiveProfileID = lastActiveProfileID
    }
}

/// Curated Chrome-style color and symbol options for browser profiles.
public enum ProfilePalette {
    public static let defaultColorHex = "#3B82F6"
    public static let defaultSymbol = "person.fill"

    public static let colorOptions: [(name: String, hex: String)] = [
        ("海蓝", "#3B82F6"),
        ("翠绿", "#10B981"),
        ("靛紫", "#8B5CF6"),
        ("琥珀", "#F59E0B"),
        ("玫粉", "#EC4899"),
        ("珊瑚红", "#EF4444"),
        ("青碧", "#06B6D4"),
        ("深靛", "#6366F1")
    ]

    public static let symbolOptions: [(name: String, symbol: String)] = [
        ("个人", "person.fill"),
        ("工作", "briefcase.fill"),
        ("学习", "graduationcap.fill"),
        ("灵感", "sparkles"),
        ("开发", "terminal.fill"),
        ("全球", "globe.americas.fill"),
        ("娱乐", "gamecontroller.fill"),
        ("星标", "star.fill"),
        ("极速", "bolt.fill"),
        ("生活", "leaf.fill")
    ]

    public static func nextSuggestedColorHex(existingCount: Int) -> String {
        guard !colorOptions.isEmpty else { return defaultColorHex }
        return colorOptions[existingCount % colorOptions.count].hex
    }

    public static func nextSuggestedSymbol(existingCount: Int) -> String {
        guard !symbolOptions.isEmpty else { return defaultSymbol }
        return symbolOptions[existingCount % symbolOptions.count].symbol
    }

    public static func color(fromHex hex: String) -> Color {
        Color(nsColor: nsColor(fromHex: hex))
    }

    public static func nsColor(fromHex hex: String) -> NSColor {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6, let rgb = UInt64(cleaned, radix: 16) else {
            return NSColor.systemBlue
        }
        let red = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
        let green = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
        let blue = CGFloat(rgb & 0x0000FF) / 255.0
        return NSColor(srgbRed: red, green: green, blue: blue, alpha: 1.0)
    }
}
