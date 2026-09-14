import Foundation

enum SessionPolicy {
    static let maxTabCount = 100

    static func persistableTabs(_ tabs: [BrowserTab]) -> [BrowserTab] {
        tabs.filter { !$0.isPrivate }
    }

    static func shouldRecordHistory(_ isPrivate: Bool) -> Bool {
        isPrivate != true
    }

    static func liveTabIDs(tabs: [BrowserTab], activeTabID: String, limit: Int) -> [String] {
        let bounded = max(1, limit)
        var ids: [String] = []
        if let active = tabs.first(where: { $0.id == activeTabID }), !URLPolicy.isHomeURL(active.url) {
            ids.append(activeTabID)
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

    static func isTabLive(_ liveIDs: [String], _ tabID: String) -> Bool {
        liveIDs.contains(tabID)
    }
}
