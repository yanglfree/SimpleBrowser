import XCTest
import WebKit
@testable import ZhuoBrowserMac

final class PasskeyTests: XCTestCase {

    /// Platform passkeys need Apple's restricted `com.apple.developer.web-browser.public-key-credential`
    /// entitlement. This build does not have it, so every "通行密钥" surface must stay honest.
    func testBrowserPasskeyEntitlementIsNotGranted() {
        XCTAssertFalse(PasskeyManager.shared.hasBrowserPasskeyEntitlement)
    }

    func testPasskeyAdapterScriptIsGone() {
        XCTAssertNil(
            InjectedScripts.shared.scriptContent(named: "passkey-adapter"),
            "Spoofing WebAuthn capabilities from injected JS must not come back"
        )
    }

    @MainActor
    func testWebViewDoesNotSpoofWebAuthnSupport() {
        let session = BrowserSession()
        let controller = TabController(tabID: "passkey-test-tab", session: session, initialURL: nil, isPrivate: false)
        guard let webView = controller.webView else {
            XCTFail("TabController should create a webView")
            return
        }

        let sources = webView.configuration.userContentController.userScripts.map(\.source)
        XCTAssertFalse(
            sources.contains { $0.contains("isUserVerifyingPlatformAuthenticatorAvailable") },
            "The app must not override WebKit's truthful passkey capabilities"
        )
        XCTAssertFalse(
            sources.contains { $0.contains("PublicKeyCredential") },
            "The app must not delete or patch PublicKeyCredential on any site"
        )
    }
}
