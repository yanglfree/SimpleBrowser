import Foundation
import ObjectiveC
import XCTest
@testable import ZhuoBrowserMac

final class InputSourceCrashGuardTests: XCTestCase {

    func testInstalledThirdPartyInputMethodBundlesParsesInfoPlist() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("InputSourceCrashGuardTests_\(UUID().uuidString)")
        let contentsDir = tempDir
            .appendingPathComponent("MockIME.app")
            .appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contentsDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let plist: [String: Any] = [
            "CFBundleIdentifier": "com.example.mockime",
            "ComponentInputModeDict": [
                "tsInputModeListKey": [
                    "com.example.mockime.mode": [
                        "TISInputSourceID": "com.example.mockime.pinyin"
                    ]
                ]
            ]
        ]
        let plistData = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try plistData.write(to: contentsDir.appendingPathComponent("Info.plist"))

        let bundles = InputSourceCrashGuard.installedThirdPartyInputMethodBundles(in: [tempDir])
        XCTAssertEqual(bundles.count, 1)
        XCTAssertEqual(bundles.first?.bundleID, "com.example.mockime")
        XCTAssertEqual(bundles.first?.inputSourceIDs, ["com.example.mockime.pinyin"])
    }

    func testIsIntlDataCacheStaleDetectsMissingBundleOrMode() {
        let bundle = InputSourceCrashGuard.InstalledInputMethodBundle(
            bundleURL: URL(fileURLWithPath: "/Users/test/Library/Input Methods/MockIME.app"),
            bundleID: "com.example.mockime",
            inputSourceIDs: ["com.example.mockime.pinyin"]
        )

        XCTAssertFalse(InputSourceCrashGuard.isIntlDataCacheStale(kbdxData: nil, installedBundles: [bundle]))
        XCTAssertFalse(InputSourceCrashGuard.isIntlDataCacheStale(kbdxData: Data(), installedBundles: [bundle]))

        let freshData = Data("prefix\0com.example.mockime\0com.example.mockime.pinyin\0suffix".utf8)
        XCTAssertFalse(InputSourceCrashGuard.isIntlDataCacheStale(kbdxData: freshData, installedBundles: [bundle]))

        let staleData = Data("prefix\0com.sogou.inputmethod.sogou.pinyin\0suffix".utf8)
        XCTAssertTrue(InputSourceCrashGuard.isIntlDataCacheStale(kbdxData: staleData, installedBundles: [bundle]))
    }

    func testSelectCurrentInputSourceGuardPreventsNullCFReleaseCrash() throws {
        InputSourceCrashGuard.install()

        XCTAssertTrue(InputSourceCrashGuard.canResolveInputSource(id: "com.apple.keylayout.ABC"))
        XCTAssertFalse(InputSourceCrashGuard.canResolveInputSource(id: "com.youdroid.nonexistent.ghost.ime"))

        guard let ctrlCls = NSClassFromString("TUINSCursorUIController") as? NSObject.Type,
              let accCls = NSClassFromString("TUIInputModeSwitcherAccessory") as? NSObject.Type else {
            throw XCTSkip("TextInputUIMacHelper private classes unavailable on this macOS build")
        }

        let ctrl = ctrlCls.init()
        guard let switcher = ctrl.value(forKey: "inputSourceSwitcher") as? NSObject else {
            XCTFail("Expected TUINSCursorUIController.inputSourceSwitcher to be non-nil")
            return
        }

        let acc = accCls.init()
        acc.setValue(["com.youdroid.nonexistent.ghost.ime"], forKey: "inputSourceIDs")
        acc.setValue(0, forKey: "selectedIndex")
        acc.setValue(true, forKey: "isInputSource")
        switcher.setValue(acc, forKey: "accessory")

        XCTAssertEqual(
            switcher.value(forKey: "inputSourceID") as? String,
            "com.youdroid.nonexistent.ghost.ime"
        )

        // Without the guard, this calls CFRelease(NULL) inside _selectCurrentInputSource and raises SIGTRAP.
        _ = ctrl.perform(NSSelectorFromString("_selectCurrentInputSource"))
    }
}
