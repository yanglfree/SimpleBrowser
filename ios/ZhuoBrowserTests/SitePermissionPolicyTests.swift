import XCTest
@testable import ZhuoBrowser

final class SitePermissionPolicyTests: XCTestCase {
    func testToggledDecisionMatchesHarmonySettingsCycle() {
        XCTAssertEqual(SitePermissionPolicy.toggledDecision(from: .prompt), .allow)
        XCTAssertEqual(SitePermissionPolicy.toggledDecision(from: .allow), .deny)
        XCTAssertEqual(SitePermissionPolicy.toggledDecision(from: .deny), .allow)
    }

    func testApplyUpdatesOnlySelectedPermission() {
        let original = SitePermission(
            origin: "https://example.com",
            camera: .deny,
            microphone: .prompt,
            location: .allow
        )

        let updated = SitePermissionPolicy.apply(
            [original],
            origin: original.origin,
            kinds: [.microphone],
            decision: .allow
        )

        XCTAssertEqual(updated, [SitePermission(
            origin: original.origin,
            camera: .deny,
            microphone: .allow,
            location: .allow
        )])
    }
}
