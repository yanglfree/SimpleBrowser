import Combine
import StoreKit
import UIKit

@MainActor
final class ProBillingService: ObservableObject {
    @Published private(set) var products: [ProProduct] = []
    @Published private(set) var entitlement: ProEntitlement?
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var isPurchasing = false
    @Published private(set) var statusMessage: String?

    private var storeProducts: [String: Product] = [:]
    private var updatesTask: Task<Void, Never>?
    private var hasActivated = false
    private let cacheKey = "zhuobrowser.iap.server-entitlement"

    var isPro: Bool {
        entitlement?.isCurrentlyActive() == true
    }

    init() {
        entitlement = Self.loadCachedEntitlement(key: cacheKey)
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                await self.process(result, reason: "transaction_update")
            }
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    func activate() async {
        guard !hasActivated else { return }
        hasActivated = true
        await fetchProducts()
        await syncEntitlement(reason: "launch")
    }

    func refreshForForeground() async {
        await syncEntitlement(reason: "foreground")
    }

    func fetchProducts() async {
        guard !isLoadingProducts else { return }
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            let catalog = try await IapEntitlementAPI.shared.fetchCatalog()
            let catalogIDs = Set(catalog.map(\.storeProductID))
            let fetched = try await Product.products(for: ProCatalog.productIDs.filter(catalogIDs.contains))
            storeProducts = Dictionary(uniqueKeysWithValues: fetched.map { ($0.id, $0) })
            products = fetched.compactMap { product in
                guard let plan = ProCatalog.plan(for: product.id),
                      let catalogProduct = catalog.first(where: { $0.storeProductID == product.id }),
                      catalogProduct.productType == (plan == .lifetime ? "non_consumable" : "subscription") else {
                    return nil
                }
                return ProProduct(id: product.id, plan: plan, displayPrice: product.displayPrice)
            }.sorted { Self.rank($0.plan) < Self.rank($1.plan) }
            statusMessage = products.isEmpty ? "App Store 商品暂不可用，请稍后重试。" : nil
        } catch {
            products = []
            storeProducts = [:]
            statusMessage = "暂时无法读取会员方案，请稍后重试。"
        }
    }

    func purchase(productID: String) async -> Bool {
        guard !isPurchasing, let product = storeProducts[productID], AppStore.canMakePayments else {
            statusMessage = "当前设备暂时无法购买。"
            return false
        }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let token = await IapEntitlementAPI.shared.appAccountToken()
            switch try await product.purchase(options: [.appAccountToken(token)]) {
            case .success(let result):
                let succeeded = await process(result, reason: "purchase")
                statusMessage = succeeded ? "卓阅 Pro 已激活。" : "购买正在由服务器确认，请稍后恢复购买。"
                return succeeded
            case .userCancelled:
                return false
            case .pending:
                statusMessage = "购买尚待确认，完成后会自动同步。"
                return false
            @unknown default:
                statusMessage = "暂时无法完成购买，请稍后重试。"
                return false
            }
        } catch {
            statusMessage = "暂时无法完成购买，请稍后重试。"
            return false
        }
    }

    func restorePurchases() async -> Bool {
        guard !isPurchasing else { return false }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            try await AppStore.sync()
            await syncEntitlement(reason: "manual_restore")
            statusMessage = isPro ? "已恢复卓阅 Pro。" : "没有找到可恢复的购买。"
            return isPro
        } catch {
            statusMessage = "恢复购买失败，请稍后重试。"
            return false
        }
    }

    func manageSubscriptions() async {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else {
            statusMessage = "暂时无法打开订阅管理。"
            return
        }
        do {
            try await AppStore.showManageSubscriptions(in: scene)
        } catch {
            statusMessage = "暂时无法打开订阅管理。"
        }
    }

    private func syncEntitlement(reason: String) async {
        var sawVerificationFailure = false
        for await result in Transaction.unfinished {
            guard isKnown(result) else { continue }
            if !(await process(result, reason: reason)) {
                sawVerificationFailure = true
            }
        }
        for await result in Transaction.currentEntitlements {
            guard isKnown(result) else { continue }
            if !(await process(result, reason: reason)) {
                sawVerificationFailure = true
            }
        }
        do {
            applyServerEntitlement(try await IapEntitlementAPI.shared.fetchEntitlement())
        } catch {
            if !ProEntitlementPolicy.canUseCached(
                entitlement,
                nowMilliseconds: Date().timeIntervalSince1970 * 1_000
            ) {
                applyServerEntitlement(nil)
            }
            if sawVerificationFailure {
                statusMessage = "购买正在由服务器确认，请稍后重试。"
            }
        }
    }

    @discardableResult
    private func process(_ result: VerificationResult<Transaction>, reason: String) async -> Bool {
        guard case .verified(let transaction) = result,
              ProCatalog.plan(for: transaction.productID) != nil,
              let environment = Self.environment(from: result.jwsRepresentation) else {
            return false
        }
        do {
            let evidence = IapStoreKitEvidence(
                transaction: transaction,
                signedTransactionInfo: result.jwsRepresentation,
                environment: environment
            )
            let response = try await IapEntitlementAPI.shared.verify(evidence: evidence, reason: reason)
            guard response.verified, response.entitlement?.isCurrentlyActive() == true else {
                return false
            }
            applyServerEntitlement(response.entitlement)
            if response.needsFinishTransaction {
                await transaction.finish()
            }
            return true
        } catch {
            return false
        }
    }

    private func isKnown(_ result: VerificationResult<Transaction>) -> Bool {
        switch result {
        case .verified(let transaction), .unverified(let transaction, _):
            ProCatalog.plan(for: transaction.productID) != nil
        }
    }

    private func applyServerEntitlement(_ entitlement: ProEntitlement?) {
        self.entitlement = entitlement
        if let entitlement, entitlement.isCurrentlyActive(), let data = try? JSONEncoder().encode(entitlement) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        } else {
            UserDefaults.standard.removeObject(forKey: cacheKey)
        }
    }

    private static func loadCachedEntitlement(key: String) -> ProEntitlement? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let entitlement = try? JSONDecoder().decode(ProEntitlement.self, from: data),
              ProEntitlementPolicy.canUseCached(
                entitlement,
                nowMilliseconds: Date().timeIntervalSince1970 * 1_000
              ) else {
            return nil
        }
        return entitlement
    }

    private static func environment(from jws: String) -> String? {
        let segments = jws.split(separator: ".")
        guard segments.count == 3 else { return nil }
        var payload = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let environment = json["environment"] as? String,
              ["Sandbox", "Production"].contains(environment) else {
            return nil
        }
        return environment
    }

    private static func rank(_ plan: ProPlan) -> Int {
        switch plan {
        case .yearly: 0
        case .monthly: 1
        case .lifetime: 2
        }
    }
}
