import XCTest
@testable import ZhuoBrowser

final class FilterListCompilerTests: XCTestCase {
    func testCompilesSupportedNetworkAndCosmeticRules() throws {
        let source = """
        ! title
        ||ads.example.com^
        ||cdn.example.com^/ads/*/creative.js
        example.com,news.example##.sponsor
        """

        let compiled = try FilterListCompiler.compile(source)
        let rules = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(compiled.json.utf8)) as? [[String: Any]]
        )

        XCTAssertEqual(compiled.count, 3)
        XCTAssertEqual(compiled.networkCount, 2)
        XCTAssertEqual(compiled.cosmeticCount, 1)
        XCTAssertEqual(compiled.skippedCount, 0)
        XCTAssertFalse(compiled.truncated)
        XCTAssertEqual((rules[0]["action"] as? [String: String])?["type"], "block")
        let firstTrigger = try XCTUnwrap(rules[0]["trigger"] as? [String: Any])
        XCTAssertEqual(
            firstTrigger["url-filter"] as? String,
            "^https?://([^/]*\\.)?ads\\.example\\.com([:/].*)?"
        )
        let secondTrigger = try XCTUnwrap(rules[1]["trigger"] as? [String: Any])
        XCTAssertEqual(
            secondTrigger["url-filter"] as? String,
            "^https?://([^/]*\\.)?cdn\\.example\\.com/ads/.*/creative\\.js"
        )
        let cosmeticTrigger = try XCTUnwrap(rules[2]["trigger"] as? [String: Any])
        XCTAssertEqual(cosmeticTrigger["if-domain"] as? [String], ["*example.com", "*news.example"])
    }

    func testSkipsExceptionsOptionsAndInvalidHosts() throws {
        let source = """
        @@||allowed.example^
        ||script.example^$script
        ||bad..example^
        /regex/
        """

        let compiled = try FilterListCompiler.compile(source)

        XCTAssertEqual(compiled.count, 0)
        XCTAssertEqual(compiled.skippedCount, 4)
    }

    func testNetworkRulesTakePriorityAtTheRuleLimit() throws {
        let source = """
        example.com##.sponsor
        ||first.example^
        ||second.example^
        """

        let compiled = try FilterListCompiler.compile(source, maximumRules: 2)
        let rules = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(compiled.json.utf8)) as? [[String: Any]]
        )

        XCTAssertEqual(compiled.count, 2)
        XCTAssertTrue(compiled.truncated)
        XCTAssertTrue(rules.allSatisfy { ($0["action"] as? [String: String])?["type"] == "block" })
    }

    func testRemoteUpdateIntervalMatchesHarmonyThreeDayPolicy() {
        let now = Date(timeIntervalSince1970: 1_000_000)

        XCTAssertTrue(RemoteRuleStore.shouldUpdate(lastUpdatedAt: 0, now: now))
        XCTAssertFalse(
            RemoteRuleStore.shouldUpdate(
                lastUpdatedAt: now.timeIntervalSince1970 - RemoteRuleStore.updateInterval + 1,
                now: now
            )
        )
        XCTAssertTrue(
            RemoteRuleStore.shouldUpdate(
                lastUpdatedAt: now.timeIntervalSince1970 - RemoteRuleStore.updateInterval,
                now: now
            )
        )
    }
}
