import XCTest
@testable import ZhuoBrowser

final class BlockingPolicyTests: XCTestCase {
    func testObservedResourcesAreSanitizedTypedAndBounded() {
        let payload: [[String: Any]] = (0..<60).map { index in
            [
                "url": "https://Resource\(index).Example/path?secret=value",
                "category": index.isMultiple(of: 2) ? "tracker" : "malicious"
            ]
        } + [
            ["url": "javascript:alert(1)", "category": "tracker"],
            ["url": "https://ignored.example", "category": "unknown"]
        ]

        let resources = BlockObservationPolicy.resources(from: payload)

        XCTAssertEqual(resources.count, BlockObservationPolicy.maximumResourceDetails)
        XCTAssertEqual(resources.first, ObservedBlockResource(host: "resource0.example", category: .tracker))
        XCTAssertEqual(resources.last, ObservedBlockResource(host: "resource49.example", category: .malicious))
    }

    func testEventDraftsKeepResourceDetailsAndAggregateOnlyTheRemainder() {
        let drafts = BlockObservationPolicy.eventDrafts(
            stats: BlockStats(ads: 1, trackers: 3, malicious: 2, popups: 2),
            resources: [
                ObservedBlockResource(host: "analytics.example", category: .tracker),
                ObservedBlockResource(host: "phishing.example", category: .malicious)
            ]
        )

        XCTAssertEqual(
            Array(drafts.prefix(2)),
            [
                BlockEventDraft(
                    category: .tracker,
                    count: 1,
                    resourceHost: "analytics.example",
                    engine: .resourceCleanup
                ),
                BlockEventDraft(
                    category: .malicious,
                    count: 1,
                    resourceHost: "phishing.example",
                    engine: .resourceCleanup
                )
            ]
        )
        XCTAssertEqual(drafts.reduce(0) { $0 + $1.count }, 8)
        XCTAssertEqual(
            drafts.filter { $0.resourceHost == nil }.map { [$0.category.rawValue, $0.count] },
            [[BlockCategory.advertisement.rawValue, 1], [BlockCategory.tracker.rawValue, 2],
             [BlockCategory.malicious.rawValue, 1], [BlockCategory.popup.rawValue, 2]]
        )
        XCTAssertTrue(
            BlockObservationPolicy.eventDrafts(
                stats: BlockStats(),
                resources: [ObservedBlockResource(host: "unexpected.example", category: .tracker)]
            ).isEmpty
        )
    }

    func testVisibleEventsStayTabScopedPositiveRecentAndBounded() {
        let now = Date(timeIntervalSince1970: 100)
        let events = [
            BlockEvent(
                id: "older",
                tabID: "active",
                pageURL: "https://example.com/old",
                category: .advertisement,
                count: 1,
                occurredAt: now.addingTimeInterval(-2)
            ),
            BlockEvent(
                id: "other-tab",
                tabID: "other",
                pageURL: "https://example.com/other",
                category: .tracker,
                count: 3,
                occurredAt: now.addingTimeInterval(2)
            ),
            BlockEvent(
                id: "invalid",
                tabID: "active",
                pageURL: "https://example.com/invalid",
                category: .popup,
                count: 0,
                occurredAt: now.addingTimeInterval(1)
            ),
            BlockEvent(
                id: "newer",
                tabID: "active",
                pageURL: "https://example.com/new",
                category: .cookieBanner,
                count: 2,
                occurredAt: now
            )
        ]

        XCTAssertEqual(
            BlockEventPresentationPolicy.visibleEvents(events, tabID: "active", limit: 1).map(\.id),
            ["newer"]
        )
        XCTAssertTrue(BlockEventPresentationPolicy.visibleEvents(events, tabID: "active", limit: 0).isEmpty)
    }

    func testEffectiveControlInheritsGlobalAndResolvesOverrides() {
        let settings = BrowserSettings(
            blockAds: true,
            siteControls: [
                SiteControl(
                    host: "Example.COM",
                    networkBlocking: .disabled,
                    trackerBlocking: .enabled,
                    cosmeticCleanup: .inherit,
                    autoReader: .enabled,
                    darkMode: .disabled,
                    desktopUserAgent: .enabled
                )
            ]
        )

        XCTAssertEqual(
            BlockingPolicy.effectiveControl(for: "https://example.com/article", settings: settings),
            EffectiveSiteControl(
                networkBlockingEnabled: false,
                trackerBlockingEnabled: true,
                cosmeticCleanupEnabled: true,
                autoReaderEnabled: true,
                webDarkMode: .light,
                desktopUserAgentEnabled: true
            )
        )
        XCTAssertEqual(
            BlockingPolicy.effectiveControl(for: "https://other.example", settings: settings),
            EffectiveSiteControl(
                networkBlockingEnabled: true,
                trackerBlockingEnabled: true,
                cosmeticCleanupEnabled: true,
                autoReaderEnabled: false,
                webDarkMode: .system,
                desktopUserAgentEnabled: false
            )
        )
    }

    func testSiteControlDecodesLegacyDisplayFieldsAsInherited() throws {
        let data = #"{"host":"example.com","networkBlocking":2,"trackerBlocking":1,"cosmeticCleanup":0,"autoReader":1}"#
            .data(using: .utf8)!

        let control = try JSONDecoder().decode(SiteControl.self, from: data)

        XCTAssertEqual(control.darkMode, .inherit)
        XCTAssertEqual(control.desktopUserAgent, .inherit)
        XCTAssertTrue(control.hasOverride)
    }

    func testNormalizationDropsInheritedControlsAndMergesObservedStats() {
        let controls = BlockingPolicy.normalizedSiteControls([
            SiteControl(host: "unused.example"),
            SiteControl(host: "Example.COM", trackerBlocking: .disabled)
        ])
        XCTAssertEqual(controls, [SiteControl(host: "example.com", trackerBlocking: .disabled)])

        let stats = BlockingPolicy.normalizedSiteStats([
            SiteBlockStats(host: "Example.COM", stats: BlockStats(ads: 2, trackers: 1, malicious: 5)),
            SiteBlockStats(host: "example.com", stats: BlockStats(popups: 3, cookieBanners: 4))
        ])
        XCTAssertEqual(
            stats,
            [SiteBlockStats(
                host: "example.com",
                stats: BlockStats(ads: 2, trackers: 1, malicious: 5, popups: 3, cookieBanners: 4)
            )]
        )
        XCTAssertEqual(
            BlockingPolicy.cumulativeStats([
                SiteBlockStats(host: "example.com", stats: BlockStats(ads: 2, trackers: 1)),
                SiteBlockStats(host: "other.example", stats: BlockStats(ads: -5, malicious: 4, popups: 3))
            ]),
            BlockStats(ads: 2, trackers: 1, malicious: 4, popups: 3, cookieBanners: 0)
        )
    }

    func testBlockStatsOnlyAddsNonnegativeCounts() {
        var stats = BlockStats(ads: 1)
        stats.add(BlockStats(ads: -3, trackers: 2, malicious: 3, popups: 4, cookieBanners: -1))

        XCTAssertEqual(stats, BlockStats(ads: 1, trackers: 2, malicious: 3, popups: 4, cookieBanners: 0))
        XCTAssertEqual(stats.total, 10)
    }

    func testLegacyBlockStatsDecodeMissingMaliciousCountAsZero() throws {
        let legacy = #"{"ads":2,"trackers":1,"popups":3,"cookieBanners":4}"#.data(using: .utf8)!
        let restored = try JSONDecoder().decode(BlockStats.self, from: legacy)

        XCTAssertEqual(restored, BlockStats(ads: 2, trackers: 1, malicious: 0, popups: 3, cookieBanners: 4))
    }
}
