import Foundation

enum BrowserToolbarGestureAction: Equatable {
    case none
    case openActions
    case hideToolbar
    case previousTab
    case nextTab
}

enum BrowserGesturePolicy {
    static let swipeThreshold = 22.0

    static func toolbarAction(
        translationX: Double,
        translationY: Double,
        settings: BrowserSettings,
        isBrowsing: Bool,
        tabCount: Int,
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
              tabCount > 1,
              abs(translationX) >= swipeThreshold else {
            return .none
        }
        return translationX < 0 ? .nextTab : .previousTab
    }

    static func canOpenBlocking(settings: BrowserSettings, isBrowsing: Bool) -> Bool {
        settings.gesturesEnabled && settings.gestureBlockingEnabled && isBrowsing
    }
}
