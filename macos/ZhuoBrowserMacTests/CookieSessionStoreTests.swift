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
}
