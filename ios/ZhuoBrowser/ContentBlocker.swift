import CryptoKit
import Foundation
import WebKit

/// Compiles bundled EasyList JSON into one atomic `WKContentRuleList` batch.
final class ContentBlocker {
    static let shared = ContentBlocker()

    private let queue = DispatchQueue(label: "com.youdroid.zhuobrowser.content-blocker")
    private var lists: [WKContentRuleList] = []
    private var reloadCompletions: [(Bool) -> Void] = []
    private var isReloading = false
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
        reloadBundledRules(completion: nil)
    }

    /// Reloads the immutable rules bundled with the app. Concurrent callers join
    /// the same work so the UI cannot start competing WebKit compiles.
    func reloadBundledRules(completion: ((Bool) -> Void)?) {
        queue.async { [weak self] in
            guard let self else { return }
            if let completion {
                self.reloadCompletions.append(completion)
            }
            if self.isReloading {
                return
            }
            self.isReloading = true
            let identifiers = ["supplement", "easylistchina", "easylist"]
            let group = DispatchGroup()
            let compiled = CompiledRuleLists()
            for identifier in identifiers {
                group.enter()
                self.compileList(identifier) { list in
                    if let list {
                        compiled.append(list)
                    }
                    group.leave()
                }
            }
            group.notify(queue: self.queue) {
                let ready = compiled.snapshot()
                let success = ready.count == identifiers.count
                if success {
                    self.lists = ready
                }
                self.isReloading = false
                let completions = self.reloadCompletions
                self.reloadCompletions = []
                DispatchQueue.main.async {
                    if success {
                        self.onListsChanged?()
                    }
                    completions.forEach { $0(success) }
                }
            }
        }
    }

    private func compileList(_ identifier: String, completion: @escaping (WKContentRuleList?) -> Void) {
        guard let url = Bundle.main.url(forResource: identifier, withExtension: "json", subdirectory: "rules")
            ?? Bundle.main.url(forResource: identifier, withExtension: "json"),
            let json = try? String(contentsOf: url, encoding: .utf8) else {
            completion(nil)
            return
        }
        let digest = SHA256.hash(data: Data(json.utf8)).prefix(8).map { String(format: "%02x", Int($0)) }.joined()
        let storeIdentifier = "zhuo.\(identifier).\(digest)"
        let store = WKContentRuleListStore.default()
        store?.lookUpContentRuleList(forIdentifier: storeIdentifier) { existing, _ in
            if let existing {
                completion(existing)
                return
            }
            store?.compileContentRuleList(forIdentifier: storeIdentifier, encodedContentRuleList: json) { list, _ in
                completion(list)
            }
        }
        if store == nil {
            completion(nil)
        }
    }
}

private final class CompiledRuleLists {
    private let lock = NSLock()
    private var lists: [WKContentRuleList] = []

    func append(_ list: WKContentRuleList) {
        lock.lock()
        lists.append(list)
        lock.unlock()
    }

    func snapshot() -> [WKContentRuleList] {
        lock.lock()
        defer { lock.unlock() }
        return lists
    }
}
