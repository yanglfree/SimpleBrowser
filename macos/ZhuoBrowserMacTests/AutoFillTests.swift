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

    func testCandidateHostsWalkUpToTheRegistrableDomain() {
        XCTAssertEqual(
            SavedCredential.candidateHosts(for: "idmsa.apple.com"),
            ["idmsa.apple.com", "apple.com"]
        )
        XCTAssertEqual(
            SavedCredential.candidateHosts(for: "a.b.example.co.uk"),
            ["a.b.example.co.uk", "b.example.co.uk", "example.co.uk"]
        )
        XCTAssertEqual(SavedCredential.candidateHosts(for: "localhost"), ["localhost"])
        XCTAssertEqual(SavedCredential.candidateHosts(for: ""), [])
    }

    func testPlaceholderAndEmptyPasswordsAreNeverStored() {
        XCTAssertFalse(SavedCredential.isFillablePassword(""))
        XCTAssertFalse(SavedCredential.isFillablePassword(SavedCredential.legacyPlaceholderPassword))
        XCTAssertTrue(SavedCredential.isFillablePassword("s3cret"))
    }

    /// The retired store held a fake apple.com "passkey" whose password was the bullet mask; the
    /// migration must drop it instead of copying it into the system keychain.
    func testLegacyMigrationSkipsFabricatedAndEmptyPasswords() {
        let entries = [
            LegacyStoredCredential(
                domain: "apple.com",
                username: "yangliangsky@gmail.com",
                password: SavedCredential.legacyPlaceholderPassword
            ),
            LegacyStoredCredential(domain: "example.com", username: "empty", password: ""),
            LegacyStoredCredential(domain: "example.com", username: "real", password: "real-password")
        ]

        let migrated = CredentialStore.migratableLegacyEntries(from: entries)
        XCTAssertEqual(migrated.map(\.username), ["real"])
        XCTAssertEqual(migrated.first?.password, "real-password")
    }

    @MainActor
    func testSystemKeychainSaveListReadDelete() {
        let store = CredentialStore.shared
        let domain = "test-\(UUID().uuidString).example.com"
        let username = "tester@example.com"
        let password = "p@ss\"word\\with\nnewline"

        defer {
            store.delete(SavedCredential(domain: domain, username: username))
        }

        XCTAssertTrue(store.save(domain: domain, username: username, password: password))

        let matches = store.credentials(for: domain)
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.username, username)
        XCTAssertEqual(matches.first?.domain, domain.lowercased())

        // A parent-domain lookup finds it too.
        XCTAssertEqual(store.credentials(for: "login." + domain).count, 1)

        XCTAssertEqual(store.password(forDomain: domain, username: username), password)
        XCTAssertEqual(store.password(for: matches[0]), password)

        store.delete(SavedCredential(domain: domain, username: username))
        XCTAssertTrue(store.credentials(for: domain).isEmpty)
        XCTAssertNil(store.password(forDomain: domain, username: username))
    }

    @MainActor
    func testKeychainRejectsTheLegacyPlaceholderPassword() {
        let store = CredentialStore.shared
        let domain = "test-\(UUID().uuidString).example.com"
        defer { store.delete(SavedCredential(domain: domain, username: "masked")) }

        XCTAssertFalse(store.save(
            domain: domain,
            username: "masked",
            password: SavedCredential.legacyPlaceholderPassword
        ))
        XCTAssertTrue(store.credentials(for: domain).isEmpty)
    }

    /// Passwords used to be persisted as plaintext JSON in UserDefaults alongside the private
    /// keychain items. The new store must never write them there.
    @MainActor
    func testPasswordIsNotPersistedInUserDefaults() {
        let store = CredentialStore.shared
        let domain = "test-\(UUID().uuidString).example.com"
        defer { store.delete(SavedCredential(domain: domain, username: "plain")) }

        XCTAssertTrue(store.save(domain: domain, username: "plain", password: "plain-secret"))
        XCTAssertNil(
            UserDefaults.standard.data(forKey: CredentialStore.legacyMetadataKey),
            "Passwords must never be written to UserDefaults again"
        )
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
            SavedCredential(domain: "id1.cloud.huawei.com", username: "18627178676")
        ]

        var selectedCred: SavedCredential?
        var didManagePasswords = false

        let view = AutoFillSuggestionView(
            credentials: creds,
            currentHost: "id1.cloud.huawei.com",
            onSelectCredential: { selectedCred = $0 },
            onManagePasswords: { didManagePasswords = true }
        )

        XCTAssertEqual(view.credentials.count, 1)
        XCTAssertEqual(view.currentHost, "id1.cloud.huawei.com")

        view.onSelectCredential(creds[0])
        XCTAssertEqual(selectedCred?.username, "18627178676")

        view.onManagePasswords()
        XCTAssertTrue(didManagePasswords)
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
