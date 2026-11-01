import XCTest
import WebKit
@testable import ZhuoBrowserMac

final class TabControllerDialogTests: XCTestCase {
    @MainActor
    func testPromptHandlerInterceptsTokenPrompt() {
        let session = BrowserSession()
        let controller = TabController(tabID: "dialog-test", session: session, initialURL: nil, isPrivate: false)
        guard let webView = controller.webView else {
            XCTFail("TabController should have a webView")
            return
        }

        var interceptedPrompt: String?
        var interceptedDefault: String?
        controller.promptHandler = { prompt, defaultText in
            interceptedPrompt = prompt
            interceptedDefault = defaultText
            return "ghp_mockToken123456789"
        }

        let expectation = self.expectation(description: "Prompt evaluated")
        webView.evaluateJavaScript("prompt('请输入访问 Token:', 'default-token')") { result, error in
            XCTAssertNil(error)
            XCTAssertEqual(result as? String, "ghp_mockToken123456789")
            expectation.fulfill()
        }

        waitForExpectations(timeout: 5.0)
        XCTAssertEqual(interceptedPrompt, "请输入访问 Token:")
        XCTAssertEqual(interceptedDefault, "default-token")
    }

    @MainActor
    func testPromptHandlerCancellationReturnsNil() {
        let session = BrowserSession()
        let controller = TabController(tabID: "dialog-cancel-test", session: session, initialURL: nil, isPrivate: false)
        guard let webView = controller.webView else {
            XCTFail("TabController should have a webView")
            return
        }

        controller.promptHandler = { _, _ in
            return nil
        }

        let expectation = self.expectation(description: "Prompt cancelled")
        webView.evaluateJavaScript("prompt('Enter token:')") { result, error in
            XCTAssertNil(error)
            XCTAssertTrue(result == nil || result is NSNull)
            expectation.fulfill()
        }

        waitForExpectations(timeout: 5.0)
    }

    @MainActor
    func testAlertHandlerInvoked() {
        let session = BrowserSession()
        let controller = TabController(tabID: "alert-test", session: session, initialURL: nil, isPrivate: false)
        guard let webView = controller.webView else {
            XCTFail("TabController should have a webView")
            return
        }

        var interceptedMessage: String?
        controller.alertHandler = { message in
            interceptedMessage = message
        }

        let expectation = self.expectation(description: "Alert evaluated")
        webView.evaluateJavaScript("alert('Token loaded successfully')") { _, error in
            XCTAssertNil(error)
            expectation.fulfill()
        }

        waitForExpectations(timeout: 5.0)
        XCTAssertEqual(interceptedMessage, "Token loaded successfully")
    }

    @MainActor
    func testConfirmHandlerReturnsTrue() {
        let session = BrowserSession()
        let controller = TabController(tabID: "confirm-test", session: session, initialURL: nil, isPrivate: false)
        guard let webView = controller.webView else {
            XCTFail("TabController should have a webView")
            return
        }

        controller.confirmHandler = { message in
            return true
        }

        let expectation = self.expectation(description: "Confirm evaluated")
        webView.evaluateJavaScript("confirm('Save token?')") { result, error in
            XCTAssertNil(error)
            XCTAssertEqual(result as? Bool, true)
            expectation.fulfill()
        }

        waitForExpectations(timeout: 5.0)
    }

    @MainActor
    func testAuthChallengeHandlerInterceptsChallenge() {
        let session = BrowserSession()
        let controller = TabController(tabID: "auth-test", session: session, initialURL: nil, isPrivate: false)

        var challengeIntercepted = false
        controller.authChallengeHandler = { challenge in
            challengeIntercepted = true
            return (.cancelAuthenticationChallenge, nil)
        }

        let protectionSpace = URLProtectionSpace(
            host: "api.example.com",
            port: 443,
            protocol: "https",
            realm: "Token Required",
            authenticationMethod: NSURLAuthenticationMethodHTTPBasic
        )
        let challenge = URLAuthenticationChallenge(
            protectionSpace: protectionSpace,
            proposedCredential: nil,
            previousFailureCount: 0,
            failureResponse: nil,
            error: nil,
            sender: DummyChallengeSender()
        )

        let expectation = self.expectation(description: "Challenge completed")
        controller.webView(controller.webView!, didReceive: challenge) { disposition, credential in
            XCTAssertEqual(disposition, .cancelAuthenticationChallenge)
            XCTAssertNil(credential)
            expectation.fulfill()
        }

        waitForExpectations(timeout: 2.0)
        XCTAssertTrue(challengeIntercepted)
    }
}

private final class DummyChallengeSender: NSObject, URLAuthenticationChallengeSender {
    func cancel(_ challenge: URLAuthenticationChallenge) {}
    func continueWithoutCredential(for challenge: URLAuthenticationChallenge) {}
    func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) {}
    func performDefaultHandling(for challenge: URLAuthenticationChallenge) {}
    func rejectProtectionSpaceAndContinue(for challenge: URLAuthenticationChallenge) {}
}
