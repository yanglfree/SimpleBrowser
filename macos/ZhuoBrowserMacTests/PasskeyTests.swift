import XCTest
import WebKit
@testable import ZhuoBrowserMac

final class PasskeyTests: XCTestCase {
    @MainActor
    func testPasskeyManagerSingleton() {
        let manager = PasskeyManager.shared
        XCTAssertNotNil(manager)
        // Verify state is one of the valid enum cases
        let state = manager.authorizationState
        XCTAssertTrue([.authorized, .denied, .notDetermined].contains(state))
    }

    func testPasskeyAdapterScriptContent() {
        let script = InjectedScripts.shared.makePasskeyAdapterScript()
        XCTAssertNotNil(script, "Passkey adapter script should load from resources")
        guard let script = script else { return }

        XCTAssertEqual(script.injectionTime, .atDocumentStart)
        XCTAssertFalse(script.isForMainFrameOnly)

        let source = script.source
        XCTAssertTrue(source.contains("isUserVerifyingPlatformAuthenticatorAvailable"))
        XCTAssertTrue(source.contains("getClientCapabilities"))
        XCTAssertTrue(source.contains("assistAuthenticationFallback"))
        XCTAssertTrue(source.contains("passkeyPlatformAuthenticator"))
    }

    @MainActor
    func testTabControllerInstallsPasskeyScript() {
        let session = BrowserSession()
        let controller = TabController(tabID: "test-tab", session: session, initialURL: nil, isPrivate: false)
        guard let webView = controller.webView else {
            XCTFail("TabController should create a webView")
            return
        }

        let userScripts = webView.configuration.userContentController.userScripts
        let hasPasskeyScript = userScripts.contains { script in
            script.source.contains("isUserVerifyingPlatformAuthenticatorAvailable")
        }
        XCTAssertTrue(hasPasskeyScript, "TabController webView should install passkey adapter script")
    }
}
