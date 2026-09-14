import Foundation

struct BrowserWindowRequest: Codable, Hashable, Identifiable {
    let id: String
    let sourceSessionID: String
    let sourceTabID: String
    let tabData: Data

    init?(sourceSessionID: String, tab: BrowserTab) {
        guard let tabData = try? JSONEncoder().encode(tab) else { return nil }
        id = UUID().uuidString
        self.sourceSessionID = sourceSessionID
        sourceTabID = tab.id
        self.tabData = tabData
    }

    var tab: BrowserTab? {
        try? JSONDecoder().decode(BrowserTab.self, from: tabData)
    }
}

extension Notification.Name {
    static let browserWindowDidOpen = Notification.Name("com.youdroid.zhuobrowser.window-did-open")
}

enum BrowserWindowTransfer {
    static func acknowledge(_ request: BrowserWindowRequest) {
        NotificationCenter.default.post(
            name: .browserWindowDidOpen,
            object: nil,
            userInfo: [
                "requestID": request.id,
                "sourceSessionID": request.sourceSessionID,
                "sourceTabID": request.sourceTabID
            ]
        )
    }
}
