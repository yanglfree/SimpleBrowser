import XCTest
@testable import ZhuoBrowser

final class DownloadPolicyTests: XCTestCase {
    func testWifiOnlyBlocksNonWifiEvenAfterLargeFileApproval() {
        XCTAssertEqual(
            DownloadPolicy.reason(
                wifiOnly: true,
                isWifiConnected: false,
                isApproved: true,
                totalBytes: 100 * 1_024 * 1_024,
                largeFileThresholdMB: 50
            ),
            .wifiRequired
        )
    }

    func testLargeFilePromptsOnCellularAndApprovalBypassesIt() {
        XCTAssertEqual(
            DownloadPolicy.reason(
                wifiOnly: false,
                isWifiConnected: false,
                isApproved: false,
                totalBytes: 50 * 1_024 * 1_024,
                largeFileThresholdMB: 50
            ),
            .largeFile
        )
        XCTAssertNil(
            DownloadPolicy.reason(
                wifiOnly: false,
                isWifiConnected: false,
                isApproved: true,
                totalBytes: 50 * 1_024 * 1_024,
                largeFileThresholdMB: 50
            )
        )
    }

    func testUnknownLengthDoesNotTriggerLargeFilePrompt() {
        XCTAssertNil(
            DownloadPolicy.reason(
                wifiOnly: false,
                isWifiConnected: false,
                isApproved: false,
                totalBytes: -1,
                largeFileThresholdMB: 50
            )
        )
    }

    func testRestoreReconcilesInterruptedAndMissingTasks() {
        XCTAssertEqual(
            DownloadPolicy.restoredStatus(.downloading, path: "", fileExists: { _ in false }).status,
            .failed
        )
        let missing = DownloadPolicy.restoredStatus(.completed, path: "/missing", fileExists: { _ in false })
        XCTAssertEqual(missing.status, .failed)
        XCTAssertEqual(missing.error, "missing")
        XCTAssertEqual(
            DownloadPolicy.restoredStatus(.completed, path: "/exists", fileExists: { _ in true }).status,
            .completed
        )
    }

    func testLegacyDownloadTaskDecodesNewProgressFieldsSafely() throws {
        let data = #"{"id":"1","fileName":"file.pdf","url":"https://example.com/file.pdf","status":"failed","error":"interrupted","path":""}"#.data(using: .utf8)!

        let task = try JSONDecoder().decode(DownloadTask.self, from: data)

        XCTAssertEqual(task.progress, 0)
        XCTAssertEqual(task.receivedBytes, 0)
        XCTAssertEqual(task.totalBytes, -1)
        XCTAssertEqual(task.attempts, 0)
        XCTAssertNil(task.resumeData)
    }
}
