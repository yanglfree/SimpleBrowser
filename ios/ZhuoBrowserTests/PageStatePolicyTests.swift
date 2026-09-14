import XCTest
@testable import ZhuoBrowser

final class PageStatePolicyTests: XCTestCase {
    func testResumeWindowRequiresARecentPositivePosition() {
        let now: TimeInterval = 10_000_000

        XCTAssertTrue(PageStatePolicy.shouldOfferResume(position: 420, savedAt: now - 60, now: now))
        XCTAssertTrue(
            PageStatePolicy.shouldOfferResume(
                position: 1,
                savedAt: now - PageStatePolicy.resumeWindow,
                now: now
            )
        )
        XCTAssertFalse(PageStatePolicy.shouldOfferResume(position: 0, savedAt: now - 60, now: now))
        XCTAssertFalse(
            PageStatePolicy.shouldOfferResume(
                position: 420,
                savedAt: now - PageStatePolicy.resumeWindow - 1,
                now: now
            )
        )
        XCTAssertFalse(PageStatePolicy.shouldOfferResume(position: 420, savedAt: now + 1, now: now))
    }

    func testPageIdentityIgnoresFragmentAndNormalizesHostAndRootPath() {
        XCTAssertTrue(PageStatePolicy.isSamePage("https://EXAMPLE.com", "https://example.com/#details"))
        XCTAssertFalse(PageStatePolicy.isSamePage("https://example.com/?a=1", "https://example.com/?a=2"))
    }

    func testFormDraftNormalizationRejectsInvalidAndCapsFields() throws {
        XCTAssertEqual(PageStatePolicy.normalizedFormDraft("not-json"), "")
        XCTAssertEqual(PageStatePolicy.normalizedFormDraft("[]"), "")

        let source = (0..<100).map { index in
            ["key": "field-\(index)", "value": "value-\(index)"]
        }
        let raw = String(decoding: try JSONSerialization.data(withJSONObject: source), as: UTF8.self)
        let normalized = PageStatePolicy.normalizedFormDraft(raw)
        let data = try XCTUnwrap(normalized.data(using: .utf8))
        let decoded = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: String]])

        XCTAssertEqual(decoded.count, PageStatePolicy.maximumDraftFields)
        XCTAssertEqual(decoded.first?["key"], "field-0")
        XCTAssertEqual(decoded.last?["key"], "field-79")
    }

    func testRestoreScriptsClampScrollAndParseEncodedDraft() {
        XCTAssertEqual(PageStatePolicy.restoreScrollScript(position: -5), "window.scrollTo(0, 0); 'restored';")

        let draft = #"[{"key":"message","value":"hello \"reader\""}]"#
        let script = PageStatePolicy.restoreFormDraftScript(draft)

        XCTAssertNotNil(script)
        XCTAssertTrue(script?.contains("JSON.parse") == true)
        XCTAssertTrue(script?.contains("dispatchEvent(new Event('input'") == true)
    }

    func testWatcherDebouncesDraftMessagesAndExcludesPasswords() {
        XCTAssertTrue(PageStatePolicy.captureFormDraftScript.contains("type=\"password\""))
        XCTAssertTrue(PageStatePolicy.captureFormDraftScript.contains("type=\"hidden\""))
        XCTAssertTrue(PageStatePolicy.captureFormDraftScript.contains("type=\"file\""))
        XCTAssertTrue(PageStatePolicy.captureFormDraftScript.contains("one-time-code"))
        XCTAssertTrue(PageStatePolicy.captureFormDraftScript.contains("autocomplete.indexOf('cc-')"))
        XCTAssertTrue(PageStatePolicy.formDraftWatcherScript.contains("window.setTimeout(publish, 250)"))
        XCTAssertTrue(PageStatePolicy.formDraftWatcherScript.contains("url: window.location.href"))
        XCTAssertTrue(PageStatePolicy.formDraftWatcherScript.contains(PageStatePolicy.messageHandlerName))
    }
}
