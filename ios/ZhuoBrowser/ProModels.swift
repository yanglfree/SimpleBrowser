import Foundation

enum ProPlan: String, CaseIterable, Codable, Identifiable {
    case monthly
    case yearly
    case lifetime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .monthly: "月度会员"
        case .yearly: "年度会员"
        case .lifetime: "终身会员"
        }
    }

    var detail: String {
        switch self {
        case .monthly: "按月自动续订，可随时取消"
        case .yearly: "按年自动续订，长期使用更划算"
        case .lifetime: "一次购买，永久使用，可恢复购买"
        }
    }
}

enum ProCatalog {
    static let monthlyProductID = "com.youdroid.zhuobrowser.pro_monthly"
    static let yearlyProductID = "com.youdroid.zhuobrowser.pro_yearly"
    static let lifetimeProductID = "com.youdroid.zhuobrowser.pro_lifetime"

    static let productIDs = [monthlyProductID, yearlyProductID, lifetimeProductID]

    static func plan(for productID: String) -> ProPlan? {
        switch productID {
        case monthlyProductID: .monthly
        case yearlyProductID: .yearly
        case lifetimeProductID: .lifetime
        default: nil
        }
    }
}

struct ProProduct: Identifiable, Equatable {
    let id: String
    let plan: ProPlan
    let displayPrice: String
}

struct ProEntitlement: Codable, Equatable {
    let active: Bool
    let scope: String
    let plan: ProPlan?
    let productID: String
    let expiresAt: TimeInterval
    let source: String
    let verifiedAt: TimeInterval

    private enum CodingKeys: String, CodingKey {
        case active
        case scope
        case plan
        case productID = "product_id"
        case expiresAt = "expires_at"
        case source
        case verifiedAt = "verified_at"
    }

    func isCurrentlyActive(nowMilliseconds: TimeInterval = Date().timeIntervalSince1970 * 1_000) -> Bool {
        active
            && scope == "pro"
            && ProCatalog.plan(for: productID) == plan
            && (expiresAt <= 0 || expiresAt > nowMilliseconds)
    }
}

enum ProEntitlementPolicy {
    static let cacheLifetimeMilliseconds: TimeInterval = 24 * 60 * 60 * 1_000

    static func canUseCached(_ entitlement: ProEntitlement?, nowMilliseconds: TimeInterval) -> Bool {
        guard let entitlement, entitlement.isCurrentlyActive(nowMilliseconds: nowMilliseconds) else {
            return false
        }
        return entitlement.verifiedAt > 0
            && nowMilliseconds - entitlement.verifiedAt <= cacheLifetimeMilliseconds
    }
}

struct ProPaywallSelection: Equatable {
    private(set) var productID: String?
    private(set) var hasAcceptedTerms = false

    init(products: [ProProduct], productID: String? = nil) {
        self.productID = Self.resolveProductID(products: products, requested: productID)
    }

    var canPurchase: Bool {
        productID != nil && hasAcceptedTerms
    }

    mutating func select(_ productID: String, products: [ProProduct]) {
        guard products.contains(where: { $0.id == productID }) else { return }
        self.productID = productID
        hasAcceptedTerms = false
    }

    mutating func setAcceptedTerms(_ accepted: Bool) {
        hasAcceptedTerms = accepted
    }

    mutating func updateProducts(_ products: [ProProduct]) {
        let next = Self.resolveProductID(products: products, requested: productID)
        if next != productID {
            productID = next
            hasAcceptedTerms = false
        }
    }

    private static func resolveProductID(products: [ProProduct], requested: String?) -> String? {
        if let requested, products.contains(where: { $0.id == requested }) {
            return requested
        }
        for plan in [ProPlan.yearly, .monthly, .lifetime] {
            if let product = products.first(where: { $0.plan == plan }) {
                return product.id
            }
        }
        return nil
    }
}
