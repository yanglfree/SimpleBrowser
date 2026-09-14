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
}
