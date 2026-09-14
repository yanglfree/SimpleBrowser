import XCTest
@testable import ZhuoBrowser

final class LongScreenshotPlanTests: XCTestCase {
    func testShortPageUsesOneViewport() {
        XCTAssertEqual(
            LongScreenshotPlan.slices(totalHeight: 600, viewportHeight: 800),
            [LongScreenshotSlice(offsetY: 0, cropTopRatio: 0, cropHeightRatio: 1)]
        )
    }

    func testTrailingSliceCropsTheRepeatedTop() {
        let slices = LongScreenshotPlan.slices(totalHeight: 2_600, viewportHeight: 1_000)

        XCTAssertEqual(slices.count, 3)
        XCTAssertEqual(slices[2].offsetY, 1_600)
        XCTAssertEqual(slices[2].cropTopRatio, 0.4, accuracy: 0.001)
        XCTAssertEqual(slices[2].cropHeightRatio, 0.6, accuracy: 0.001)
    }

    func testCaptureStopsAtFortyScreens() {
        let slices = LongScreenshotPlan.slices(totalHeight: 50_000, viewportHeight: 1_000)
        XCTAssertEqual(slices.count, 40)
        XCTAssertEqual(slices.last?.offsetY, 39_000)
    }

    func testOutputWidthHonorsPixelBudget() {
        let width = LongScreenshotPlan.snapshotWidthPoints(
            viewportWidth: 390,
            totalHeight: 33_760,
            viewportHeight: 844,
            displayScale: 3
        )
        let pixelWidth = width * 3
        let pixelHeight = pixelWidth * (33_760 / 390)

        XCTAssertLessThanOrEqual(pixelWidth * pixelHeight, LongScreenshotPlan.maxOutputPixels + 1)
        XCTAssertLessThan(width, 390)
    }
}
