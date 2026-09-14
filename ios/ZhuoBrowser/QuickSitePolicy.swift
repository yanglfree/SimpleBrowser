import Foundation

struct QuickSite: Identifiable, Equatable, Codable {
    var id: String
    var title: String
    var url: String
    var badge: String
    var colorIndex: Int

    static let defaults: [QuickSite] = [
        QuickSite(id: "zhihu", title: "知乎", url: "https://www.zhihu.com", badge: "知", colorIndex: 0),
        QuickSite(id: "bilibili", title: "哔哩哔哩", url: "https://www.bilibili.com", badge: "哔", colorIndex: 1),
        QuickSite(id: "sspai", title: "少数派", url: "https://sspai.com", badge: "派", colorIndex: 2),
        QuickSite(id: "weibo", title: "微博", url: "https://weibo.com", badge: "微", colorIndex: 3),
        QuickSite(id: "douban", title: "豆瓣", url: "https://www.douban.com", badge: "豆", colorIndex: 4),
        QuickSite(id: "36kr", title: "36氪", url: "https://36kr.com", badge: "氪", colorIndex: 5)
    ]
}

enum QuickSitePolicy {
    static let maximumCount = 8

    static func normalized(title: String, url: String, replacing: QuickSite? = nil, in sites: [QuickSite]) -> QuickSite? {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, URLPolicy.looksLikeURL(trimmedURL) else {
            return nil
        }
        let normalizedURL = URLPolicy.normalizeAddress(trimmedURL)
        let host = URLPolicy.rawHost(normalizedURL)
        guard !host.isEmpty,
              !sites.contains(where: { $0.id != replacing?.id && URLPolicy.rawHost($0.url) == host }) else {
            return nil
        }
        let badge = String(trimmedTitle.prefix(1)).uppercased()
        return QuickSite(
            id: replacing?.id ?? UUID().uuidString,
            title: trimmedTitle,
            url: normalizedURL,
            badge: badge,
            colorIndex: replacing?.colorIndex ?? (sites.count % 6)
        )
    }

    static func upsert(_ sites: [QuickSite], site: QuickSite) -> [QuickSite] {
        if let index = sites.firstIndex(where: { $0.id == site.id }) {
            var copy = sites
            copy[index] = site
            return copy
        }
        return Array(([site] + sites).prefix(maximumCount))
    }

    static func move(_ sites: [QuickSite], from offsets: IndexSet, to destination: Int) -> [QuickSite] {
        var copy = sites
        let moving = offsets.sorted().map { copy[$0] }
        for index in offsets.sorted(by: >) {
            copy.remove(at: index)
        }
        let removedBeforeDestination = offsets.filter { $0 < destination }.count
        copy.insert(contentsOf: moving, at: min(copy.count, destination - removedBeforeDestination))
        return copy
    }
}
