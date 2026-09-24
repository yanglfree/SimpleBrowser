import Foundation
import WebKit

/// Manages native declarative content blocking rules (WKContentRuleList) for ZhuoBrowser Mac.
/// Compiles EasyList JSON rules into native WebKit binary bytecode caches with 0 JavaScript execution cost.
public final class ContentBlocker: @unchecked Sendable {
    public static let shared = ContentBlocker()

    private let queue = DispatchQueue(label: "com.youdroid.zhuobrowser.mac.content-blocker")
    private var compiledLists: [WKContentRuleList] = []
    private var isCompiling = false
    private var hasCompiled = false

    public func currentLists() -> [WKContentRuleList] {
        queue.sync { compiledLists }
    }

    public func install(on userContentController: WKUserContentController) {
        let lists = currentLists()
        for list in lists {
            userContentController.add(list)
        }
    }

    public func prepare(completion: (() -> Void)? = nil) {
        dispatchPrecondition(condition: .onQueue(.main))
        if hasCompiled {
            completion?()
            return
        }
        guard !isCompiling else { return }
        isCompiling = true

        let ruleNames = ["supplement", "easylistchina"]
        let group = DispatchGroup()
        var results: [WKContentRuleList] = []
        let resultsLock = NSLock()

        guard let store = WKContentRuleListStore.default() else {
            isCompiling = false
            completion?()
            return
        }

        for name in ruleNames {
            group.enter()
            store.lookUpContentRuleList(forIdentifier: name) { list, error in
                if let list = list {
                    resultsLock.lock()
                    results.append(list)
                    resultsLock.unlock()
                    group.leave()
                } else if let jsonString = self.loadRuleJSON(named: name) {
                    store.compileContentRuleList(forIdentifier: name, encodedContentRuleList: jsonString) { compiled, compileError in
                        if let compiled = compiled {
                            resultsLock.lock()
                            results.append(compiled)
                            resultsLock.unlock()
                        }
                        group.leave()
                    }
                } else {
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            self.queue.sync {
                self.compiledLists = results
            }
            self.hasCompiled = true
            self.isCompiling = false
            completion?()
        }
    }

    private func loadRuleJSON(named name: String) -> String? {
        let bundle = Bundle.main
        var fileURL = bundle.url(forResource: name, withExtension: "json", subdirectory: "rules")
        if fileURL == nil {
            fileURL = bundle.url(forResource: name, withExtension: "json")
        }
        guard let url = fileURL, let data = try? Data(contentsOf: url),
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }
}
