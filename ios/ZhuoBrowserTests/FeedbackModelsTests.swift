import XCTest
@testable import ZhuoBrowser

final class FeedbackModelsTests: XCTestCase {
    func testMessageValidationMatchesHarmonyContract() {
        XCTAssertEqual(FeedbackPolicy.validate("1234"), .tooShort)
        XCTAssertNil(FeedbackPolicy.validate("12345"))
        XCTAssertEqual(FeedbackPolicy.validate(String(repeating: "a", count: 1_001)), .tooLong)
    }

    func testPayloadUsesGatewayFieldNamesAndNoPageContent() throws {
        let payload = FeedbackPayload(
            appVersion: "1.2.3",
            message: "Useful feedback",
            contact: "user@example.com",
            allowFollowUp: true,
            metadata: FeedbackMetadata(versionCode: 45, platform: "ios")
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: Any]
        )

        XCTAssertEqual(object["app_id"] as? String, "zhuobrowser")
        XCTAssertEqual(object["package_name"] as? String, "com.youdroid.zhuobrowser")
        XCTAssertEqual(object["client"] as? String, "ios")
        XCTAssertNil(object["url"])
        XCTAssertNil(object["page_content"])
    }

    func testResponseAcceptsSnakeAndCamelCaseIdentifiers() throws {
        let snake = try JSONDecoder().decode(
            FeedbackResponse.self,
            from: Data(#"{"ok":true,"ticket_id":"T-1","request_id":"R-1"}"#.utf8)
        )
        let camel = try JSONDecoder().decode(
            FeedbackResponse.self,
            from: Data(#"{"ok":true,"ticketId":"T-2","requestId":"R-2"}"#.utf8)
        )

        XCTAssertEqual(snake.ticketID, "T-1")
        XCTAssertEqual(snake.requestID, "R-1")
        XCTAssertEqual(camel.ticketID, "T-2")
        XCTAssertEqual(camel.requestID, "R-2")
    }
}
