import XCTest
import SwiftUI
import WebKit
@testable import ZhuoBrowserMac

final class AutoFillTests: XCTestCase {

    func testAutoFillAgentScriptExistsAndValid() {
        guard let source = InjectedScripts.shared.scriptContent(named: "autofill-agent") else {
            XCTFail("autofill-agent.js must exist and be loadable by InjectedScripts")
            return
        }

        XCTAssertTrue(source.contains("__zhuoAutoFillInjected"))
        XCTAssertTrue(source.contains("zhuoAutoFill"))
        XCTAssertTrue(source.contains("isLoginCandidate"))
        XCTAssertTrue(source.contains("isPasswordInput"))
        XCTAssertTrue(source.contains("isUsernameInput"))
        XCTAssertTrue(source.contains("window.__zhuoAutoFill"))
        XCTAssertTrue(source.contains("fill:"))
        XCTAssertTrue(source.contains("isTopFrame"))

        // Regression: the agent must not fabricate passkey logins, auto-submit the form, or
        // forward the saved secret into iframes.
        XCTAssertFalse(source.contains("triggerPasskey"))
        XCTAssertFalse(source.contains("zhuo-autofill-broadcast-fill"))
        XCTAssertFalse(source.contains("shouldContinue"))
        XCTAssertFalse(source.contains("attemptContinue"))
    }

    func testInjectedScriptsMakeAutoFillScript() {
        let script = InjectedScripts.shared.makeAutoFillScript()
        XCTAssertNotNil(script)
        XCTAssertEqual(script?.injectionTime, .atDocumentEnd)
        XCTAssertFalse(script?.isForMainFrameOnly ?? true)
    }

    func testSavedCredentialRootDomainExtraction() {
        XCTAssertEqual(SavedCredential.extractRootDomain(from: "id1.cloud.huawei.com"), "huawei.com")
        XCTAssertEqual(SavedCredential.extractRootDomain(from: "appleid.apple.com"), "apple.com")
        XCTAssertEqual(SavedCredential.extractRootDomain(from: "github.com"), "github.com")
        XCTAssertEqual(SavedCredential.extractRootDomain(from: "sub.example.co.uk"), "example.co.uk")
        XCTAssertEqual(SavedCredential.extractRootDomain(from: "localhost"), "localhost")
    }

    /// The old seeder persisted an "apple.com passkey" whose password was the bullet mask. Filling
    /// it submits eight bullets and every login fails with "无法验证你的身份". It must never be
    /// treated as a secret again.
    func testPlaceholderAndEmptyPasswordsAreNotFillable() {
        let masked = SavedCredential(
            domain: "apple.com",
            username: "yangliangsky@gmail.com",
            password: SavedCredential.legacyPlaceholderPassword
        )
        XCTAssertFalse(masked.isFillable)

        let empty = SavedCredential(domain: "example.com", username: "user", password: "")
        XCTAssertFalse(empty.isFillable)

        let real = SavedCredential(domain: "example.com", username: "user", password: "s3cret")
        XCTAssertTrue(real.isFillable)
    }

    func testLegacyDemoRecordsAreOnlyTheFabricatedSeeds() {
        let appleSeed = SavedCredential(
            domain: "apple.com",
            username: "yangliangsky@gmail.com",
            password: SavedCredential.legacyPlaceholderPassword
        )
        let huaweiSeed = SavedCredential(
            domain: "id1.cloud.huawei.com",
            username: "18627178676",
            password: SavedCredential.legacyPlaceholderPassword
        )
        XCTAssertTrue(appleSeed.isLegacyDemoRecord)
        XCTAssertTrue(huaweiSeed.isLegacyDemoRecord)

        // A genuine record for the same account has a real password and must be preserved.
        let genuine = SavedCredential(
            domain: "apple.com",
            username: "yangliangsky@gmail.com",
            password: "real-password"
        )
        XCTAssertFalse(genuine.isLegacyDemoRecord)

        let remaining = CredentialStore.removingLegacyDemoRecords(from: [appleSeed, huaweiSeed, genuine])
        XCTAssertEqual(remaining.map(\.username), ["yangliangsky@gmail.com"])
        XCTAssertEqual(remaining.first?.password, "real-password")
    }

    func testAutoFillOnlyOfferedWhenASecretExists() {
        XCTAssertFalse(CredentialStore.canOfferAutoFill([]))
        XCTAssertFalse(CredentialStore.canOfferAutoFill([
            SavedCredential(domain: "apple.com", username: "a@b.c", password: "")
        ]))
        XCTAssertTrue(CredentialStore.canOfferAutoFill([
            SavedCredential(domain: "example.com", username: "user", password: "s3cret")
        ]))
    }

    @MainActor
    func testCredentialStoreSaveQueryDelete() {
        let store = CredentialStore.shared
        let testDomain = "test-\(UUID().uuidString).example.com"

        let cred1 = SavedCredential(
            domain: testDomain,
            username: "tester1@example.com",
            password: "password123"
        )
        let cred2 = SavedCredential(
            domain: testDomain,
            username: "tester2@example.com",
            password: "password456"
        )

        store.save(credential: cred1)
        store.save(credential: cred2)

        let queryExact = store.credentials(for: testDomain)
        XCTAssertGreaterThanOrEqual(queryExact.count, 2)

        // Query by subdomain
        let querySub = store.credentials(for: "sub." + testDomain)
        XCTAssertGreaterThanOrEqual(querySub.count, 2)

        // Clean up
        store.delete(id: cred1.id)
        store.delete(id: cred2.id)

        let afterDelete = store.credentials(for: testDomain)
        XCTAssertFalse(afterDelete.contains(where: { $0.id == cred1.id || $0.id == cred2.id }))
    }

    @MainActor
    func testAutoFillPopoverControllerLifecycle() {
        let controller = AutoFillPopoverController.shared
        XCTAssertFalse(controller.isVisible)
        controller.dismiss()
        XCTAssertFalse(controller.isVisible)
    }

    @MainActor
    func testAutoFillSuggestionViewHierarchy() {
        let creds: [SavedCredential] = [
            SavedCredential(
                domain: "id1.cloud.huawei.com",
                username: "18627178676",
                password: "secretPassword"
            )
        ]

        var selectedCred: SavedCredential?

        let view = AutoFillSuggestionView(
            credentials: creds,
            currentHost: "id1.cloud.huawei.com",
            onSelectCredential: { selectedCred = $0 }
        )

        XCTAssertEqual(view.credentials.count, 1)
        XCTAssertEqual(view.currentHost, "id1.cloud.huawei.com")

        view.onSelectCredential(creds[0])
        XCTAssertEqual(selectedCred?.username, "18627178676")
    }

    /// Loads a real login form in a WKWebView and drives the injected agent exactly like the app
    /// does. This is the seam that reproduces the reported failure: selecting a credential used to
    /// submit the form by itself and broadcast the secret to every iframe.
    @MainActor
    func testAgentFillsWithoutAutoSubmittingOrBroadcasting() {
        let recorder = AutoFillMessageRecorder()
        let controller = WKUserContentController()
        controller.add(recorder, name: "zhuoAutoFill")
        guard let script = InjectedScripts.shared.makeAutoFillScript() else {
            XCTFail("autofill-agent script missing")
            return
        }
        controller.addUserScript(script)

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 600, height: 400), configuration: configuration)

        let html = """
        <html><body>
        <form id="f" onsubmit="window.__submitted = true; return false;">
          <input id="u" name="username" autocomplete="username">
          <input id="p" type="password" name="password">
          <button type="submit">登录</button>
        </form>
        <script>
          window.__broadcast = 0;
          window.addEventListener('message', function (e) {
            if (e.data && e.data.type === 'zhuo-autofill-broadcast-fill') { window.__broadcast += 1; }
          });
        </script>
        </body></html>
        """

        let navigation = NavigationFinished()
        webView.navigationDelegate = navigation
        let loaded = expectation(description: "page loaded")
        navigation.onFinish = { loaded.fulfill() }
        webView.loadHTMLString(html, baseURL: URL(string: "https://login.example.com/")!)
        wait(for: [loaded], timeout: 5)

        // Document-end user scripts run after the document is parsed; give the agent one beat.
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

        let filled = expectation(description: "filled")
        webView.evaluateJavaScript(
            "document.getElementById('u').focus(); JSON.stringify(window.__zhuoAutoFill.fill('alice', 's3cret'))"
        ) { result, error in
            XCTAssertNil(error)
            XCTAssertEqual(result as? String, "true")
            filled.fulfill()
        }
        wait(for: [filled], timeout: 5)

        XCTAssertTrue(recorder.actions.contains("focus"), "agent should report the focused login field")

        let inspected = expectation(description: "inspected")
        webView.evaluateJavaScript(
            "JSON.stringify({u: document.getElementById('u').value," +
            " p: document.getElementById('p').value," +
            " submitted: !!window.__submitted," +
            " broadcast: window.__broadcast})"
        ) { result, error in
            XCTAssertNil(error)
            let json = (result as? String).flatMap { $0.data(using: .utf8) } ?? Data()
            let state = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any]
            XCTAssertEqual(state?["u"] as? String, "alice")
            XCTAssertEqual(state?["p"] as? String, "s3cret")
            XCTAssertEqual(state?["submitted"] as? Bool, false, "filling must not submit the login form")
            XCTAssertEqual(state?["broadcast"] as? Int, 0, "the secret must never be posted to frames")
            inspected.fulfill()
        }
        wait(for: [inspected], timeout: 5)

        // Detach the web view so its WebContent process does not outlive the test and collide
        // with the web views created by later tests in the same host process.
        webView.stopLoading()
        webView.navigationDelegate = nil
        controller.removeScriptMessageHandler(forName: "zhuoAutoFill")
    }
}

private final class AutoFillMessageRecorder: NSObject, WKScriptMessageHandler {
    private(set) var actions: [String] = []

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let action = body["action"] as? String else { return }
        actions.append(action)
    }
}

private final class NavigationFinished: NSObject, WKNavigationDelegate {
    var onFinish: (() -> Void)?

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onFinish?()
    }
}
