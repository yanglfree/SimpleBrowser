import XCTest
import SwiftUI
@testable import ZhuoBrowserMac

final class AutoFillTests: XCTestCase {

    func testAutoFillAgentScriptExistsAndValid() {
        guard let source = InjectedScripts.shared.scriptContent(named: "autofill-agent") else {
            XCTFail("autofill-agent.js must exist and be loadable by InjectedScripts")
            return
        }

        XCTAssertTrue(source.contains("__zhuoAutoFillInjected"))
        XCTAssertTrue(source.contains("zhuoAutoFill"))
        XCTAssertTrue(source.contains("isLoginCandidate"))
        XCTAssertTrue(source.contains("isPasswordInput"))
        XCTAssertTrue(source.contains("isUsernameInput"))
        XCTAssertTrue(source.contains("window.__zhuoAutoFill"))
        XCTAssertTrue(source.contains("fill:"))
        XCTAssertTrue(source.contains("triggerPasskey:"))
    }

    func testInjectedScriptsMakeAutoFillScript() {
        let script = InjectedScripts.shared.makeAutoFillScript()
        XCTAssertNotNil(script)
        XCTAssertEqual(script?.injectionTime, .atDocumentEnd)
        XCTAssertFalse(script?.isForMainFrameOnly ?? true)
    }

    func testSavedCredentialRootDomainExtraction() {
        XCTAssertEqual(SavedCredential.extractRootDomain(from: "id1.cloud.huawei.com"), "huawei.com")
        XCTAssertEqual(SavedCredential.extractRootDomain(from: "appleid.apple.com"), "apple.com")
        XCTAssertEqual(SavedCredential.extractRootDomain(from: "github.com"), "github.com")
        XCTAssertEqual(SavedCredential.extractRootDomain(from: "sub.example.co.uk"), "example.co.uk")
        XCTAssertEqual(SavedCredential.extractRootDomain(from: "localhost"), "localhost")
    }

    @MainActor
    func testCredentialStoreSaveQueryDelete() {
        let store = CredentialStore.shared
        let testDomain = "test-\(UUID().uuidString).example.com"

        let cred1 = SavedCredential(
            domain: testDomain,
            username: "tester1@example.com",
            password: "password123",
            isPasskey: false
        )
        let cred2 = SavedCredential(
            domain: testDomain,
            username: "tester2@example.com",
            password: "password456",
            isPasskey: true
        )

        store.save(credential: cred1)
        store.save(credential: cred2)

        let queryExact = store.credentials(for: testDomain)
        XCTAssertGreaterThanOrEqual(queryExact.count, 2)
        // Passkey credential should be sorted first
        XCTAssertTrue(queryExact.first?.isPasskey == true)

        // Query by subdomain
        let querySub = store.credentials(for: "sub." + testDomain)
        XCTAssertGreaterThanOrEqual(querySub.count, 2)

        // Clean up
        store.delete(id: cred1.id)
        store.delete(id: cred2.id)

        let afterDelete = store.credentials(for: testDomain)
        XCTAssertFalse(afterDelete.contains(where: { $0.id == cred1.id || $0.id == cred2.id }))
    }

    @MainActor
    func testAutoFillPopoverControllerLifecycle() {
        let controller = AutoFillPopoverController.shared
        XCTAssertFalse(controller.isVisible)
        controller.dismiss()
        XCTAssertFalse(controller.isVisible)
    }

    @MainActor
    func testAutoFillSuggestionViewHierarchy() {
        let creds: [SavedCredential] = [
            SavedCredential(
                domain: "id1.cloud.huawei.com",
                username: "18627178676",
                password: "secretPassword",
                isPasskey: false
            )
        ]

        var selectedCred: SavedCredential?
        var didClickOtherPasswords = false
        var didClickNearbyPasskeys = false

        let view = AutoFillSuggestionView(
            credentials: creds,
            currentHost: "id1.cloud.huawei.com",
            rootDomain: "huawei.com",
            isPasswordContext: true,
            onSelectCredential: { selectedCred = $0 },
            onSelectOtherPasswords: { didClickOtherPasswords = true },
            onSelectNearbyPasskeys: { didClickNearbyPasskeys = true }
        )

        XCTAssertEqual(view.credentials.count, 1)
        XCTAssertEqual(view.currentHost, "id1.cloud.huawei.com")
        XCTAssertEqual(view.rootDomain, "huawei.com")
        XCTAssertTrue(view.isPasswordContext)

        // Trigger closures
        view.onSelectCredential(creds[0])
        XCTAssertEqual(selectedCred?.username, "18627178676")

        view.onSelectOtherPasswords()
        XCTAssertTrue(didClickOtherPasswords)

        view.onSelectNearbyPasskeys()
        XCTAssertTrue(didClickNearbyPasskeys)
    }
}
