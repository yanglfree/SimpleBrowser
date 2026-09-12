import CryptoKit
import Foundation
import WebKit

/// Compiles bundled EasyList JSON into `WKContentRuleList` instances.
/// Supplement and EasyList China are installed first so blocking works before
/// the large EasyList compile finishes.
final class ContentBlocker {
    static let shared = ContentBlocker()

    private let queue = DispatchQueue(label: "com.youdroid.zhuobrowser.content-blocker")
    private var lists: [WKContentRuleList] = []
    private var started = false
    var onListsChanged: (() -> Void)?

    func currentLists() -> [WKContentRuleList] {
        queue.sync { lists }
    }

    func install(on userContentController: WKUserContentController, installed: inout Set<String>) {
        for list in currentLists() {
            if installed.contains(list.identifier) {
                continue
            }
            userContentController.add(list)
            installed.insert(list.identifier)
        }
    }

    func prepare() {
        queue.async { [weak self] in
            guard let self, !self.started else {
                return
            }
            self.started = true
            for identifier in ["supplement", "easylistchina", "easylist"] {
                self.compileList(identifier)
            }
        }
    }

    private func compileList(_ identifier: String) {
        guard let url = Bundle.main.url(forResource: identifier, withExtension: "json", subdirectory: "rules")
            ?? Bundle.main.url(forResource: identifier, withExtension: "json"),
            let json = try? String(contentsOf: url, encoding: .utf8) else {
            return
        }
        let digest = SHA256.hash(data: Data(json.utf8)).prefix(8).map { String(format: "%02x", Int($0)) }.joined()
        let storeIdentifier = "zhuo.\(identifier).\(digest)"
        let store = WKContentRuleListStore.default()
        store?.lookUpContentRuleList(forIdentifier: storeIdentifier) { [weak self] existing, _ in
            if let existing {
                self?.append(existing)
                return
            }
            store?.compileContentRuleList(forIdentifier: storeIdentifier, encodedContentRuleList: json) { list, _ in
                if let list {
                    self?.append(list)
                }
            }
        }
    }

    private func append(_ list: WKContentRuleList) {
        queue.async { [weak self] in
            guard let self else {
                return
            }
            if self.lists.contains(where: { $0.identifier == list.identifier }) {
                return
            }
            self.lists.append(list)
            DispatchQueue.main.async {
                self.onListsChanged?()
            }
        }
    }
}
