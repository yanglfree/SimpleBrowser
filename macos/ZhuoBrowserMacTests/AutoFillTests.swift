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
        controller.add(recorder, contentWorld: .defaultClient, name: "zhuoAutoFill")
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
            "document.getElementById('u').focus(); JSON.stringify(window.__zhuoAutoFill.fill('alice', 's3cret'))",
            in: nil,
            in: .defaultClient
        ) { result in
            switch result {
            case .success(let value):
                XCTAssertEqual(value as? String, "true")
            case .failure(let error):
                XCTFail("Unexpected JS error: \(error)")
            }
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
        controller.removeScriptMessageHandler(forName: "zhuoAutoFill", contentWorld: .defaultClient)
    }

    func testAutoFillIframeOriginPolicy() {
        // App Store Connect embeds idmsa.apple.com via HTTPS iframe — same registrable root domain.
        XCTAssertTrue(TabController.isAutoFillAllowed(
            frameHost: "idmsa.apple.com",
            frameScheme: "https",
            topLevelHost: "appstoreconnect.apple.com",
            isMainFrame: false
        ))
        XCTAssertEqual(
            TabController.effectiveAutoFillHost(
                frameHost: "idmsa.apple.com",
                topLevelHost: "appstoreconnect.apple.com",
                isMainFrame: false
            ),
            "idmsa.apple.com"
        )

        // Third-party embeds or insecure HTTP iframes must be rejected.
        XCTAssertFalse(TabController.isAutoFillAllowed(
            frameHost: "idmsa.apple.com",
            frameScheme: "https",
            topLevelHost: "evil.com",
            isMainFrame: false
        ))
        XCTAssertFalse(TabController.isAutoFillAllowed(
            frameHost: "idmsa.apple.com",
            frameScheme: "http",
            topLevelHost: "appstoreconnect.apple.com",
            isMainFrame: false
        ))

        // Main frame is allowed when a host exists.
        XCTAssertTrue(TabController.isAutoFillAllowed(
            frameHost: "login.example.com",
            frameScheme: "https",
            topLevelHost: "login.example.com",
            isMainFrame: true
        ))
        XCTAssertFalse(TabController.isAutoFillAllowed(
            frameHost: "",
            frameScheme: "about",
            topLevelHost: "",
            isMainFrame: true
        ))
    }

    @MainActor
    func testAgentReportsAlreadyFocusedAndClickedInput() {
        let recorder = AutoFillMessageRecorder()
        let controller = WKUserContentController()
        controller.add(recorder, contentWorld: .defaultClient, name: "zhuoAutoFill")
        guard let script = InjectedScripts.shared.makeAutoFillScript() else {
            XCTFail("autofill-agent script missing")
            return
        }
        controller.addUserScript(script)

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 600, height: 400), configuration: configuration)
        defer {
            webView.stopLoading()
            webView.navigationDelegate = nil
            controller.removeScriptMessageHandler(forName: "zhuoAutoFill", contentWorld: .defaultClient)
        }

        let html = """
        <html><body>
          <input id="u" autocomplete="username webauthn">
          <script>document.getElementById('u').focus();</script>
        </body></html>
        """

        let navigation = NavigationFinished()
        webView.navigationDelegate = navigation
        let loaded = expectation(description: "page loaded")
        navigation.onFinish = { loaded.fulfill() }
        webView.loadHTMLString(html, baseURL: URL(string: "https://idmsa.apple.com/")!)
        wait(for: [loaded], timeout: 5)

        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        let initialFocusCount = recorder.actions.filter { $0 == "focus" }.count
        XCTAssertGreaterThanOrEqual(initialFocusCount, 1, "agent should report an already-focused candidate on init")

        let clicked = expectation(description: "clicked")
        webView.evaluateJavaScript("document.getElementById('u').click(); true") { _, error in
            XCTAssertNil(error)
            clicked.fulfill()
        }
        wait(for: [clicked], timeout: 5)
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))

        let afterClickFocusCount = recorder.actions.filter { $0 == "focus" }.count
        XCTAssertGreaterThan(afterClickFocusCount, initialFocusCount, "clicking an already-focused candidate should re-report focus")
    }

    @MainActor
    func testAgentCapturesTwoStepAndEnterKeySubmission() {
        let recorder = AutoFillMessageRecorder()
        let controller = WKUserContentController()
        controller.add(recorder, contentWorld: .defaultClient, name: "zhuoAutoFill")
        guard let script = InjectedScripts.shared.makeAutoFillScript() else {
            XCTFail("autofill-agent script missing")
            return
        }
        controller.addUserScript(script)

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 600, height: 400), configuration: configuration)
        defer {
            webView.stopLoading()
            webView.navigationDelegate = nil
            controller.removeScriptMessageHandler(forName: "zhuoAutoFill", contentWorld: .defaultClient)
        }

        let html = """
        <html><body>
          <div id="step1"><input id="u" autocomplete="username"></div>
          <div id="step2" style="display:none"><input id="p" type="password" autocomplete="current-password"></div>
        </body></html>
        """

        let navigation = NavigationFinished()
        webView.navigationDelegate = navigation
        let loaded = expectation(description: "page loaded")
        navigation.onFinish = { loaded.fulfill() }
        webView.loadHTMLString(html, baseURL: URL(string: "https://idmsa.apple.com/")!)
        wait(for: [loaded], timeout: 5)
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

        // Step 1: type username and remove username input; Step 2: fill password and press Enter twice
        let stepScript = """
        (() => {
          const u = document.getElementById('u');
          u.focus();
          u.value = 'alice@apple.com';
          u.dispatchEvent(new Event('input', { bubbles: true }));
          document.getElementById('step1').remove();

          document.getElementById('step2').style.display = 'block';
          const p = document.getElementById('p');
          p.focus();
          p.value = 'twoStepSecret!';
          p.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }));
          p.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }));
          return true;
        })()
        """
        let done = expectation(description: "two-step done")
        webView.evaluateJavaScript(stepScript) { _, error in
            XCTAssertNil(error)
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

        let submissions = recorder.messages.filter { $0.action == "submitted" }
        XCTAssertEqual(submissions.count, 1, "repeated Enter within 3s should be deduplicated")
        XCTAssertEqual(submissions.first?.payload["username"] as? String, "alice@apple.com")
        XCTAssertEqual(submissions.first?.payload["password"] as? String, "twoStepSecret!")
    }

    @MainActor
    func testWKFrameInfoTargetedFillDoesNotLeakToParentFrame() {
        let recorder = AutoFillMessageRecorder()
        let controller = WKUserContentController()
        controller.add(recorder, contentWorld: .defaultClient, name: "zhuoAutoFill")
        guard let script = InjectedScripts.shared.makeAutoFillScript() else {
            XCTFail("autofill-agent script missing")
            return
        }
        controller.addUserScript(script)

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 600, height: 400), configuration: configuration)
        defer {
            webView.stopLoading()
            webView.navigationDelegate = nil
            controller.removeScriptMessageHandler(forName: "zhuoAutoFill", contentWorld: .defaultClient)
        }

        let html = """
        <html><body>
          <input id="decoyPass" type="password" name="password">
          <iframe id="f" style="width:300px;height:200px" srcdoc="
            <html><body>
              <form onsubmit='return false;'>
                <input id='iu' name='username' autocomplete='username'>
                <input id='ip' type='password' name='password'>
              </form>
            </body></html>
          "></iframe>
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
        let loaded = expectation(description: "iframe page loaded")
        navigation.onFinish = { loaded.fulfill() }
        webView.loadHTMLString(html, baseURL: URL(string: "https://appstoreconnect.apple.com/")!)
        wait(for: [loaded], timeout: 5)
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))

        let focusedIframe = expectation(description: "focused iframe input")
        webView.evaluateJavaScript("document.getElementById('f').contentDocument.getElementById('iu').focus(); true") { _, error in
            XCTAssertNil(error)
            focusedIframe.fulfill()
        }
        wait(for: [focusedIframe], timeout: 5)
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

        guard let iframeMsg = recorder.messages.last(where: { $0.action == "focus" && !$0.frameInfo.isMainFrame }) else {
            XCTFail("Expected a focus message from the iframe's WKFrameInfo")
            return
        }

        let filled = expectation(description: "targeted fill")
        webView.evaluateJavaScript(
            "window.__zhuoAutoFill.fill('iframeUser', 'iframeSecret')",
            in: iframeMsg.frameInfo,
            in: .defaultClient
        ) { result in
            if case .failure(let error) = result {
                XCTFail("Targeted frame fill failed: \(error)")
            }
            filled.fulfill()
        }
        wait(for: [filled], timeout: 5)

        let verified = expectation(description: "verified isolation")
        let verifyJS = """
        JSON.stringify({
          iu: document.getElementById('f').contentDocument.getElementById('iu').value,
          ip: document.getElementById('f').contentDocument.getElementById('ip').value,
          decoy: document.getElementById('decoyPass').value,
          broadcast: window.__broadcast
        })
        """
        webView.evaluateJavaScript(verifyJS) { result, error in
            XCTAssertNil(error)
            let json = (result as? String).flatMap { $0.data(using: .utf8) } ?? Data()
            let state = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any]
            XCTAssertEqual(state?["iu"] as? String, "iframeUser")
            XCTAssertEqual(state?["ip"] as? String, "iframeSecret")
            XCTAssertEqual(state?["decoy"] as? String, "", "parent frame decoy password must stay untouched")
            XCTAssertEqual(state?["broadcast"] as? Int, 0, "no postMessage broadcast allowed")
            verified.fulfill()
        }
        wait(for: [verified], timeout: 5)
    }

    @MainActor
    func testCredentialCSVImporterParsesSafariAndChromeFormats() {
        let testHost1 = "csv-apple-\(UUID().uuidString.lowercased()).example.com"
        let testHost2 = "csv-chrome-\(UUID().uuidString.lowercased()).example.com"
        defer {
            let store = CredentialStore.shared
            store.delete(SavedCredential(domain: testHost1, username: "alice@example.com"))
            store.delete(SavedCredential(domain: testHost2, username: "bob@example.com"))
        }

        // Safari format with UTF-8 BOM, quoted comma in Title, escaped quotes in password
        let safariCSV = "\u{FEFF}Title,URL,Username,Password,Notes,OTPAuth\r\n" +
            "\"Apple, Inc.\",https://\(testHost1)/auth/signin,alice@example.com,\"p@ss\"\"word,1\",note,\r\n" +
            "EmptyPass,https://ignored.example.com,nobody,,note,\r\n" +
            "Placeholder,https://ignored2.example.com,fake,\(SavedCredential.legacyPlaceholderPassword),note,\r\n"

        let parsedSafari = CredentialCSVImporter.parse(csv: safariCSV)
        XCTAssertEqual(parsedSafari.count, 1)
        XCTAssertEqual(parsedSafari.first?.domain, testHost1)
        XCTAssertEqual(parsedSafari.first?.username, "alice@example.com")
        XCTAssertEqual(parsedSafari.first?.password, "p@ss\"word,1")

        // Chrome format with bare hostname
        let chromeCSV = "name,url,username,password,note\n" +
            "Work,\(testHost2),bob@example.com,chromeSecret99,work\n"

        let summary1 = CredentialStore.shared.importCSV(safariCSV)
        XCTAssertEqual(summary1.imported, 1)
        XCTAssertEqual(summary1.skipped, 2)

        let summary2 = CredentialStore.shared.importCSV(chromeCSV)
        XCTAssertEqual(summary2.imported, 1)
        XCTAssertEqual(summary2.skipped, 0)

        let all = CredentialStore.shared.allCredentials()
        XCTAssertTrue(all.contains { $0.domain == testHost1 && $0.username == "alice@example.com" })
        XCTAssertTrue(all.contains { $0.domain == testHost2 && $0.username == "bob@example.com" })
        XCTAssertEqual(CredentialStore.shared.password(forDomain: testHost1, username: "alice@example.com"), "p@ss\"word,1")
        XCTAssertEqual(CredentialStore.shared.password(forDomain: testHost2, username: "bob@example.com"), "chromeSecret99")
    }
}

private final class AutoFillMessageRecorder: NSObject, WKScriptMessageHandler {
    private(set) var actions: [String] = []
    private(set) var messages: [(action: String, payload: [String: Any], frameInfo: WKFrameInfo)] = []

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let action = body["action"] as? String else { return }
        actions.append(action)
        messages.append((action: action, payload: body, frameInfo: message.frameInfo))
    }
}

private final class NavigationFinished: NSObject, WKNavigationDelegate {
    var onFinish: (() -> Void)?

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onFinish?()
    }
}
