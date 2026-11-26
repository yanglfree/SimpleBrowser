import WebKit
import XCTest
@testable import ZhuoBrowser

@MainActor
final class PopupConfigurationTests: XCTestCase {
    func testPopupSharesOpenerUserContentControllerWithoutDuplicatingWiring() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let session = BrowserSession(
            persistence: BrowserPersistenceStore(directoryURL: directory, defaults: defaults)
        )
        let dataStore = WKWebsiteDataStore.nonPersistent()
        let opener = TabController(
            tab: BrowserTab.home(isPrivate: false),
            session: session,
            dataStore: dataStore
        )
        let openerConfiguration = opener.webView.configuration
        let scriptCount = openerConfiguration.userContentController.userScripts.count

        let popupConfiguration = try XCTUnwrap(
            openerConfiguration.copy() as? WKWebViewConfiguration
        )
        XCTAssertTrue(
            popupConfiguration.userContentController === openerConfiguration.userContentController
        )

        // WebKit hands `createWebViewWith` this copy. Building the popup tab used to
        // throw "Attempt to add script message handler with name ... when one already
        // exists" because the inherited controller was wired a second time.
        let popup = TabController(
            tab: BrowserTab.home(isPrivate: false),
            session: session,
            dataStore: dataStore,
            popupConfiguration: popupConfiguration
        )

        XCTAssertNotNil(popup.webView)
        XCTAssertEqual(
            popupConfiguration.userContentController.userScripts.count,
            scriptCount
        )
    }

    func testInheritedConfigurationSkipsScriptInstallation() {
        let configuration = WebKernel.makeConfiguration(
            isPrivate: false,
            dataStore: .nonPersistent(),
            blockAds: false,
            minimumFontSize: 14
        )
        let scriptCount = configuration.userContentController.userScripts.count

        WebKernel.configure(
            configuration,
            blockAds: true,
            minimumFontSize: 16,
            inheritsUserContent: true
        )

        XCTAssertEqual(configuration.userContentController.userScripts.count, scriptCount)
    }
}
