import CryptoKit
import Foundation
import WebKit

/// Compiles bundled EasyList JSON into one atomic `WKContentRuleList` batch.
final class ContentBlocker: @unchecked Sendable {
    static let shared = ContentBlocker()
    static let listsDidChangeNotification = Notification.Name("com.youdroid.zhuobrowser.content-lists-changed")

    private let queue = DispatchQueue(label: "com.youdroid.zhuobrowser.content-blocker")
    private var lists: [WKContentRuleList] = []
    private var prepareCompletions: [(Bool, Bool) -> Void] = []
    private var isPreparing = false
    private var isPrepared = false
    private var preparedWithCachedRules = false
    private var remoteUpdateCompletions: [(Bool, Date?) -> Void] = []
    private var isRemoteUpdating = false

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

    func prepare(completion: ((Bool, Bool) -> Void)? = nil) {
        queue.async { [weak self] in
            guard let self else { return }
            if self.isPrepared {
                if let completion {
                    let usedCachedRules = self.preparedWithCachedRules
                    DispatchQueue.main.async { completion(true, usedCachedRules) }
                }
                return
            }
            if let completion { self.prepareCompletions.append(completion) }
            guard !self.isPreparing else { return }
            self.isPreparing = true
            if let snapshot = RemoteRuleStore.cachedSnapshot(),
               let supplement = self.bundledJSON(identifier: "supplement") {
                let artifacts = snapshot.artifacts + [
                    RemoteRuleArtifact(identifier: "supplement", json: supplement, count: 0, truncated: false)
                ]
                self.compileArtifacts(artifacts) { ready in
                    if ready.count == artifacts.count {
                        self.lists = ready
                        self.postListsChanged()
                        self.finishPrepare(success: true, usedCachedRules: true)
                    } else {
                        self.compileBundledForPrepare()
                    }
                }
            } else {
                self.compileBundledForPrepare()
            }
        }
    }

    private func compileBundledForPrepare() {
        let artifacts = ["supplement", "easylistchina", "easylist"].compactMap { identifier -> RemoteRuleArtifact? in
            guard let json = bundledJSON(identifier: identifier) else { return nil }
            return RemoteRuleArtifact(identifier: identifier, json: json, count: 0, truncated: false)
        }
        compileArtifacts(artifacts) { ready in
            let success = ready.count == 3
            if success {
                self.lists = ready
                self.postListsChanged()
            }
            self.finishPrepare(success: success, usedCachedRules: false)
        }
    }

    private func finishPrepare(success: Bool, usedCachedRules: Bool) {
        isPreparing = false
        isPrepared = success
        preparedWithCachedRules = success && usedCachedRules
        let completions = prepareCompletions
        prepareCompletions = []
        DispatchQueue.main.async {
            completions.forEach { $0(success, usedCachedRules) }
        }
    }

    func updateRemoteRules(
        allowsExpensiveNetworkAccess: Bool,
        completion: @escaping (Bool, Date?) -> Void
    ) {
        queue.async { [weak self] in
            guard let self else { return }
            if self.isPreparing {
                self.prepareCompletions.append { [weak self] _, _ in
                    self?.updateRemoteRules(
                        allowsExpensiveNetworkAccess: allowsExpensiveNetworkAccess,
                        completion: completion
                    )
                }
                return
            }
            self.remoteUpdateCompletions.append(completion)
            guard !self.isRemoteUpdating else { return }
            self.isRemoteUpdating = true
            Task {
                do {
                    let snapshot = try await RemoteRuleStore.fetchSnapshot(
                        allowsExpensiveNetworkAccess: allowsExpensiveNetworkAccess
                    )
                    self.queue.async {
                        guard let supplement = self.bundledJSON(identifier: "supplement") else {
                            self.finishRemoteUpdate(success: false, updatedAt: nil)
                            return
                        }
                        let artifacts = snapshot.artifacts + [
                            RemoteRuleArtifact(identifier: "supplement", json: supplement, count: 0, truncated: false)
                        ]
                        self.compileArtifacts(artifacts) { compiled in
                            guard compiled.count == artifacts.count else {
                                self.finishRemoteUpdate(success: false, updatedAt: nil)
                                return
                            }
                            do {
                                try RemoteRuleStore.persist(snapshot)
                                self.lists = compiled
                                self.isPrepared = true
                                self.preparedWithCachedRules = true
                                self.postListsChanged()
                                self.finishRemoteUpdate(success: true, updatedAt: snapshot.updatedAt)
                            } catch {
                                self.finishRemoteUpdate(success: false, updatedAt: nil)
                            }
                        }
                    }
                } catch {
                    self.queue.async {
                        self.finishRemoteUpdate(success: false, updatedAt: nil)
                    }
                }
            }
        }
    }

    private func bundledJSON(identifier: String) -> String? {
        guard let url = Bundle.main.url(forResource: identifier, withExtension: "json", subdirectory: "rules")
            ?? Bundle.main.url(forResource: identifier, withExtension: "json"),
            let json = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        return json
    }

    private func compileArtifacts(
        _ artifacts: [RemoteRuleArtifact],
        completion: @escaping ([WKContentRuleList]) -> Void
    ) {
        let group = DispatchGroup()
        let compiled = CompiledRuleLists()
        for artifact in artifacts {
            group.enter()
            compile(artifact) { list in
                if let list { compiled.append(list) }
                group.leave()
            }
        }
        group.notify(queue: queue) { completion(compiled.snapshot()) }
    }

    private func compile(_ artifact: RemoteRuleArtifact, completion: @escaping (WKContentRuleList?) -> Void) {
        let json = artifact.json
        let digest = SHA256.hash(data: Data(json.utf8)).prefix(8).map { String(format: "%02x", Int($0)) }.joined()
        let storeIdentifier = "zhuo.\(artifact.identifier).\(digest)"
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

    private func finishRemoteUpdate(success: Bool, updatedAt: Date?) {
        isRemoteUpdating = false
        let completions = remoteUpdateCompletions
        remoteUpdateCompletions = []
        DispatchQueue.main.async {
            completions.forEach { $0(success, updatedAt) }
        }
    }

    private func postListsChanged() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.listsDidChangeNotification, object: self)
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
