import Foundation

enum JsDialogKind: Equatable {
    case alert
    case confirm
    case prompt
}

enum WebPromptPolicy {
    static func hostTitle(for urlString: String) -> String {
        let rawHost = URLPolicy.rawHost(urlString)
        guard !rawHost.isEmpty else {
            return "当前网页"
        }
        let host = URLPolicy.displayHost(urlString)
        return host.isEmpty ? rawHost : host
    }
}

final class PendingJsDialog: Identifiable {
    let id = UUID()
    let tabID: String
    let kind: JsDialogKind
    let titleHost: String
    let message: String
    let defaultText: String

    private var alertHandler: (() -> Void)?
    private var confirmHandler: ((Bool) -> Void)?
    private var promptHandler: ((String?) -> Void)?
    private var resolved = false

    init(tabID: String, titleHost: String, message: String, completion: @escaping () -> Void) {
        self.tabID = tabID
        self.kind = .alert
        self.titleHost = titleHost
        self.message = message
        self.defaultText = ""
        self.alertHandler = completion
    }

    init(tabID: String, titleHost: String, message: String, confirmCompletion: @escaping (Bool) -> Void) {
        self.tabID = tabID
        self.kind = .confirm
        self.titleHost = titleHost
        self.message = message
        self.defaultText = ""
        self.confirmHandler = confirmCompletion
    }

    init(
        tabID: String,
        titleHost: String,
        message: String,
        defaultText: String,
        promptCompletion: @escaping (String?) -> Void
    ) {
        self.tabID = tabID
        self.kind = .prompt
        self.titleHost = titleHost
        self.message = message
        self.defaultText = defaultText
        self.promptHandler = promptCompletion
    }

    deinit {
        cancel()
    }

    var isResolved: Bool {
        resolved
    }

    func completeAlert() {
        guard !resolved else { return }
        resolved = true
        let handler = alertHandler
        clearHandlers()
        handler?()
    }

    func completeConfirm(_ confirmed: Bool) {
        guard !resolved else { return }
        resolved = true
        let handler = confirmHandler
        clearHandlers()
        handler?(confirmed)
    }

    func completePrompt(_ value: String?) {
        guard !resolved else { return }
        resolved = true
        let handler = promptHandler
        clearHandlers()
        handler?(value)
    }

    func cancel() {
        guard !resolved else { return }
        resolved = true
        let alert = alertHandler
        let confirm = confirmHandler
        let prompt = promptHandler
        clearHandlers()
        alert?()
        confirm?(false)
        prompt?(nil)
    }

    private func clearHandlers() {
        alertHandler = nil
        confirmHandler = nil
        promptHandler = nil
    }
}

final class PendingHttpAuth: Identifiable {
    typealias Completion = (URLSession.AuthChallengeDisposition, URLCredential?) -> Void

    let id = UUID()
    let tabID: String
    let host: String
    let realm: String
    let isRetry: Bool

    private var completion: Completion?
    private var resolved = false

    init(
        tabID: String,
        host: String,
        realm: String,
        isRetry: Bool,
        completion: @escaping Completion
    ) {
        self.tabID = tabID
        self.host = host
        self.realm = realm
        self.isRetry = isRetry
        self.completion = completion
    }

    deinit {
        cancel()
    }

    var isResolved: Bool {
        resolved
    }

    func submit(username: String, password: String) {
        guard !resolved else { return }
        resolved = true
        let handler = completion
        completion = nil
        let credential = URLCredential(user: username, password: password, persistence: .forSession)
        handler?(.useCredential, credential)
    }

    func cancel() {
        guard !resolved else { return }
        resolved = true
        let handler = completion
        completion = nil
        handler?(.cancelAuthenticationChallenge, nil)
    }
}
