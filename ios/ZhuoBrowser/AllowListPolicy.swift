import Foundation

enum AllowListPolicy {
    static func isHostAllowed(_ hosts: [String], _ host: String) -> Bool {
        !host.isEmpty && hosts.contains(host)
    }

    static func setHostAllowed(_ hosts: [String], host: String, allowed: Bool) -> [String] {
        if host.isEmpty {
            return hosts
        }
        let without = hosts.filter { $0 != host }
        return allowed ? without + [host] : without
    }

    static func adsBlockEnabled(for url: String, hosts: [String], blockAds: Bool) -> Bool {
        if !blockAds || URLPolicy.isHomeURL(url) {
            return false
        }
        return !isHostAllowed(hosts, URLPolicy.rawHost(url))
    }
}
