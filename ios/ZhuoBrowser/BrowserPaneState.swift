import Foundation

enum BrowserPaneSlot: Equatable {
    case primary
    case secondary
}

struct BrowserPaneState: Equatable {
    var primaryTabID: String
    var secondaryTabID: String?
    var focusedSlot: BrowserPaneSlot
    var primaryRatio: Double

    init(primaryTabID: String) {
        self.primaryTabID = primaryTabID
        secondaryTabID = nil
        focusedSlot = .primary
        primaryRatio = 0.5
    }

    var focusedTabID: String {
        if focusedSlot == .secondary, let secondaryTabID {
            return secondaryTabID
        }
        return primaryTabID
    }

    func isSplit(existingTabIDs: Set<String>) -> Bool {
        guard let secondaryTabID else { return false }
        return primaryTabID != secondaryTabID
            && existingTabIDs.contains(primaryTabID)
            && existingTabIDs.contains(secondaryTabID)
    }

    func contains(_ tabID: String) -> Bool {
        primaryTabID == tabID || secondaryTabID == tabID
    }

    mutating func beginSplit(primaryTabID: String, secondaryTabID: String) {
        guard primaryTabID != secondaryTabID else { return }
        self.primaryTabID = primaryTabID
        self.secondaryTabID = secondaryTabID
        focusedSlot = .secondary
    }

    mutating func select(_ tabID: String, existingTabIDs: Set<String>) {
        repair(existingTabIDs: existingTabIDs, fallbackTabID: tabID)
        guard isSplit(existingTabIDs: existingTabIDs) else {
            primaryTabID = tabID
            secondaryTabID = nil
            focusedSlot = .primary
            return
        }
        if tabID == primaryTabID {
            focusedSlot = .primary
        } else if tabID == secondaryTabID {
            focusedSlot = .secondary
        } else if focusedSlot == .secondary {
            secondaryTabID = tabID
        } else {
            primaryTabID = tabID
        }
    }

    mutating func closeSplit(focusedTabID: String) {
        primaryTabID = focusedTabID
        secondaryTabID = nil
        focusedSlot = .primary
    }

    mutating func setPrimaryRatio(_ ratio: Double) {
        primaryRatio = min(0.7, max(0.3, ratio))
    }

    mutating func repair(existingTabIDs: Set<String>, fallbackTabID: String) {
        let primaryExists = existingTabIDs.contains(primaryTabID)
        let secondaryExists = secondaryTabID.map(existingTabIDs.contains) == true
        if !primaryExists, secondaryExists, let secondaryTabID {
            primaryTabID = secondaryTabID
            self.secondaryTabID = nil
            focusedSlot = .primary
        } else if !primaryExists {
            primaryTabID = fallbackTabID
            secondaryTabID = nil
            focusedSlot = .primary
        } else if !secondaryExists {
            secondaryTabID = nil
            focusedSlot = .primary
        }
    }
}
