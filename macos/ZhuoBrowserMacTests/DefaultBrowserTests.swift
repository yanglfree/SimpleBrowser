import XCTest
@testable import ZhuoBrowserMac

final class DefaultBrowserTests: XCTestCase {

    func testAppInfoPlistQualifiesAsSystemDefaultWebBrowser() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let infoPlistURL = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("ZhuoBrowserMac/Info.plist")

        let data = try Data(contentsOf: infoPlistURL)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        )

        let capability = DefaultBrowserManager.inspectInfoPlist(plist)
        XCTAssertTrue(capability.qualifiesAsSystemDefaultWebBrowser)
        XCTAssertTrue(capability.declaredURLSchemes.contains("http"))
        XCTAssertTrue(capability.declaredURLSchemes.contains("https"))
        XCTAssertTrue(capability.declaredURLSchemes.contains("file"))
        XCTAssertTrue(capability.declaredURLSchemes.contains("zhuo"))
        XCTAssertTrue(capability.declaredViewerContentTypes.contains("public.html"))
        XCTAssertTrue(capability.declaredViewerContentTypes.contains("public.xhtml"))
        XCTAssertTrue(capability.declaredViewerContentTypes.contains("public.url"))
    }

    func testInspectInfoPlistRejectsIncompleteDeclarations() {
        let missingXHTML: [String: Any] = [
            "CFBundleURLTypes": [
                [
                    "CFBundleTypeRole": "Viewer",
                    "CFBundleURLSchemes": ["http", "https"]
                ]
            ],
            "CFBundleDocumentTypes": [
                [
                    "CFBundleTypeRole": "Viewer",
                    "LSItemContentTypes": ["public.html"]
                ]
            ]
        ]
        XCTAssertFalse(DefaultBrowserManager.inspectInfoPlist(missingXHTML).qualifiesAsSystemDefaultWebBrowser)

        let missingHTTPS: [String: Any] = [
            "CFBundleURLTypes": [
                [
                    "CFBundleTypeRole": "Viewer",
                    "CFBundleURLSchemes": ["http"]
                ]
            ],
            "CFBundleDocumentTypes": [
                [
                    "CFBundleTypeRole": "Viewer",
                    "LSItemContentTypes": ["public.html", "public.xhtml"]
                ]
            ]
        ]
        XCTAssertFalse(DefaultBrowserManager.inspectInfoPlist(missingHTTPS).qualifiesAsSystemDefaultWebBrowser)
    }

    func testDefaultBrowserStatusAndSetAsDefaultFlow() {
        var activeHandler = DefaultBrowserManager.HandlerInfo(
            bundleIdentifier: "com.apple.Safari",
            displayName: "Safari浏览器",
            bundleURL: URL(fileURLWithPath: "/Applications/Safari.app")
        )
        var requestedSchemes: [String] = []

        let manager = DefaultBrowserManager(
            ownBundleIdentifier: "com.youdroid.zhuobrowser.mac",
            defaultHandlerProvider: { _ in activeHandler },
            schemeDefaultSetter: { _, scheme, completion in
                requestedSchemes.append(scheme)
                if scheme == "https" {
                    activeHandler = DefaultBrowserManager.HandlerInfo(
                        bundleIdentifier: "com.youdroid.zhuobrowser.mac",
                        displayName: "Zhuo浏览器",
                        bundleURL: URL(fileURLWithPath: "/Applications/ZhuoBrowserMac.app")
                    )
                }
                completion(nil)
            }
        )

        XCTAssertFalse(manager.isDefaultBrowser)
        XCTAssertEqual(manager.currentDefaultBrowserName, "Safari浏览器")

        let exp = expectation(description: "Set as default browser completes")
        manager.setAsDefaultBrowser { becameDefault in
            XCTAssertTrue(becameDefault)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2.0)

        XCTAssertEqual(requestedSchemes, ["http", "https"])
        XCTAssertTrue(manager.isDefaultBrowser)
        XCTAssertEqual(manager.currentDefaultBrowserName, "Zhuo浏览器")
    }

    func testURLPolicySupportsLocalFileURLs() {
        let fileURL = "file:///Users/test/Documents/index.html"
        XCTAssertTrue(URLPolicy.looksLikeURL(fileURL))
        XCTAssertEqual(URLPolicy.normalizeAddress(fileURL), fileURL)
        XCTAssertEqual(URLPolicy.displayAddress(for: fileURL), fileURL)
    }
}
