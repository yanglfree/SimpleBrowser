import Foundation

/// Pure policy that decides which tabs keep a live `WKWebView`.
///
/// **Default behaviour is "every tab stays resident".** Tab switching, scroll
/// position, form input and page JS state are treated as baseline functionality, so
/// nothing is frozen just because a tab is in the background. Freezing only happens
/// when the user explicitly opts into the memory-saver mode, or when macOS reports a
/// *critical* memory condition (an emergency valve, never a routine event).
public struct MemoryBudgetPolicy {
    /// Only used when the opt-in memory-saver mode is enabled; the default mode keeps
    /// every tab resident and ignores this value.
    public static let defaultLiveBudget: Int = 4
    public static let minLiveBudget: Int = 1
    public static let maxLiveBudget: Int = 8

    /// Live budget used under memory pressure, before clamping.
    public static let warningBudget: Int = 3
    public static let criticalBudget: Int = 1

    public struct Plan: Equatable {
        public let tabsToKeepAlive: Set<String>
        public let tabsToHibernate: Set<String>
        public let effectiveBudget: Int

        public init(tabsToKeepAlive: Set<String>, tabsToHibernate: Set<String>, effectiveBudget: Int = defaultLiveBudget) {
            self.tabsToKeepAlive = tabsToKeepAlive
            self.tabsToHibernate = tabsToHibernate
            self.effectiveBudget = effectiveBudget
        }
    }

    /// Clamps the user preference and derates it while the system is under pressure.
    public static func effectiveBudget(
        requested: Int,
        pressure: MemoryPressureLevel = .nominal
    ) -> Int {
        let clamped = max(minLiveBudget, min(requested, maxLiveBudget))
        switch pressure {
        case .nominal:
            return clamped
        case .warning:
            return max(minLiveBudget, min(clamped, warningBudget))
        case .critical:
            return criticalBudget
        }
    }

    /// Evaluates which tabs keep a live WebView and which get frozen.
    /// - Parameters:
    ///   - tabs: All open tabs
    ///   - activeTabID: ID of the currently selected tab
    ///   - budget: Maximum number of simultaneous live WebViews (opt-in mode only)
    ///   - pressure: Current system memory pressure
    ///   - hibernationEnabled: user opt-in for the memory-saver mode. When `false`,
    ///     nothing is frozen unless the process is under critical memory pressure.
    public static func evaluate(
        tabs: [BrowserTab],
        activeTabID: String?,
        budget: Int = defaultLiveBudget,
        pressure: MemoryPressureLevel = .nominal,
        hibernationEnabled: Bool = true
    ) -> Plan {
        guard !tabs.isEmpty else {
            return Plan(tabsToKeepAlive: [], tabsToHibernate: [], effectiveBudget: budget)
        }

        var keepAlive = Set<String>()
        var activeIsLive = false

        // 1. The active tab must always stay alive.
        if let activeID = activeTabID, let activeTab = tabs.first(where: { $0.id == activeID }) {
            keepAlive.insert(activeID)
            activeIsLive = !activeTab.isHome
        } else if let firstTab = tabs.first {
            keepAlive.insert(firstTab.id)
            activeIsLive = !firstTab.isHome
        }

        let webTabs = tabs.filter { !$0.isHome }

        // 2. Resident mode: keep every page alive so switching is free.
        //    Only a critical system-wide memory condition overrides this.
        if !hibernationEnabled && pressure < .critical {
            for tab in webTabs {
                keepAlive.insert(tab.id)
            }
            return Plan(
                tabsToKeepAlive: keepAlive,
                tabsToHibernate: [],
                effectiveBudget: max(keepAlive.count, webTabs.count)
            )
        }

        let effective = effectiveBudget(
            requested: hibernationEnabled ? budget : criticalBudget,
            pressure: pressure
        )

        // 3. Fill the remaining slots with the most recently used *web* tabs.
        //    Home tabs have no WebView, so reserving slots for them would silently
        //    shrink the real live pool.
        var remaining = effective - (activeIsLive ? 1 : 0)
        if remaining > 0 {
            let candidates = webTabs
                .filter { !keepAlive.contains($0.id) }
                .sorted { $0.lastActiveTime > $1.lastActiveTime }

            for candidate in candidates where remaining > 0 {
                keepAlive.insert(candidate.id)
                remaining -= 1
            }
        }

        // 4. Anything outside the pool is frozen rather than reloaded later.
        let hibernate = Set(webTabs.map(\.id).filter { !keepAlive.contains($0) })

        return Plan(tabsToKeepAlive: keepAlive, tabsToHibernate: hibernate, effectiveBudget: effective)
    }
}
