import Foundation

struct BrowserSettings: Equatable {
    var searchEngine: SearchEngine = .bing
    var blockAds: Bool = true
    var searchSuggestionsEnabled: Bool = true

    var searchEngineLabel: String {
        switch searchEngine {
        case .bing: return "Bing"
        case .baidu: return "百度"
        case .google: return "Google"
        case .duckDuckGo: return "DuckDuckGo"
        }
    }

    enum CodingKeys: String, CodingKey {
        case searchEngine, blockAds, searchSuggestionsEnabled
    }

    init(searchEngine: SearchEngine = .bing, blockAds: Bool = true, searchSuggestionsEnabled: Bool = true) {
        self.searchEngine = searchEngine
        self.blockAds = blockAds
        self.searchSuggestionsEnabled = searchSuggestionsEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        searchEngine = try container.decodeIfPresent(SearchEngine.self, forKey: .searchEngine) ?? .bing
        blockAds = try container.decodeIfPresent(Bool.self, forKey: .blockAds) ?? true
        searchSuggestionsEnabled = try container.decodeIfPresent(Bool.self, forKey: .searchSuggestionsEnabled) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(searchEngine, forKey: .searchEngine)
        try container.encode(blockAds, forKey: .blockAds)
        try container.encode(searchSuggestionsEnabled, forKey: .searchSuggestionsEnabled)
    }
}

extension BrowserSettings: Codable {}

extension SearchEngine: CaseIterable, Identifiable {
    var id: Int { rawValue }

    static var allCases: [SearchEngine] {
        [.bing, .baidu, .google, .duckDuckGo]
    }

    var label: String {
        BrowserSettings(searchEngine: self).searchEngineLabel
    }
}
