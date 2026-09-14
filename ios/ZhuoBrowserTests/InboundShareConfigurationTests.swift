import XCTest
@testable import ZhuoBrowser

final class InboundShareConfigurationTests: XCTestCase {
    func testBothTargetsDeclareTheQueueAppGroup() throws {
        let iosDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let paths = [
            "ZhuoBrowser/ZhuoBrowser.entitlements",
            "ZhuoBrowserShareExtension/ZhuoBrowserShareExtension.entitlements"
        ]

        for path in paths {
            let data = try Data(contentsOf: iosDirectory.appendingPathComponent(path))
            let plist = try XCTUnwrap(
                PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            )
            let groups = try XCTUnwrap(plist["com.apple.security.application-groups"] as? [Any])
                .compactMap { $0 as? String }
            XCTAssertEqual(groups, [InboundShareQueue.appGroupIdentifier], path)
        }
    }

    func testHostAppCanRoundTripAQueueRequestInTheSharedContainer() throws {
        let request = try XCTUnwrap(
            InboundSharePolicy.create(
                rawURL: "https://example.com/article?utm_source=simulator&id=42",
                title: "App Group Probe",
                action: .cleanOpen
            )
        )
        defer { try? InboundShareQueue.remove(request) }

        try InboundShareQueue.enqueue(request)
        XCTAssertTrue(try InboundShareQueue.pending().contains(request))
        try InboundShareQueue.remove(request)
        XCTAssertFalse(try InboundShareQueue.pending().contains(request))
    }
}
