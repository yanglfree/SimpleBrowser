import XCTest
import SwiftUI
@testable import ZhuoBrowserMac

@MainActor
final class FavoritesTests: XCTestCase {

    func testDefaultFavoritesCountAndStructure() {
        let manager = FavoritesManager.shared
        XCTAssertEqual(manager.items.count, 24, "There should be exactly 24 curated favorites matching the screenshot")

        let folders = manager.items.filter { $0.isFolder }
        XCTAssertEqual(folders.count, 6, "There should be 6 folders: 设计, Android 开发, iOS 开发, 工具, 下载&资源, 工作")

        let expectedFolderTitles = ["设计", "Android 开发", "iOS 开发", "工具", "下载&资源", "工作"]
        for expected in expectedFolderTitles {
            XCTAssertTrue(folders.contains(where: { $0.title == expected }), "Missing folder: \(expected)")
        }

        for folder in folders {
            XCTAssertFalse(folder.children.isEmpty, "Folder \(folder.title) should have children")
            XCTAssertEqual(folder.children.count, 9, "Folder \(folder.title) should contain 9 bookmark items")
        }
    }

    func testLinksIntegrity() {
        let manager = FavoritesManager.shared
        let links = manager.items.filter { !$0.isFolder }
        XCTAssertEqual(links.count, 18, "There should be 18 link items")

        for link in links {
            XCTAssertFalse(link.url.isEmpty, "Link \(link.title) should have a valid URL")
            XCTAssertTrue(link.url.hasPrefix("http://") || link.url.hasPrefix("https://"), "URL should have web scheme: \(link.url)")
            XCTAssertFalse(link.iconName.isEmpty, "Link \(link.title) should have an iconName")
        }
    }

    func testIconImageResolution() {
        let manager = FavoritesManager.shared
        for item in manager.items {
            let image = manager.iconImage(named: item.iconName)
            XCTAssertNotNil(image, "Icon image for \(item.iconName) should be resolved")
            if let image {
                XCTAssertGreaterThan(image.size.width, 0)
                XCTAssertGreaterThan(image.size.height, 0)
            }
        }
    }

    func testFavoritesSectionViewHosting() {
        let session = BrowserSession()
        let view = FavoritesSectionView(session: session, hasWallpaper: false)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 1000, height: 300)
        XCTAssertNotNil(hosting)
    }
}
