import Foundation

enum BrowserLayoutClass: Int, Equatable {
    case compact = 0
    case medium = 1
    case expanded = 2
    case desktop = 3

    static func resolve(width: Double) -> BrowserLayoutClass {
        if width < 600 { return .compact }
        if width < 840 { return .medium }
        if width < 1_440 { return .expanded }
        return .desktop
    }
}

enum SidebarPresentation: Equatable {
    case unavailable
    case overlay
    case inline
}

enum ArticleWorkbenchMode: Equatable {
    case compact
    case switchableInspector
    case fixedInspector
}

enum AdaptiveWorkspacePolicy {
    static let mediumMinimumWidth = 600.0
    static let expandedMinimumWidth = 840.0
    static let desktopMinimumWidth = 1_440.0
    static let articleInspectorWidth = 320.0
    static let articleReaderMaximumWidth = 760.0

    static func sidebarPresentation(width: Double) -> SidebarPresentation {
        switch BrowserLayoutClass.resolve(width: width) {
        case .compact: return .unavailable
        case .medium: return .overlay
        case .expanded, .desktop: return .inline
        }
    }

    static func sidebarWidth(width: Double) -> Double {
        if width >= 1_440 { return 400 }
        if width >= expandedMinimumWidth { return 360 }
        return min(320, max(0, width))
    }

    static func articleWorkbenchMode(width: Double) -> ArticleWorkbenchMode {
        switch BrowserLayoutClass.resolve(width: width) {
        case .compact: return .compact
        case .medium: return .switchableInspector
        case .expanded, .desktop: return .fixedInspector
        }
    }

    static func showsArticleInspector(width: Double, requested: Bool) -> Bool {
        switch articleWorkbenchMode(width: width) {
        case .compact: return false
        case .switchableInspector: return requested
        case .fixedInspector: return true
        }
    }

    static func articleReaderMaximumWidth(availableWidth: Double, inspectorVisible: Bool) -> Double {
        guard availableWidth > 0 else { return articleReaderMaximumWidth }
        let reserved = inspectorVisible ? articleInspectorWidth : 0
        return min(articleReaderMaximumWidth, max(0, availableWidth - reserved - 48))
    }

    static func tabColumnCount(width: Double) -> Int {
        switch BrowserLayoutClass.resolve(width: width) {
        case .compact: return 2
        case .medium: return 3
        case .expanded, .desktop: return 4
        }
    }

    static func showsDesktopTabStrip(width: Double) -> Bool {
        BrowserLayoutClass.resolve(width: width) == .desktop
    }

    static func desktopTabWidth(
        availableWidth: Double,
        tabCount: Int,
        pinnedCount: Int
    ) -> Double {
        let safeCount = max(0, tabCount)
        let safePinned = min(max(0, pinnedCount), safeCount)
        let regularCount = safeCount - safePinned
        guard regularCount > 0 else { return 88 }
        let itemGaps = Double(safeCount) * 4
        let regularWidth = availableWidth - 16 - 36 - itemGaps - Double(safePinned) * 52
        return min(240, max(88, floor(regularWidth / Double(regularCount))))
    }
}
