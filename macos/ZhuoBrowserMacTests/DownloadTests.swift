import AppKit
import SwiftUI
import WebKit
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

    func testDownloadStatusTextWithUnknownTotalSize() {
        let item = DownloadItem(
            id: "dl-unknown",
            sourceURL: "https://example.com/stream",
            filename: "stream.bin",
            destinationPath: "/tmp/stream.bin",
            receivedBytes: 2048,
            totalBytes: -1,
            state: .downloading
        )
        XCTAssertEqual(item.statusText, "已下载 2 KB")
        XCTAssertNil(item.progress)
    }

    func testDirectDownloadStreamsProgressAndCompletes() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZhuoDirectDownloadTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceFile = tempDir.appendingPathComponent("source.data")
        let testData = Data(repeating: 0xAB, count: 64 * 1024)
        try? testData.write(to: sourceFile)

        let targetDir = tempDir.appendingPathComponent("target", isDirectory: true)

        let manager = DownloadManager(
            storageFileURL: tempDir.appendingPathComponent("downloads.json"),
            downloadsDirectoryProvider: { targetDir },
            autoOpenPopoverOnNewDownload: false
        )

        manager.startDirectDownload(from: sourceFile, suggestedFilename: "output.data")

        let exp = expectation(description: "Direct download finishes")
        let startTime = Date()

        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { timer in
            Task { @MainActor in
                if let item = manager.items.first(where: { $0.filename == "output.data" }) {
                    if item.state == .completed {
                        timer.invalidate()
                        XCTAssertEqual(item.receivedBytes, 64 * 1024)
                        XCTAssertEqual(item.totalBytes, 64 * 1024)
                        XCTAssertTrue(FileManager.default.fileExists(atPath: item.destinationPath))
                        exp.fulfill()
                    } else if item.state == .failed || item.state == .cancelled {
                        timer.invalidate()
                        XCTFail("Download failed with: \(item.errorMessage ?? "unknown")")
                        exp.fulfill()
                    }
                }
                if Date().timeIntervalSince(startTime) > 5.0 {
                    timer.invalidate()
                    XCTFail("Download timed out")
                    exp.fulfill()
                }
            }
        }

        wait(for: [exp], timeout: 6.0)
    }

    func testDirectDownloadCancellation() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZhuoDirectCancelTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let targetDir = tempDir.appendingPathComponent("target", isDirectory: true)

        let manager = DownloadManager(
            storageFileURL: tempDir.appendingPathComponent("downloads.json"),
            downloadsDirectoryProvider: { targetDir },
            autoOpenPopoverOnNewDownload: false
        )

        let fakeURL = URL(string: "https://example.invalid/largefile.iso")!
        manager.startDirectDownload(from: fakeURL, suggestedFilename: "largefile.iso")

        guard let item = manager.items.first else {
            XCTFail("Item should exist")
            return
        }

        XCTAssertEqual(item.state, .downloading)
        manager.cancelDownload(id: item.id)

        XCTAssertEqual(manager.items.first?.state, .cancelled)
    }

    func testTransientDownloadTabDetectionAndSilentClose() {
        XCTAssertTrue(
            TabController.shouldCloseTransientDownloadTab(
                hasCommittedNavigation: false,
                canGoBack: false,
                backListEmpty: true,
                hasCurrentBackForwardItem: false
            )
        )
        XCTAssertFalse(
            TabController.shouldCloseTransientDownloadTab(
                hasCommittedNavigation: true,
                canGoBack: false,
                backListEmpty: true,
                hasCurrentBackForwardItem: true
            )
        )
        XCTAssertFalse(
            TabController.shouldCloseTransientDownloadTab(
                hasCommittedNavigation: false,
                canGoBack: true,
                backListEmpty: false,
                hasCurrentBackForwardItem: true
            )
        )

        let session = BrowserSession()
        let originalTab = session.createTab(url: "https://developer.huawei.com", select: true)
        let downloadTab = session.createTab(url: "https://nsp-appgallery.example.com/app.p7b", select: true)
        XCTAssertEqual(session.activeTabID, downloadTab.id)

        session.closeTab(id: downloadTab.id, recordHistory: false)
        XCTAssertEqual(session.activeTabID, originalTab.id)
        XCTAssertFalse(session.canReopenClosedTab)
    }

    func testPDFDocumentDetectionAndContextMenuItems() {
        XCTAssertTrue(TabController.isPDFDocument(mimeType: "application/pdf", url: URL(string: "https://example.com/file")))
        XCTAssertTrue(TabController.isPDFDocument(mimeType: nil, url: URL(string: "https://example.com/spec.PDF")))
        XCTAssertFalse(TabController.isPDFDocument(mimeType: "text/html", url: URL(string: "https://example.com/index.html")))

        let session = BrowserSession()
        _ = session.createTab(url: "https://example.com/manual.pdf", select: true)
        guard let controller = session.activeController else {
            XCTFail("Active controller should exist")
            return
        }
        let webView = controller.webView as? BrowserWKWebView
        XCTAssertNotNil(webView)
        XCTAssertTrue(controller.isCurrentDocumentPDF)

        let menu = NSMenu()
        let dummyEvent = NSEvent.mouseEvent(
            with: .rightMouseDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1.0
        )!
        webView?.willOpenMenu(menu, with: dummyEvent)
        XCTAssertTrue(menu.items.contains { $0.title == "下载 PDF" })
        XCTAssertTrue(menu.items.contains { $0.title == "存储 PDF 为..." })

        // Calling willOpenMenu again should not duplicate items
        let countBefore = menu.items.count
        webView?.willOpenMenu(menu, with: dummyEvent)
        XCTAssertEqual(menu.items.count, countBefore)
    }

    func testQuarantineFlagParsingDetectsHardQuarantine() {
        for hardAttr in [
            "0287;6b04ee08;ZhuoBrowserMac;",
            "0387;6b0420e6;ZhuoBrowserMac;",
            "0087;6ae99321;com.apple.WebKit.Networking;"
        ] {
            let parsed = DownloadFileFinalizer.parseQuarantineFlags(hardAttr)
            XCTAssertNotNil(parsed)
            XCTAssertTrue(DownloadFileFinalizer.isHardQuarantineFlags(parsed ?? 0))
        }

        for cleanAttr in [
            "0283;6b04eeb7;ZhuoBrowserMac;A96B336A-6E02-4ED1-B352-D28FF7C2766F",
            "0083;6a4646b1;Safari;8F36DD39-D7F2-4526-B7E9-6854DDCA7510",
            "0082;6b04ee08;ZhuoBrowserMac;",
            "0081;690342de;Edge;6ED88827-1F3B-4563-9102-9C121D733514"
        ] {
            let parsed = DownloadFileFinalizer.parseQuarantineFlags(cleanAttr)
            XCTAssertNotNil(parsed)
            XCTAssertFalse(DownloadFileFinalizer.isHardQuarantineFlags(parsed ?? 0))
        }

        XCTAssertNil(DownloadFileFinalizer.parseQuarantineFlags(""))
        XCTAssertNil(DownloadFileFinalizer.parseQuarantineFlags(";6b04ee08;Safari;"))
        XCTAssertNil(DownloadFileFinalizer.parseQuarantineFlags("not-hex;6b04ee08;Safari;"))
    }

    func testMaterializeFileStreamsMultiChunkPayloadAndCleansStaging() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZhuoMaterializeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Multi-chunk (> 1 MB) payload
        var largePayload = Data(count: 1_600_000)
        for index in largePayload.indices {
            largePayload[index] = UInt8((index * 31) & 0xFF)
        }
        let largeStagingURL = tempDir.appendingPathComponent("large.part")
        let largeDestURL = tempDir.appendingPathComponent("out/large.dmg")
        try largePayload.write(to: largeStagingURL)

        let bytesWritten = try DownloadFileFinalizer.materializeFile(
            from: largeStagingURL,
            to: largeDestURL,
            removeSource: true
        )
        XCTAssertEqual(bytesWritten, Int64(largePayload.count))
        XCTAssertFalse(FileManager.default.fileExists(atPath: largeStagingURL.path))
        XCTAssertEqual(try Data(contentsOf: largeDestURL), largePayload)
        XCTAssertFalse(DownloadFileFinalizer.hasHardQuarantineFlag(at: largeDestURL))

        // 0-byte payload
        let emptyStagingURL = tempDir.appendingPathComponent("empty.part")
        let emptyDestURL = tempDir.appendingPathComponent("out/empty.bin")
        try Data().write(to: emptyStagingURL)

        let emptyBytesWritten = try DownloadFileFinalizer.materializeFile(
            from: emptyStagingURL,
            to: emptyDestURL,
            removeSource: true
        )
        XCTAssertEqual(emptyBytesWritten, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: emptyStagingURL.path))
        XCTAssertEqual(try Data(contentsOf: emptyDestURL), Data())
        XCTAssertFalse(DownloadFileFinalizer.hasHardQuarantineFlag(at: emptyDestURL))
    }

    func testWKDownloadMaterializesCleanFileWithoutHardQuarantine() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZhuoWKDownloadCleanTests-\(UUID().uuidString)", isDirectory: true)
        let downloadsDir = tempDir.appendingPathComponent("downloads", isDirectory: true)
        let stagingDir = tempDir.appendingPathComponent("staging", isDirectory: true)
        try FileManager.default.createDirectory(at: downloadsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let manager = DownloadManager(
            storageFileURL: tempDir.appendingPathComponent("downloads.json"),
            downloadsDirectoryProvider: { downloadsDir },
            stagingDirectoryProvider: { stagingDir },
            autoOpenPopoverOnNewDownload: false
        )

        let payload = Data("ZhuoBrowserMac clean download payload".utf8)
        let dataURL = URL(string: "data:application/octet-stream;base64,\(payload.base64EncodedString())")!
        let webView = WKWebView(frame: .zero)
        let exp = expectation(description: "WKDownload materializes without hard quarantine")

        webView.startDownload(using: URLRequest(url: dataURL)) { wkDownload in
            MainActor.assumeIsolated {
                manager.handleWebKitDownload(
                    wkDownload,
                    fallbackURL: dataURL,
                    originURL: URL(string: "https://example.com/downloads")
                )
            }
        }

        let startTime = Date()
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { timer in
            Task { @MainActor in
                if let item = manager.items.first {
                    if item.state == .completed {
                        timer.invalidate()
                        let destURL = URL(fileURLWithPath: item.destinationPath)
                        XCTAssertEqual(try? Data(contentsOf: destURL), payload)
                        XCTAssertEqual(item.receivedBytes, Int64(payload.count))
                        XCTAssertEqual(item.totalBytes, Int64(payload.count))
                        XCTAssertFalse(DownloadFileFinalizer.hasHardQuarantineFlag(at: destURL))
                        let remainingStaging = (try? FileManager.default.contentsOfDirectory(atPath: stagingDir.path)) ?? []
                        XCTAssertTrue(remainingStaging.isEmpty, "Staging directory should be empty after finalization, found: \(remainingStaging)")
                        exp.fulfill()
                    } else if item.state == .failed || item.state == .cancelled {
                        timer.invalidate()
                        XCTFail("WKDownload failed with: \(item.errorMessage ?? "unknown")")
                        exp.fulfill()
                    }
                }
                if Date().timeIntervalSince(startTime) > 8.0 {
                    timer.invalidate()
                    XCTFail("WKDownload timed out")
                    exp.fulfill()
                }
            }
        }

        wait(for: [exp], timeout: 10.0)
    }

    func testSandboxBundleDoesNotEnableProcessWideLSFileQuarantine() {
        let appBundle = Bundle(for: DownloadManager.self)
        let lsFileQuarantine = appBundle.object(forInfoDictionaryKey: "LSFileQuarantineEnabled") as? Bool
        XCTAssertNotEqual(lsFileQuarantine, true)
    }
}
