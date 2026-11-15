import XCTest
@testable import ZhuoBrowser

final class WebPromptModelsTests: XCTestCase {
    func testHostTitleExtractsHostOrFallsBack() {
        XCTAssertEqual(WebPromptPolicy.hostTitle(for: "https://sub.example.com/path"), "sub.example.com")
        XCTAssertEqual(WebPromptPolicy.hostTitle(for: "about:blank"), "当前网页")
        XCTAssertEqual(WebPromptPolicy.hostTitle(for: ""), "当前网页")
    }

    func testAlertInvokesCompletionOnce() {
        var count = 0
        let dialog = PendingJsDialog(tabID: "t1", titleHost: "example.com", message: "hello") {
            count += 1
        }
        dialog.completeAlert()
        dialog.completeAlert()
        dialog.cancel()
        XCTAssertEqual(count, 1)
        XCTAssertTrue(dialog.isResolved)
    }

    func testConfirmCancelsOnDeinitIfUnresolved() {
        var received: [Bool] = []
        do {
            let dialog = PendingJsDialog(tabID: "t1", titleHost: "example.com", message: "confirm?") { ok in
                received.append(ok)
            }
            XCTAssertFalse(dialog.isResolved)
        }
        XCTAssertEqual(received, [false])
    }

    func testPromptSubmitsTextAndIgnoresDuplicateResolution() {
        var results: [String?] = []
        let dialog = PendingJsDialog(
            tabID: "t1",
            titleHost: "example.com",
            message: "name?",
            defaultText: "guest"
        ) { value in
            results.append(value)
        }
        dialog.completePrompt("alice")
        dialog.cancel()
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first ?? nil, "alice")
    }

    func testHttpAuthSubmitsOnceAndCancelsOnDeinit() {
        var dispositions: [URLSession.AuthChallengeDisposition] = []
        var users: [String?] = []
        do {
            let auth = PendingHttpAuth(
                tabID: "t1",
                host: "example.com",
                realm: "Intranet",
                isRetry: true
            ) { disposition, credential in
                dispositions.append(disposition)
                users.append(credential?.user)
            }
            auth.submit(username: "u1", password: "secret")
            auth.cancel()
        }
        XCTAssertEqual(dispositions, [.useCredential])
        XCTAssertEqual(users, ["u1"])

        var canceledDispositions: [URLSession.AuthChallengeDisposition] = []
        do {
            let dropped = PendingHttpAuth(
                tabID: "t1",
                host: "example.com",
                realm: "",
                isRetry: false
            ) { disposition, _ in
                canceledDispositions.append(disposition)
            }
            XCTAssertFalse(dropped.isResolved)
        }
        XCTAssertEqual(canceledDispositions, [.cancelAuthenticationChallenge])
    }
}
