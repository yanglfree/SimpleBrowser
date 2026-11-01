import AppKit
import SwiftUI
import XCTest
@testable import ZhuoBrowserMac

@MainActor
final class DownloadTests: XCTestCase {

    func testOnDemandToolbarVisibilityFollowsSafariLifecycle() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZhuoDownloadTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let manager = DownloadManager(
            storageFileURL: tempDir.appendingPathComponent("downloads.json"),
            downloadsDirectoryProvider: { tempDir },
            autoOpenPopoverOnNewDownload: false
        )

        // 1. Initially hidden when there are no downloads and popover is closed
        XCTAssertFalse(manager.shouldShowToolbarButton)
        XCTAssertNil(manager.overallProgress)

        // 2. Appears as soon as a download starts
        let activeItem = DownloadItem(
            id: "dl-1",
            sourceURL: "https://example.com/cap_disRelease.p7b",
            filename: "cap_disRelease.p7b",
            destinationPath: tempDir.appendingPathComponent("cap_disRelease.p7b").path,
            receivedBytes: 2048,
            totalBytes: 4096,
            state: .downloading
        )
        manager.recordDownloadItem(activeItem, openPopover: true)

        XCTAssertTrue(manager.shouldShowToolbarButton)
        XCTAssertTrue(manager.isShowingPopover)
        XCTAssertEqual(manager.activeDownloadsCount, 1)
        XCTAssertEqual(manager.overallProgress ?? 0, 0.5, accuracy: 0.01)

        // 3. When download finishes, button stays visible until user clears it
        var finishedItem = activeItem
        finishedItem.receivedBytes = 4096
        finishedItem.state = .completed
        manager.recordDownloadItem(finishedItem)

        XCTAssertTrue(manager.shouldShowToolbarButton)
        XCTAssertTrue(manager.hasClearableItems)
        XCTAssertNil(manager.overallProgress)

        // 4. Clicking "清除" clears completed items, closes popover, and hides toolbar button
        manager.clearCompletedDownloads()
        XCTAssertTrue(manager.items.isEmpty)
        XCTAssertFalse(manager.isShowingPopover)
        XCTAssertFalse(manager.shouldShowToolbarButton)
    }

    func testUniqueDestinationURLAvoidsOverwritingExistingFiles() {
        let dir = URL(fileURLWithPath: "/tmp/downloads", isDirectory: true)
        let existing: Set<String> = [
            "/tmp/downloads/sticker-2026-10-31-06.png",
            "/tmp/downloads/sticker-2026-10-31-06 (1).png"
        ]

        let resolved = DownloadPolicy.uniqueDestinationURL(
            in: dir,
            suggestedFilename: "sticker-2026-10-31-06.png",
            fileExists: { existing.contains($0) }
        )

        XCTAssertEqual(resolved.lastPathComponent, "sticker-2026-10-31-06 (2).png")
    }

    func testAttachmentAndMIMETypeDownloadDetection() {
        let url = URL(string: "https://example.com/cap_disRelease.p7b")!
        let attachmentResponse = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": "text/plain",
                "Content-Disposition": "attachment; filename=\"cap_disRelease.p7b\""
            ]
        )
        XCTAssertTrue(DownloadPolicy.shouldDownloadResponse(attachmentResponse, canShowMIMEType: true))

        let inlineHTMLResponse = HTTPURLResponse(
            url: URL(string: "https://example.com/index.html")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/html"]
        )
        XCTAssertFalse(DownloadPolicy.shouldDownloadResponse(inlineHTMLResponse, canShowMIMEType: true))
        XCTAssertTrue(DownloadPolicy.shouldDownloadResponse(inlineHTMLResponse, canShowMIMEType: false))
    }

    func testByteCountFormattingMatchesSafariStyle() {
        XCTAssertEqual(DownloadPolicy.formatByteCount(4096), "4 KB")
        XCTAssertEqual(DownloadPolicy.formatByteCount(129 * 1024), "129 KB")
        XCTAssertEqual(DownloadPolicy.formatByteCount(Int64(2.5 * 1024 * 1024)), "2.5 MB")
    }

    func testLibraryTogglePopoverAndDownloadsPopoverHosting() {
        let session = BrowserSession()
        XCTAssertFalse(session.isShowingLibraryManager)

        session.toggleLibrary(tabIndex: 0)
        XCTAssertTrue(session.isShowingLibraryManager)
        XCTAssertEqual(session.librarySelectedTab, 0)

        session.toggleLibrary(tabIndex: 1)
        XCTAssertTrue(session.isShowingLibraryManager)
        XCTAssertEqual(session.librarySelectedTab, 1)

        session.toggleLibrary(tabIndex: 1)
        XCTAssertFalse(session.isShowingLibraryManager)

        let downloadsView = DownloadsPopoverView(downloadManager: DownloadManager.shared, session: session)
        let hosting = NSHostingView(rootView: downloadsView)
        hosting.frame = NSRect(x: 0, y: 0, width: 336, height: 240)
        hosting.layoutSubtreeIfNeeded()
        XCTAssertNotNil(hosting)
    }
}
