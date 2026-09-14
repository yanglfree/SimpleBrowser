import Foundation

enum SessionPolicy {
    static let maxTabCount = 100
    static let recentTabLimit = 5

    static func persistableTabs(_ tabs: [BrowserTab]) -> [BrowserTab] {
        tabs.filter { !$0.isPrivate }
    }

    static func shouldRecordHistory(_ isPrivate: Bool) -> Bool {
        isPrivate != true
    }

    static func recentTabs(
        _ tabs: [BrowserTab],
        activeTabID: String,
        limit: Int = recentTabLimit
    ) -> [BrowserTab] {
        guard limit > 0, let active = tabs.first(where: { $0.id == activeTabID }) else {
            return []
        }
        return Array(
            tabs
                .filter { $0.isPrivate == active.isPrivate }
                .sorted { left, right in
                    if left.id == active.id { return right.id != active.id }
                    if right.id == active.id { return false }
                    if left.lastVisitedAt == right.lastVisitedAt { return left.id < right.id }
                    return left.lastVisitedAt > right.lastVisitedAt
                }
                .prefix(limit)
        )
    }

    static func liveTabIDs(
        tabs: [BrowserTab],
        activeTabID: String,
        limit: Int,
        requiredTabIDs: [String] = []
    ) -> [String] {
        let available = Set(tabs.filter { !URLPolicy.isHomeURL($0.url) }.map(\.id))
        var ids = requiredTabIDs.filter(available.contains)
        ids = ids.reduce(into: []) { result, id in
            if !result.contains(id) { result.append(id) }
        }
        let bounded = max(1, max(limit, ids.count))
        if let active = tabs.first(where: { $0.id == activeTabID }), !URLPolicy.isHomeURL(active.url) {
            if !ids.contains(activeTabID) { ids.append(activeTabID) }
        }
        for tab in tabs.sorted(by: { $0.lastVisitedAt > $1.lastVisitedAt }) {
            if ids.count >= bounded {
                break
            }
            if !URLPolicy.isHomeURL(tab.url), !ids.contains(tab.id) {
                ids.append(tab.id)
            }
        }
        return ids
    }

    static func partitionExpiredTabs(
        _ tabs: [BrowserTab],
        expiry: TabExpiry,
        now: TimeInterval = Date().timeIntervalSince1970
    ) -> (active: [BrowserTab], expired: [BrowserTab]) {
        guard expiry != .never else {
            return (tabs, [])
        }
        let cutoff = now - TimeInterval(expiry.rawValue * 24 * 60 * 60)
        return (
            tabs.filter { $0.lastVisitedAt >= cutoff },
            tabs.filter { $0.lastVisitedAt < cutoff }
        )
    }

    static func softLimitCleanupCandidates(
        tabs: [BrowserTab],
        activeTabID: String,
        limit: Int
    ) -> [String] {
        let targetCount = max(1, BrowserSettings.clampedTabSoftLimit(limit) - 1)
        let removeCount = max(0, tabs.count - targetCount)
        guard removeCount > 0 else {
            return []
        }
        let candidates = tabs.filter { $0.id != activeTabID }
        let stale = candidates
            .filter { URLPolicy.isHomeURL($0.url) || $0.isLoading }
            .sorted { $0.lastVisitedAt < $1.lastVisitedAt }
        let staleIDs = Set(stale.map(\.id))
        let remaining = candidates
            .filter { !staleIDs.contains($0.id) }
            .sorted { $0.lastVisitedAt < $1.lastVisitedAt }
        return Array((stale + remaining).prefix(removeCount).map(\.id))
    }

    static func selectedTabAfterClosing(_ tabs: [BrowserTab], closing id: String) -> String? {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        let remaining = tabs.filter { $0.id != id }
        guard !remaining.isEmpty else {
            return nil
        }
        return remaining[min(index, remaining.count - 1)].id
    }

    static func otherTabIDs(in tabs: [BrowserTab], keeping id: String) -> [String] {
        guard let target = tabs.first(where: { $0.id == id }) else {
            return []
        }
        return tabs
            .filter { $0.id != id && $0.isPrivate == target.isPrivate }
            .map(\.id)
    }

    static func adjacentTabID(_ tabs: [BrowserTab], activeTabID: String, direction: Int) -> String? {
        guard tabs.count > 1,
              direction != 0,
              let index = tabs.firstIndex(where: { $0.id == activeTabID }) else {
            return nil
        }
        let offset = direction < 0 ? -1 : 1
        return tabs[(index + offset + tabs.count) % tabs.count].id
    }

    static func canReorderTab(_ tabs: [BrowserTab], id: String, direction: Int) -> Bool {
        guard direction != 0,
              let index = tabs.firstIndex(where: { $0.id == id }) else {
            return false
        }
        let targetIndex = index + (direction < 0 ? -1 : 1)
        guard tabs.indices.contains(targetIndex) else {
            return false
        }
        return sharesGroup(tabs[index], tabs[targetIndex])
    }

    static func reorderedTabs(_ tabs: [BrowserTab], moving id: String, direction: Int) -> [BrowserTab]? {
        guard canReorderTab(tabs, id: id, direction: direction),
              let index = tabs.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        return reorderedTabs(tabs, moving: id, targetIndex: index + (direction < 0 ? -1 : 1))
    }

    static func reorderedTabs(_ tabs: [BrowserTab], moving id: String, targetID: String) -> [BrowserTab]? {
        guard let targetIndex = tabs.firstIndex(where: { $0.id == targetID }) else {
            return nil
        }
        return reorderedTabs(tabs, moving: id, targetIndex: targetIndex)
    }

    private static func reorderedTabs(_ tabs: [BrowserTab], moving id: String, targetIndex: Int) -> [BrowserTab]? {
        guard let index = tabs.firstIndex(where: { $0.id == id }),
              index != targetIndex else {
            return nil
        }
        let moving = tabs[index]
        var first = index
        while first > 0, sharesGroup(tabs[first - 1], moving) {
            first -= 1
        }
        var last = index
        while last < tabs.count - 1, sharesGroup(tabs[last + 1], moving) {
            last += 1
        }
        let clamped = min(max(targetIndex, first), last)
        guard clamped != index else {
            return nil
        }
        var reordered = tabs
        let tab = reordered.remove(at: index)
        reordered.insert(tab, at: min(clamped, reordered.count))
        return reordered
    }

    private static func sharesGroup(_ left: BrowserTab, _ right: BrowserTab) -> Bool {
        left.isPrivate == right.isPrivate && left.isPinned == right.isPinned
    }

    static func isTabLive(_ liveIDs: [String], _ tabID: String) -> Bool {
        liveIDs.contains(tabID)
    }
}
