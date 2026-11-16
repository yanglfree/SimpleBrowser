import WebKit
import XCTest
@testable import ZhuoBrowserMac

final class CookieSessionStoreTests: XCTestCase {

    private func makeCookie(name: String, value: String, sessionOnly: Bool) -> HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name,
            .value: value,
            .domain: "example.com",
            .path: "/"
        ]
        if !sessionOnly {
            properties[.expires] = Date().addingTimeInterval(86_400)
        }
        return HTTPCookie(properties: properties)
    }

    func testSessionCookiesSurviveAnArchiveRoundTrip() {
        guard let cookie = makeCookie(name: "web_session", value: "abc123", sessionOnly: true) else {
            return XCTFail("Failed to build test cookie")
        }
        XCTAssertTrue(cookie.isSessionOnly, "A cookie without an expiry must be session-only")

        guard let data = CookieSessionStore.encodeCookies([cookie]) else {
            return XCTFail("Encoding session cookies must succeed")
        }
        guard let restored = CookieSessionStore.decodeCookies(from: data) else {
            return XCTFail("Decoding the archive must succeed")
        }

        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(restored.first?.name, "web_session")
        XCTAssertEqual(restored.first?.value, "abc123")
        XCTAssertEqual(restored.first?.domain, "example.com")
        XCTAssertEqual(restored.first?.isSessionOnly, true)
    }

    func testPersistentCookiesAreAlsoRoundTrippable() {
        guard let cookie = makeCookie(name: "webId", value: "x", sessionOnly: false) else {
            return XCTFail("Failed to build test cookie")
        }
        XCTAssertFalse(cookie.isSessionOnly)

        guard let data = CookieSessionStore.encodeCookies([cookie]),
              let restored = CookieSessionStore.decodeCookies(from: data) else {
            return XCTFail("Round trip failed")
        }
        XCTAssertEqual(restored.first?.isSessionOnly, false)
    }

    func testCorruptArchiveIsIgnored() {
        XCTAssertNil(CookieSessionStore.decodeCookies(from: Data("not an archive".utf8)))
    }

    func testStoreDoesNotTouchDiskInEphemeralMode() {
        let store = CookieSessionStore(isPersistenceEnabled: false)
        XCTAssertFalse(store.isPersistenceEnabled)

        // Must be a harmless no-op rather than a crash or a stray file.
        store.persistSessionCookies()
        store.restoreArchivedCookies()
        store.startPeriodicFlush()
        store.stopPeriodicFlush()
    }

    func testLegacyNSKeyedArchiverCookieDataIsMigratedWithoutError() throws {
        guard let cookie = makeCookie(name: "legacy_session", value: "migrated_ok", sessionOnly: true) else {
            return XCTFail("Failed to build test cookie")
        }
        let legacyData = try NSKeyedArchiver.archivedData(
            withRootObject: [cookie],
            requiringSecureCoding: true
        )
        guard let restored = CookieSessionStore.decodeCookies(from: legacyData) else {
            return XCTFail("Legacy NSKeyedArchiver cookie blob must decode via migration path")
        }
        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(restored.first?.name, "legacy_session")
        XCTAssertEqual(restored.first?.value, "migrated_ok")
    }

    func testWebSessionStorageStoreRoundTripsOriginEntries() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WebSessionStorageTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("web-session-storage.json")
        let writer = WebSessionStorageStore(isPersistenceEnabled: true, storageURL: fileURL)
        writer.updateEntries(
            ["finder_uin": "v2_abc", "auth_token": "tok_999"],
            forOrigin: "https://channels.weixin.qq.com"
        )
        writer.flushSynchronously()

        let reader = WebSessionStorageStore(isPersistenceEnabled: true, storageURL: fileURL)
        let entries = reader.entries(forOrigin: "https://channels.weixin.qq.com")
        XCTAssertEqual(entries["finder_uin"], "v2_abc")
        XCTAssertEqual(entries["auth_token"], "tok_999")
    }

    @MainActor
    func testSessionStorageBootstrapRunsInIsolatedWorldWithoutPatchingStoragePrototype() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WebSessionStorageWebViewTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("web-session-storage.json")
        let store = WebSessionStorageStore(isPersistenceEnabled: true, storageURL: fileURL)
        store.updateEntries(["token": "abc_123"], forOrigin: "https://aistudio.google.com")

        let script = try XCTUnwrap(store.makeBootstrapUserScript())
        XCTAssertEqual(script.injectionTime, .atDocumentStart)

        let controller = WKUserContentController()
        controller.addUserScript(script)

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.userContentController = controller
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 400, height: 300), configuration: config)

        let navDelegate = CookieTestNavigationDelegate()
        webView.navigationDelegate = navDelegate
        let loaded = expectation(description: "html loaded")
        navDelegate.onFinish = { loaded.fulfill() }
        webView.loadHTMLString("<html><body>ok</body></html>", baseURL: URL(string: "https://aistudio.google.com/api-keys")!)
        wait(for: [loaded], timeout: 5.0)

        let check = expectation(description: "page storage check")
        webView.evaluateJavaScript("""
            JSON.stringify({
                restoredValue: window.sessionStorage.getItem('token'),
                setItemNative: Storage.prototype.setItem.toString().includes('[native code]'),
                removeItemNative: Storage.prototype.removeItem.toString().includes('[native code]'),
                clearNative: Storage.prototype.clear.toString().includes('[native code]'),
                hasLeak: typeof window.__zhuoSyncSessionStorage !== 'undefined'
            })
        """, in: nil, in: .page) { result in
            if case .success(let val) = result,
               let data = (val as? String)?.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                XCTAssertEqual(dict["restoredValue"] as? String, "abc_123")
                XCTAssertEqual(dict["setItemNative"] as? Bool, true)
                XCTAssertEqual(dict["removeItemNative"] as? Bool, true)
                XCTAssertEqual(dict["clearNative"] as? Bool, true)
                XCTAssertEqual(dict["hasLeak"] as? Bool, false)
            } else {
                XCTFail("Unexpected JS check result: \(result)")
            }
            check.fulfill()
        }
        wait(for: [check], timeout: 5.0)
        webView.stopLoading()
        webView.navigationDelegate = nil
    }
}

private final class CookieTestNavigationDelegate: NSObject, WKNavigationDelegate {
    var onFinish: (() -> Void)?

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onFinish?()
    }
}
