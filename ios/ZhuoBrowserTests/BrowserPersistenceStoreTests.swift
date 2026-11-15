import XCTest
@testable import ZhuoBrowser

final class BrowserPersistenceStoreTests: XCTestCase {
    private var tempDir: URL!
    private var defaultsSuiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrowserPersistenceStoreTests-\(UUID().uuidString)", isDirectory: true)
        defaultsSuiteName = "BrowserPersistenceStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testSaveLoadRoundTripAndFailedURLCodable() throws {
        let store = BrowserPersistenceStore(directoryURL: tempDir, defaults: defaults)
        var tab = BrowserTab.home(isPrivate: false)
        tab.url = "https://previous.example"
        tab.failedURL = "https://broken.example/path"
        tab.loadError = .dns

        XCTAssertEqual(tab.displayAddressURL, "https://broken.example/path")

        let payload = PersistedSession(tabs: [tab], activeTabID: tab.id)
        store.save(payload, for: .session)
        store.flush()

        XCTAssertTrue(FileManager.default.fileExists(atPath: store.fileURL(for: .session).path))

        let restored: PersistedSession? = store.load(.session, as: PersistedSession?.self) { nil }
        XCTAssertEqual(restored?.activeTabID, tab.id)
        XCTAssertEqual(restored?.tabs.first?.failedURL, "https://broken.example/path")
        XCTAssertEqual(restored?.tabs.first?.loadError, .dns)
    }

    func testMigratesLegacyUserDefaultsPayloadOnFirstLoad() throws {
        let store = BrowserPersistenceStore(directoryURL: tempDir, defaults: defaults)
        let legacy = [SavedItem(id: "s1", title: "Docs", url: "https://example.com", createdAt: 1, updatedAt: 2)]
        let data = try JSONEncoder().encode(legacy)
        defaults.set(data, forKey: BrowserPersistenceKey.savedItems.rawValue)

        let loaded = store.load(.savedItems, as: [SavedItem].self) { [] }
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.url, "https://example.com")

        store.flush()
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.fileURL(for: .savedItems).path))
    }

    func testCorruptDiskFileFallsBackGracefully() throws {
        let store = BrowserPersistenceStore(directoryURL: tempDir, defaults: defaults)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: store.fileURL(for: .settings))

        let settings = store.load(.settings, as: BrowserSettings.self) { BrowserSettings() }
        XCTAssertEqual(settings, BrowserSettings())
    }

    func testFailingURLStringExtractsFromUserInfoAndIgnoresAboutBlank() {
        let urlError = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorCannotFindHost,
            userInfo: [NSURLErrorFailingURLStringErrorKey: "https://unreachable.example/test"]
        )
        XCTAssertEqual(
            PageLoadErrorKind.failingURLString(from: urlError, fallback: "https://fallback.example"),
            "https://unreachable.example/test"
        )

        let aboutError = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorCancelled,
            userInfo: [NSURLErrorFailingURLStringErrorKey: "about:blank"]
        )
        XCTAssertEqual(
            PageLoadErrorKind.failingURLString(from: aboutError, fallback: "https://fallback.example"),
            "https://fallback.example"
        )
    }

    @MainActor
    func testSessionPromptsRejectBackgroundTabsAndReplaceActivePrompt() {
        let store = BrowserPersistenceStore(directoryURL: tempDir, defaults: defaults)
        let session = BrowserSession(persistence: store)
        let firstTabID = session.activeTabID
        guard let secondTabID = session.createTab(isPrivate: false, select: false) else {
            return XCTFail("Expected second tab creation")
        }

        var bgCalled = false
        let bgDialog = PendingJsDialog(tabID: secondTabID, titleHost: "bg.example", message: "bg") {
            bgCalled = true
        }
        session.presentJsDialog(bgDialog)
        XCTAssertNil(session.activeJsDialog)
        XCTAssertTrue(bgCalled)

        var firstCancelled = false
        let firstDialog = PendingJsDialog(tabID: firstTabID, titleHost: "a.example", message: "1") {
            firstCancelled = true
        }
        let secondDialog = PendingJsDialog(tabID: firstTabID, titleHost: "a.example", message: "2") {}
        session.presentJsDialog(firstDialog)
        session.presentJsDialog(secondDialog)
        XCTAssertTrue(firstCancelled)
        XCTAssertEqual(session.activeJsDialog?.message, "2")

        store.flush()
    }
}
