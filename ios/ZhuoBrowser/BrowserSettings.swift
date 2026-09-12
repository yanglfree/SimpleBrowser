import Foundation

struct BrowserSettings: Codable, Equatable {
    var searchEngine: SearchEngine = .bing
    var blockAds: Bool = true

    var searchEngineLabel: String {
        switch searchEngine {
        case .bing: return "Bing"
        case .baidu: return "百度"
        case .google: return "Google"
        case .duckDuckGo: return "DuckDuckGo"
        }
    }
}

extension SearchEngine: CaseIterable, Identifiable {
    var id: Int { rawValue }

    static var allCases: [SearchEngine] {
        [.bing, .baidu, .google, .duckDuckGo]
    }

    var label: String {
        BrowserSettings(searchEngine: self).searchEngineLabel
    }
}
