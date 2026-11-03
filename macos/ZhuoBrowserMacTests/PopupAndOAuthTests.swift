import AppKit
import WebKit
import XCTest
@testable import ZhuoBrowserMac

@MainActor
final class PopupAndOAuthTests: XCTestCase {

    override func tearDown() {
        WebPopupWindowManager.shared.closeAllPopups()
        super.tearDown()
    }

    // MARK: - 1. OAuthPolicy Tests

    func testOAuthPolicyDetectsGoogleAndMajorAuthProviders() {
        // Google authentication endpoints
        let googleOAuth = URL(string: "https://accounts.google.com/o/oauth2/v2/auth?client_id=test&response_type=code")!
        let googleSignIn = URL(string: "https://accounts.google.com/signin/v2/identifier")!
        let googleService = URL(string: "https://accounts.google.com/ServiceLogin?service=mail")!
        XCTAssertTrue(OAuthPolicy.isOAuthOrLoginURL(googleOAuth))
        XCTAssertTrue(OAuthPolicy.isOAuthOrLoginURL(googleSignIn))
        XCTAssertTrue(OAuthPolicy.isOAuthOrLoginURL(googleService))

        // Apple ID
        let appleAuth = URL(string: "https://appleid.apple.com/auth/authorize?client_id=app&response_type=code")!
        XCTAssertTrue(OAuthPolicy.isOAuthOrLoginURL(appleAuth))

        // GitHub OAuth
        let githubOAuth = URL(string: "https://github.com/login/oauth/authorize?client_id=gh123")!
        XCTAssertTrue(OAuthPolicy.isOAuthOrLoginURL(githubOAuth))

        // Microsoft / Live
        let msftOAuth = URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize?client_id=ms")!
        XCTAssertTrue(OAuthPolicy.isOAuthOrLoginURL(msftOAuth))

        // Generic OAuth with standard params
        let genericOAuth = URL(string: "https://auth.example.com/oauth2/authorize?client_id=abc&response_type=code&redirect_uri=https://example.com/cb")!
        XCTAssertTrue(OAuthPolicy.isOAuthOrLoginURL(genericOAuth))

        // Regular websites must NOT match
        let normalSearch = URL(string: "https://www.google.com/search?q=swiftui")!
        let normalRepo = URL(string: "https://github.com/apple/swift")!
        let normalPage = URL(string: "https://example.com/article")!
        XCTAssertFalse(OAuthPolicy.isOAuthOrLoginURL(normalSearch))
        XCTAssertFalse(OAuthPolicy.isOAuthOrLoginURL(normalRepo))
        XCTAssertFalse(OAuthPolicy.isOAuthOrLoginURL(normalPage))
    }

    func testOAuthPolicyShouldOpenAsPopup() {
        let features = WKWindowFeatures()

        // Empty features + normal URL: not a popup
        let normalURL = URL(string: "https://example.com")!
        XCTAssertFalse(OAuthPolicy.shouldOpenAsPopup(features: features, url: normalURL))

        // Empty features + Google login URL: should be a popup
        let googleURL = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        XCTAssertTrue(OAuthPolicy.shouldOpenAsPopup(features: features, url: googleURL))
    }

    // MARK: - 2. WebPopupWindow & Manager Tests

    func testWebPopupWindowManagerPresentAndClose() {
        let manager = WebPopupWindowManager.shared
        XCTAssertEqual(manager.openPopupCount, 0)

        let config = WKWebViewConfiguration()
        let features = WKWindowFeatures()
        let testURL = URL(string: "https://accounts.google.com/signin")!

        let webView = manager.presentPopup(
            configuration: config,
            features: features,
            initialURL: testURL
        )

        XCTAssertEqual(manager.openPopupCount, 1)
        XCTAssertNotNil(webView.window)
        XCTAssertEqual(webView.window?.styleMask.contains(.titled), true)
        XCTAssertEqual(webView.window?.styleMask.contains(.closable), true)
        XCTAssertEqual(webView.window?.styleMask.contains(.resizable), true)

        let controller = manager.activeControllers.first
        XCTAssertNotNil(controller)

        // Simulating webViewDidClose (e.g. login finished and web page calls window.close())
        controller?.webViewDidClose(webView)

        XCTAssertEqual(manager.openPopupCount, 0)
    }

    func testWebPopupWindowManagerOpenPopupDirectly() {
        let manager = WebPopupWindowManager.shared
        let loginURL = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!

        let controller = manager.openPopup(url: loginURL)
        XCTAssertEqual(manager.openPopupCount, 1)
        XCTAssertEqual(controller.window?.isVisible, true)

        manager.closeAllPopups()
        XCTAssertEqual(manager.openPopupCount, 0)
    }

    // MARK: - 3. TabController Popup Integration

    func testTabControllerCreateWebViewWithReturnsPopupForOAuth() {
        let session = BrowserSession()
        session.createTab(url: "https://example.com/login", select: true)

        guard let controller = session.activeController, let webView = controller.webView else {
            XCTFail("Active controller and webView must exist")
            return
        }

        let oauthURL = URL(string: "https://accounts.google.com/o/oauth2/v2/auth?client_id=123")!
        let request = URLRequest(url: oauthURL)

        class MockNavigationAction: WKNavigationAction {
            let req: URLRequest
            init(req: URLRequest) {
                self.req = req
                super.init()
            }
            override var request: URLRequest { req }
            override var targetFrame: WKFrameInfo? { nil }
        }

        let mockAction = MockNavigationAction(req: request)
        let features = WKWindowFeatures()

        let returnedWebView = controller.webView(
            webView,
            createWebViewWith: webView.configuration,
            for: mockAction,
            windowFeatures: features
        )

        // Must return dedicated popup web view and NOT navigate current tab
        XCTAssertNotNil(returnedWebView)
        XCTAssertEqual(WebPopupWindowManager.shared.openPopupCount, 1)
        XCTAssertEqual(session.activeTab?.url, "https://example.com/login")
    }

    func testTabControllerCreateWebViewWithOpensTabForTargetBlank() {
        let session = BrowserSession()
        session.createTab(url: "https://example.com/article", select: true)
        let countBefore = session.tabs.count

        guard let controller = session.activeController, let webView = controller.webView else {
            XCTFail("Active controller and webView must exist")
            return
        }

        let articleURL = URL(string: "https://example.com/another-article")!
        let request = URLRequest(url: articleURL)

        class MockNavigationAction: WKNavigationAction {
            let req: URLRequest
            init(req: URLRequest) {
                self.req = req
                super.init()
            }
            override var request: URLRequest { req }
            override var targetFrame: WKFrameInfo? { nil }
        }

        let mockAction = MockNavigationAction(req: request)
        let features = WKWindowFeatures()

        let returnedWebView = controller.webView(
            webView,
            createWebViewWith: webView.configuration,
            for: mockAction,
            windowFeatures: features
        )

        // For regular links, createWebViewWith returns nil, leaves current tab intact,
        // and creates a new tab in the session
        XCTAssertNil(returnedWebView)
        XCTAssertEqual(WebPopupWindowManager.shared.openPopupCount, 0)
        XCTAssertEqual(session.tabs.count, countBefore + 1)
        XCTAssertEqual(session.activeTab?.url, "https://example.com/another-article")
    }

    // MARK: - 4. BrowserSession External URL Routing

    func testLiveJavaScriptWindowOpenPreservesOpener() {
        let session = BrowserSession()
        session.createTab(url: "https://x.com", select: true)

        guard let controller = session.activeController, let webView = controller.webView else {
            XCTFail("Active controller and webView must exist")
            return
        }

        let expectation = expectation(description: "Live window.open preserves opener")

        let html = """
        <html><body>
        <script>
        function triggerLogin() {
            var w = window.open(
                "https://accounts.google.com/gsi/select?client_id=49625052041-kgt0hghf445lmcmhijv46b715m2mpbct.apps.googleusercontent.com&ux_mode=popup&ui_mode=card&as=u4Yh5mz6Dr8N2wKJZ5-8KtNaxp3vjjQzyRo5si3rn3s&bs=iysd5TRkvOz0a19hDLMXkvyDu%2Be4Z8Ef4%2BSnwg%2FJI%2FI&channel_id=1f51fd879688de9abf27e8cb8dd50400873f077f77919404ba3c1171da0a3f1a&origin=https%3A%2F%2Fx.com",
                "g_credential_picker",
                "toolbar=no,location=no,directories=no,status=no,menubar=no,scrollbars=no,resizable=no,copyhistory=no,width=500,height=550"
            );
            return w != null;
        }
        </script>
        </body></html>
        """

        webView.loadHTMLString(html, baseURL: URL(string: "https://x.com"))

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            webView.evaluateJavaScript("triggerLogin()") { result, error in
                XCTAssertNil(error)
                XCTAssertEqual(result as? Bool, true)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    let popups = WebPopupWindowManager.shared.activeControllers
                    XCTAssertEqual(popups.count, 1)
                    if let popup = popups.first {
                        popup.webView.evaluateJavaScript("!!window.opener") { hasOpener, err in
                            XCTAssertNil(err)
                            XCTAssertEqual(hasOpener as? Bool, true, "window.opener must be preserved in popup")
                            expectation.fulfill()
                        }
                    } else {
                        XCTFail("Popup must be open")
                        expectation.fulfill()
                    }
                }
            }
        }

        wait(for: [expectation], timeout: 5.0)
    }

    func testDecidePolicyDivertsMainFramePopupModeToPopupWindow() {
        let session = BrowserSession()
        session.createTab(url: "https://x.com", select: true)

        guard let controller = session.activeController, let webView = controller.webView else {
            XCTFail("Active controller and webView must exist")
            return
        }

        let expectation = expectation(description: "Diverts ux_mode=popup to popup window")

        let gsiURL = URL(string: "https://accounts.google.com/gsi/select?client_id=123&ux_mode=popup&origin=https%3A%2F%2Fx.com")!

        // Load the URL directly into the tab: TabController's decidePolicyFor must intercept
        // and divert to a popup window instead of loading into the main frame tab.
        controller.load(url: gsiURL)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            XCTAssertEqual(WebPopupWindowManager.shared.openPopupCount, 1)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 3.0)
    }

    // MARK: - 5. BrowserSession External URL Routing

    func testBrowserSessionOpenExternalURLRoutesOAuthToPopup() {
        let session = BrowserSession.shared
        session.tabs.removeAll()
        session.createTab(url: "https://example.com", select: true)

        // 1. Google OAuth URL must open as a popup window, NOT duplicate tabs
        session.openExternalURL("https://accounts.google.com/o/oauth2/v2/auth?client_id=abc&response_type=code")
        XCTAssertEqual(WebPopupWindowManager.shared.openPopupCount, 1)
        XCTAssertEqual(session.tabs.count, 1) // Session tabs stay unchanged!

        // 2. Regular external URL must open as a tab
        session.openExternalURL("https://news.ycombinator.com")
        XCTAssertEqual(session.tabs.count, 2)
        XCTAssertTrue(session.activeTab?.url.hasPrefix("https://news.ycombinator.com") == true)
    }
}
