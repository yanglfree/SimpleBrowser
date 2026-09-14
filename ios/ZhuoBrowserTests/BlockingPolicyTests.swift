import XCTest
@testable import ZhuoBrowser

final class BlockingPolicyTests: XCTestCase {
    func testEffectiveControlInheritsGlobalAndResolvesOverrides() {
        let settings = BrowserSettings(
            blockAds: true,
            siteControls: [
                SiteControl(
                    host: "Example.COM",
                    networkBlocking: .disabled,
                    trackerBlocking: .enabled,
                    cosmeticCleanup: .inherit,
                    autoReader: .enabled
                )
            ]
        )

        XCTAssertEqual(
            BlockingPolicy.effectiveControl(for: "https://example.com/article", settings: settings),
            EffectiveSiteControl(
                networkBlockingEnabled: false,
                trackerBlockingEnabled: true,
                cosmeticCleanupEnabled: true,
                autoReaderEnabled: true
            )
        )
        XCTAssertEqual(
            BlockingPolicy.effectiveControl(for: "https://other.example", settings: settings),
            EffectiveSiteControl(
                networkBlockingEnabled: true,
                trackerBlockingEnabled: true,
                cosmeticCleanupEnabled: true,
                autoReaderEnabled: false
            )
        )
    }

    func testNormalizationDropsInheritedControlsAndMergesObservedStats() {
        let controls = BlockingPolicy.normalizedSiteControls([
            SiteControl(host: "unused.example"),
            SiteControl(host: "Example.COM", trackerBlocking: .disabled)
        ])
        XCTAssertEqual(controls, [SiteControl(host: "example.com", trackerBlocking: .disabled)])

        let stats = BlockingPolicy.normalizedSiteStats([
            SiteBlockStats(host: "Example.COM", stats: BlockStats(ads: 2, trackers: 1)),
            SiteBlockStats(host: "example.com", stats: BlockStats(popups: 3, cookieBanners: 4))
        ])
        XCTAssertEqual(
            stats,
            [SiteBlockStats(host: "example.com", stats: BlockStats(ads: 2, trackers: 1, popups: 3, cookieBanners: 4))]
        )
    }

    func testBlockStatsOnlyAddsNonnegativeCounts() {
        var stats = BlockStats(ads: 1)
        stats.add(BlockStats(ads: -3, trackers: 2, popups: 4, cookieBanners: -1))

        XCTAssertEqual(stats, BlockStats(ads: 1, trackers: 2, popups: 4, cookieBanners: 0))
        XCTAssertEqual(stats.total, 7)
    }
}
