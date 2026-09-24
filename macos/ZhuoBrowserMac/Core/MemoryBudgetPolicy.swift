import Foundation

/// Pure policy for enforcing ultra-low memory budgets by evicting inactive tabs.
public struct MemoryBudgetPolicy {
    /// Default live webview budget for macOS desktop.
    /// Setting this to 2 ensures only the currently viewed tab and at most 1 recent tab
    /// occupy WebKit process memory. Remaining tabs are hibernated immediately.
    public static let defaultLiveBudget: Int = 2
    public static let minLiveBudget: Int = 1
    public static let maxLiveBudget: Int = 4

    public struct Plan: Equatable {
        public let tabsToKeepAlive: Set<String>
        public let tabsToHibernate: Set<String>

        public init(tabsToKeepAlive: Set<String>, tabsToHibernate: Set<String>) {
            self.tabsToKeepAlive = tabsToKeepAlive
            self.tabsToHibernate = tabsToHibernate
        }
    }

    /// Evaluates which tabs should keep their live WKWebView and which should be hibernated.
    /// - Parameters:
    ///   - tabs: All open tabs
    ///   - activeTabID: ID of the currently selected tab
    ///   - budget: Maximum number of simultaneous live WebViews
    /// - Returns: A plan containing IDs to keep alive and IDs to hibernate
    public static func evaluate(
        tabs: [BrowserTab],
        activeTabID: String?,
        budget: Int = defaultLiveBudget
    ) -> Plan {
        let clampedBudget = max(minLiveBudget, min(budget, maxLiveBudget))
        guard !tabs.isEmpty else {
            return Plan(tabsToKeepAlive: [], tabsToHibernate: [])
        }

        var keepAlive = Set<String>()

        // 1. The active tab must always stay alive
        if let activeID = activeTabID, tabs.contains(where: { $0.id == activeID }) {
            keepAlive.insert(activeID)
        } else if let firstID = tabs.first?.id {
            keepAlive.insert(firstID)
        }

        // 2. Fill remaining budget with the most recently active tabs
        let remainingBudget = clampedBudget - keepAlive.count
        if remainingBudget > 0 {
            let sortedCandidates = tabs
                .filter { !keepAlive.contains($0.id) }
                .sorted(by: { $0.lastActiveTime > $1.lastActiveTime })

            for candidate in sortedCandidates.prefix(remainingBudget) {
                keepAlive.insert(candidate.id)
            }
        }

        // 3. Any tab not in keepAlive must be hibernated
        let hibernate = Set(tabs.map(\.id).filter { !keepAlive.contains($0) })

        return Plan(tabsToKeepAlive: keepAlive, tabsToHibernate: hibernate)
    }
}
