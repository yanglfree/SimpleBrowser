import XCTest
@testable import ZhuoBrowser

final class InboundSharePolicyTests: XCTestCase {
    func testOnlyExplicitMarketingParametersAreRemoved() throws {
        let request = try XCTUnwrap(
            InboundSharePolicy.create(
                rawURL: "https://example.com/article?utm_source=x&token=secret&sig=a%2Bb#section",
                action: .cleanOpen
            )
        )

        XCTAssertEqual(request.cleanURL, "https://example.com/article?token=secret&sig=a%2Bb#section")
        XCTAssertEqual(request.rawURL, "https://example.com/article?utm_source=x&token=secret&sig=a%2Bb#section")
        XCTAssertEqual(request.removedTrackingParameters, ["utm_source"])
    }

    func testMalformedEncodingIsPreserved() throws {
        let request = try XCTUnwrap(
            InboundSharePolicy.create(
                rawURL: "https://example.com/?bad%ZZ=value&utm_medium=share",
                action: .privateOpen
            )
        )

        XCTAssertEqual(request.cleanURL, "https://example.com/?bad%ZZ=value")
    }

    func testTextExtractionTrimsSentencePunctuation() {
        XCTAssertEqual(
            InboundSharePolicy.extractHTTPURL(from: "See https://example.com/path?q=1。"),
            "https://example.com/path?q=1"
        )
        XCTAssertNil(InboundSharePolicy.extractHTTPURL(from: "not a link"))
        XCTAssertNil(InboundSharePolicy.create(rawURL: "javascript:alert(1)", action: .cleanOpen))
    }

    func testActionAndTitleRoundTripWithoutChangingURL() throws {
        let request = try XCTUnwrap(
            InboundSharePolicy.create(
                rawURL: "https://example.com/?gclid=ad&id=42",
                title: "  Article  ",
                action: .saveArticle,
                id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!,
                createdAt: Date(timeIntervalSince1970: 1)
            )
        )
        let decoded = try JSONDecoder().decode(
            InboundShareRequest.self,
            from: JSONEncoder().encode(request)
        )

        XCTAssertEqual(decoded, request)
        XCTAssertEqual(decoded.title, "Article")
        XCTAssertEqual(decoded.cleanURL, "https://example.com/?id=42")
    }

    func testOriginalActionOnlyAppearsWhenCleaningChangedTheURL() throws {
        let tracked = try XCTUnwrap(
            InboundSharePolicy.create(
                rawURL: "https://example.com/?utm_source=share&id=42",
                action: .cleanOpen
            )
        )
        let clean = try XCTUnwrap(
            InboundSharePolicy.create(
                rawURL: "https://example.com/?id=42",
                action: .cleanOpen
            )
        )

        XCTAssertEqual(
            InboundSharePolicy.availableActions(for: tracked),
            [.cleanOpen, .privateOpen, .readAndClose, .saveArticle, .originalOpen]
        )
        XCTAssertEqual(
            InboundSharePolicy.availableActions(for: clean),
            [.cleanOpen, .privateOpen, .readAndClose, .saveArticle]
        )
    }

    func testActionDispatchMatchesHarmonySemantics() throws {
        let request = try XCTUnwrap(
            InboundSharePolicy.create(
                rawURL: "https://example.com/?utm_source=share&id=42",
                action: .cleanOpen
            )
        )

        XCTAssertFalse(InboundShareAction.cleanOpen.usesPrivateTab)
        XCTAssertTrue(InboundShareAction.privateOpen.usesPrivateTab)
        XCTAssertTrue(InboundShareAction.readAndClose.usesPrivateTab)
        XCTAssertTrue(InboundShareAction.readAndClose.opensDisposableReader)
        XCTAssertTrue(InboundShareAction.saveArticle.requiresPro)
        XCTAssertTrue(InboundShareAction.saveArticle.shouldCaptureArticle)
        XCTAssertEqual(InboundShareAction.cleanOpen.targetURL(in: request), "https://example.com/?id=42")
        XCTAssertEqual(InboundShareAction.originalOpen.targetURL(in: request), request.rawURL)
    }
}
