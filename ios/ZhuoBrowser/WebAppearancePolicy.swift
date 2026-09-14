import Foundation

enum WebAppearancePolicy {
    static let supportedZoomPercents = [75, 90, 100, 110, 125, 150]

    static func host(for rawURL: String) -> String {
        guard let host = URLComponents(string: rawURL)?.host?.lowercased() else {
            return ""
        }
        return host
    }

    static func userAgentPreference(for rawURL: String, settings: BrowserSettings) -> UserAgentPreference {
        let targetHost = host(for: rawURL)
        return settings.siteUserAgentPreferences.first(where: { $0.host == targetHost })?.preference
            ?? settings.defaultUserAgentPreference
    }

    static func usesDesktopUserAgent(for rawURL: String, settings: BrowserSettings) -> Bool {
        userAgentPreference(for: rawURL, settings: settings) == .desktop
    }

    static func zoomPercent(for rawURL: String, settings: BrowserSettings) -> Int {
        let targetHost = host(for: rawURL)
        return settings.siteZoomRatios.first(where: { $0.host == targetHost })?.percent ?? 100
    }

    static func isDarkModeExcluded(for rawURL: String, settings: BrowserSettings) -> Bool {
        settings.webDarkModeExcludedHosts.contains(host(for: rawURL))
    }

    static func clampedZoomPercent(_ value: Int) -> Int {
        supportedZoomPercents.min(by: { abs($0 - value) < abs($1 - value) }) ?? 100
    }

    static func normalizedHosts(_ hosts: [String]) -> [String] {
        Array(Set(hosts.map { $0.lowercased() }.filter { !$0.isEmpty })).sorted()
    }

    static func normalizedUserAgentPreferences(
        _ preferences: [SiteUserAgentPreference]
    ) -> [SiteUserAgentPreference] {
        var byHost: [String: UserAgentPreference] = [:]
        preferences.forEach { entry in
            let normalizedHost = entry.host.lowercased()
            if !normalizedHost.isEmpty, entry.preference != .default {
                byHost[normalizedHost] = entry.preference
            }
        }
        return byHost.keys.sorted().compactMap { host in
            byHost[host].map { SiteUserAgentPreference(host: host, preference: $0) }
        }
    }

    static func normalizedZoomRatios(_ ratios: [SiteZoomRatio]) -> [SiteZoomRatio] {
        var byHost: [String: Int] = [:]
        ratios.forEach { entry in
            let normalizedHost = entry.host.lowercased()
            if !normalizedHost.isEmpty {
                let percent = clampedZoomPercent(entry.percent)
                if percent != 100 {
                    byHost[normalizedHost] = percent
                }
            }
        }
        return byHost.keys.sorted().compactMap { host in
            byHost[host].map { SiteZoomRatio(host: host, percent: $0) }
        }
    }
}
