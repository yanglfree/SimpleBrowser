import Foundation

enum SessionPolicy {
    static let maxTabCount = 100
    static let liveWebViewLimit = 4

    static func persistableTabs(_ tabs: [BrowserTab]) -> [BrowserTab] {
        tabs.filter { !$0.isPrivate }
    }

    static func shouldRecordHistory(_ isPrivate: Bool) -> Bool {
        isPrivate != true
    }

    static func liveTabIDs(tabs: [BrowserTab], activeTabID: String, limit: Int) -> [String] {
        let bounded = max(1, limit)
        var ids: [String] = []
        if !activeTabID.isEmpty {
            ids.append(activeTabID)
        }
        for tab in tabs {
            if ids.count >= bounded {
                break
            }
            if !ids.contains(tab.id) {
                ids.append(tab.id)
            }
        }
        return ids
    }

    static func isTabLive(_ liveIDs: [String], _ tabID: String) -> Bool {
        liveIDs.contains(tabID)
    }
}
