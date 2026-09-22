import Foundation

enum BrowserToolbarGestureAction: Equatable {
    case none
    case openActions
    case hideToolbar
    case previousTab
    case nextTab
    case createTab
}

enum BrowserGesturePolicy {
    static let swipeThreshold = 22.0

    static func toolbarAction(
        translationX: Double,
        translationY: Double,
        settings: BrowserSettings,
        isBrowsing: Bool,
        tabCount: Int,
        activeTabIndex: Int,
        isEditingAddress: Bool
    ) -> BrowserToolbarGestureAction {
        guard settings.gesturesEnabled, !isEditingAddress else { return .none }
        if abs(translationY) >= abs(translationX) {
            if translationY <= -swipeThreshold, settings.gestureActionsEnabled {
                return .openActions
            }
            if translationY >= swipeThreshold, settings.autoHideToolbarEnabled, isBrowsing {
                return .hideToolbar
            }
            return .none
        }
        guard settings.gestureTabSwitchEnabled,
              tabCount >= 1,
              abs(translationX) >= swipeThreshold else {
            return .none
        }
        if translationX < 0 {
            if activeTabIndex >= 0 && activeTabIndex == tabCount - 1 {
                return .createTab
            } else if activeTabIndex >= 0 && activeTabIndex < tabCount - 1 {
                return .nextTab
            } else {
                return .none
            }
        } else {
            if activeTabIndex > 0 {
                return .previousTab
            } else {
                return .none
            }
        }
    }

    static func toolbarAction(
        translationX: Double,
        translationY: Double,
        settings: BrowserSettings,
        isBrowsing: Bool,
        tabCount: Int,
        isEditingAddress: Bool
    ) -> BrowserToolbarGestureAction {
        toolbarAction(
            translationX: translationX,
            translationY: translationY,
            settings: settings,
            isBrowsing: isBrowsing,
            tabCount: tabCount,
            activeTabIndex: 0,
            isEditingAddress: isEditingAddress
        )
    }

    static func canOpenBlocking(settings: BrowserSettings, isBrowsing: Bool) -> Bool {
        settings.gesturesEnabled && settings.gestureBlockingEnabled && isBrowsing
    }
}
