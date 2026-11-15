import SwiftUI
import UIKit
import XCTest
@testable import ZhuoBrowser

final class DockSwipeTapGuardTests: XCTestCase {
    func testAllowsTapInitially() {
        let guardState = DockSwipeTapGuard()
        XCTAssertTrue(guardState.canTriggerTap(at: Date(timeIntervalSince1970: 100)))
    }

    func testSuppressesTapDuringDragAndCooldownWindow() {
        var guardState = DockSwipeTapGuard()
        let start = Date(timeIntervalSince1970: 1_000)

        guardState.beginDrag()
        XCTAssertFalse(guardState.canTriggerTap(at: start))

        guardState.endDrag(at: start, cooldown: 0.35)
        XCTAssertFalse(guardState.canTriggerTap(at: start.addingTimeInterval(0.05)))
        XCTAssertFalse(guardState.canTriggerTap(at: start.addingTimeInterval(0.34)))
        XCTAssertTrue(guardState.canTriggerTap(at: start.addingTimeInterval(0.35)))
    }

    @MainActor
    func testTabOverviewThumbnailDoesNotExceedColumnWidth() {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 2600))
        let tallImage = renderer.image { context in
            UIColor.systemRed.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1200, height: 2600))
        }
        let wideRenderer = UIGraphicsImageRenderer(size: CGSize(width: 2400, height: 1000))
        let wideImage = wideRenderer.image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2400, height: 1000))
        }

        let grid = LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 12), count: 2),
            spacing: 12
        ) {
            TabOverviewThumbnail(image: nil, isPrivate: false)
            TabOverviewThumbnail(image: tallImage, isPrivate: false)
            TabOverviewThumbnail(image: wideImage, isPrivate: false)
        }
        .frame(width: 353)

        let controller = UIHostingController(rootView: grid)
        controller.view.frame = CGRect(x: 0, y: 0, width: 353, height: 420)
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()

        let measured = controller.sizeThatFits(in: CGSize(width: 353, height: 1000))
        XCTAssertLessThanOrEqual(measured.width, 353.5)
        XCTAssertEqual(measured.height, 300, accuracy: 2)
    }
}
