import XCTest
@testable import ZhuoBrowserMac

final class SingleInstanceGuardTests: XCTestCase {

    func testExtractURLsFromArguments() {
        let args = [
            "/Applications/ZhuoBrowserMac.app/Contents/MacOS/ZhuoBrowserMac",
            "-ApplePersistenceIgnoreState",
            "YES",
            "-NSDocumentRevisionsDebugMode",
            "YES",
            "https://zhuobrowser.org",
            "https://github.com/youdroid/zhuobrowser",
            "zhuo://home"
        ]

        let extracted = SingleInstanceGuard.extractURLs(from: args)
        XCTAssertEqual(extracted.count, 3)
        XCTAssertEqual(extracted[0], "https://zhuobrowser.org")
        XCTAssertEqual(extracted[1], "https://github.com/youdroid/zhuobrowser")
        XCTAssertEqual(extracted[2], "zhuo://home")
    }

    func testExtractURLsEmptyWhenOnlyFlags() {
        let args = [
            "/Applications/ZhuoBrowserMac.app/Contents/MacOS/ZhuoBrowserMac",
            "-NSDocumentRevisionsDebugMode",
            "YES"
        ]
        let extracted = SingleInstanceGuard.extractURLs(from: args)
        XCTAssertTrue(extracted.isEmpty)
    }

    func testFileLockAcquisitionAndMutualExclusion() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SingleInstanceGuardTests_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let lockURL = tempDir.appendingPathComponent(".test.lock")

        let guard1 = SingleInstanceGuard()
        let guard2 = SingleInstanceGuard()

        // First instance acquires lock
        let acquired1 = guard1.acquireLock(customLockURL: lockURL, currentPID: 12345)
        XCTAssertTrue(acquired1, "Primary guard should successfully acquire lock")

        // Second instance tries to acquire same lock
        let acquired2 = guard2.acquireLock(customLockURL: lockURL, currentPID: 54321)
        XCTAssertFalse(acquired2, "Secondary guard should fail to acquire lock while primary holds it")

        // Primary releases lock
        guard1.releaseLock()

        // Now second instance can acquire lock
        let acquiredAfterRelease = guard2.acquireLock(customLockURL: lockURL, currentPID: 54321)
        XCTAssertTrue(acquiredAfterRelease, "Secondary guard should acquire lock once primary releases it")
        guard2.releaseLock()
    }

    @MainActor
    func testOpenExternalURLNavigatesOrOpensTab() {
        let session = BrowserSession.shared
        session.tabs.removeAll()
        session.createTab(url: "zhuo://home", select: true)

        // When active tab is on home, openExternalURL should navigate existing tab
        session.openExternalURL("https://example.com/test1")
        XCTAssertEqual(session.tabs.count, 1)
        XCTAssertEqual(session.activeTab?.url, "https://example.com/test1")

        // When active tab is on a web page, openExternalURL should create a new tab
        session.openExternalURL("https://example.com/test2")
        XCTAssertEqual(session.tabs.count, 2)
        XCTAssertEqual(session.activeTab?.url, "https://example.com/test2")
    }
}
