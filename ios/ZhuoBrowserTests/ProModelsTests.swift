import XCTest
@testable import ZhuoBrowser

final class ProModelsTests: XCTestCase {
    func testCatalogMapsOnlyKnownProducts() {
        XCTAssertEqual(ProCatalog.plan(for: ProCatalog.monthlyProductID), .monthly)
        XCTAssertEqual(ProCatalog.plan(for: ProCatalog.yearlyProductID), .yearly)
        XCTAssertEqual(ProCatalog.plan(for: ProCatalog.lifetimeProductID), .lifetime)
        XCTAssertNil(ProCatalog.plan(for: "unknown"))
    }

    func testEntitlementRequiresMatchingServerScopeProductAndExpiry() {
        let now: TimeInterval = 2_000_000
        XCTAssertTrue(entitlement(plan: .yearly, expiresAt: now + 1).isCurrentlyActive(nowMilliseconds: now))
        XCTAssertFalse(entitlement(plan: .monthly, expiresAt: now + 1).isCurrentlyActive(nowMilliseconds: now))
        XCTAssertFalse(entitlement(plan: .yearly, expiresAt: now).isCurrentlyActive(nowMilliseconds: now))
        XCTAssertTrue(entitlement(plan: .lifetime, productID: ProCatalog.lifetimeProductID, expiresAt: 0).isCurrentlyActive(nowMilliseconds: now))
    }

    func testCachedEntitlementMustBeFreshAndActive() {
        let now: TimeInterval = 10_000_000_000
        XCTAssertTrue(ProEntitlementPolicy.canUseCached(
            entitlement(expiresAt: now + 10_000, verifiedAt: now - 1_000),
            nowMilliseconds: now
        ))
        XCTAssertFalse(ProEntitlementPolicy.canUseCached(
            entitlement(
                expiresAt: now + 10_000,
                verifiedAt: now - ProEntitlementPolicy.cacheLifetimeMilliseconds - 1
            ),
            nowMilliseconds: now
        ))
    }

    func testPaywallDefaultsToYearlyAndResetsConsentWhenPlanChanges() {
        let products = [
            ProProduct(id: ProCatalog.monthlyProductID, plan: .monthly, displayPrice: "¥8"),
            ProProduct(id: ProCatalog.yearlyProductID, plan: .yearly, displayPrice: "¥68"),
            ProProduct(id: ProCatalog.lifetimeProductID, plan: .lifetime, displayPrice: "¥99")
        ]
        var selection = ProPaywallSelection(products: products)
        XCTAssertEqual(selection.productID, ProCatalog.yearlyProductID)
        XCTAssertFalse(selection.canPurchase)

        selection.setAcceptedTerms(true)
        XCTAssertTrue(selection.canPurchase)
        selection.select(ProCatalog.monthlyProductID, products: products)

        XCTAssertEqual(selection.productID, ProCatalog.monthlyProductID)
        XCTAssertFalse(selection.hasAcceptedTerms)
        XCTAssertFalse(selection.canPurchase)
    }

    private func entitlement(
        plan: ProPlan = .yearly,
        productID: String = ProCatalog.yearlyProductID,
        expiresAt: TimeInterval,
        verifiedAt: TimeInterval = 1
    ) -> ProEntitlement {
        ProEntitlement(
            active: true,
            scope: "pro",
            plan: plan,
            productID: productID,
            expiresAt: expiresAt,
            source: "app_store",
            verifiedAt: verifiedAt
        )
    }
}
