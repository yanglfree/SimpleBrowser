import XCTest
@testable import ZhuoBrowser

final class HomeBackgroundPolicyTests: XCTestCase {
    func testDailyRefreshRequiresSelectionAndCompletedPrivacyFlow() {
        XCTAssertTrue(
            BingDailyWallpaperPolicy.shouldRefresh(
                backgroundEnabled: true,
                dailySelected: true,
                privacyConsentAccepted: true,
                onboardingCompleted: true
            )
        )

        for blocked in 0..<4 {
            var conditions = [true, true, true, true]
            conditions[blocked] = false
            XCTAssertFalse(
                BingDailyWallpaperPolicy.shouldRefresh(
                    backgroundEnabled: conditions[0],
                    dailySelected: conditions[1],
                    privacyConsentAccepted: conditions[2],
                    onboardingCompleted: conditions[3]
                )
            )
        }
    }

    func testBingArchiveResolvesOnlyExpectedImageEndpoint() throws {
        let payload = #"{"images":[{"url":"/th?id=OHR.Example_ZH-CN123.jpg&rf=LaDigue_1920x1080.jpg"}]}"#
        let url = try XCTUnwrap(BingDailyWallpaperPolicy.resolveImageURL(from: Data(payload.utf8)))

        XCTAssertEqual(url.host, "www.bing.com")
        XCTAssertEqual(url.path, "/th")
        XCTAssertTrue(url.absoluteString.contains("OHR.Example_ZH-CN123.jpg"))
    }

    func testBingArchiveRejectsUnexpectedOrMissingPaths() {
        let absolute = #"{"images":[{"url":"https://example.com/image.jpg"}]}"#
        let missingID = #"{"images":[{"url":"/th?rf=image.jpg"}]}"#

        XCTAssertNil(BingDailyWallpaperPolicy.resolveImageURL(from: Data(absolute.utf8)))
        XCTAssertNil(BingDailyWallpaperPolicy.resolveImageURL(from: Data(missingID.utf8)))
        XCTAssertNil(BingDailyWallpaperPolicy.resolveImageURL(from: Data("not-json".utf8)))
    }

    func testDailyCacheFreshnessUsesTheLocalCalendarDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3_600)!
        let now = calendar.date(
            from: DateComponents(year: 2026, month: 9, day: 15, hour: 12)
        )!

        XCTAssertTrue(
            BingDailyWallpaperPolicy.isFresh(
                modifiedAt: now.addingTimeInterval(-60),
                now: now,
                calendar: calendar
            )
        )
        XCTAssertFalse(
            BingDailyWallpaperPolicy.isFresh(
                modifiedAt: now.addingTimeInterval(-86_400),
                now: now,
                calendar: calendar
            )
        )
        XCTAssertFalse(
            BingDailyWallpaperPolicy.isFresh(
                modifiedAt: now.addingTimeInterval(60),
                now: now,
                calendar: calendar
            )
        )
    }

    func testDailyImageRequiresACompleteBoundedJPEG() {
        XCTAssertTrue(BingDailyWallpaperPolicy.isSupportedJPEG(Data([0xFF, 0xD8, 0xFF, 0xD9])))
        XCTAssertFalse(BingDailyWallpaperPolicy.isSupportedJPEG(Data([0x89, 0x50, 0x4E, 0x47])))
        XCTAssertFalse(BingDailyWallpaperPolicy.isSupportedJPEG(Data([0xFF, 0xD8, 0x00, 0x00])))
    }
}
