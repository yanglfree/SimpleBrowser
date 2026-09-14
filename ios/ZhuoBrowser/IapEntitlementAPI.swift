import Foundation
import StoreKit

struct IapCatalogProduct: Decodable {
    let storeProductID: String
    let productType: String
    let entitlementScope: String
    let plan: ProPlan
    let active: Bool

    private enum CodingKeys: String, CodingKey {
        case storeProductID = "storeProductId"
        case productType
        case entitlementScope
        case plan
        case active
    }
}

struct IapStoreKitEvidence: Encodable {
    let storeProductID: String
    let productType: String
    let signedTransactionInfo: String
    let transactionID: String
    let originalTransactionID: String
    let appAccountToken: String?
    let environment: String
    let idempotencyKey: String

    init(transaction: Transaction, signedTransactionInfo: String, environment: String) {
        storeProductID = transaction.productID
        productType = ProCatalog.plan(for: transaction.productID) == .lifetime ? "non_consumable" : "subscription"
        self.signedTransactionInfo = signedTransactionInfo
        transactionID = String(transaction.id)
        originalTransactionID = String(transaction.originalID)
        appAccountToken = transaction.appAccountToken?.uuidString
        self.environment = environment
        idempotencyKey = "ios:zhuobrowser:\(transaction.productID):\(transaction.originalID):\(transaction.id)"
    }

    private enum CodingKeys: String, CodingKey {
        case storeProductID = "store_product_id"
        case productType = "product_type"
        case signedTransactionInfo = "signed_transaction_info"
        case transactionID = "transaction_id"
        case originalTransactionID = "original_transaction_id"
        case appAccountToken = "app_account_token"
        case environment
        case idempotencyKey = "idempotency_key"
    }
}

struct IapVerifyResponse: Decodable {
    let verified: Bool
    let entitlement: ProEntitlement?
    let needsFinishTransaction: Bool

    private enum CodingKeys: String, CodingKey {
        case verified
        case entitlement
        case needsFinishTransaction = "needs_finish_transaction"
    }
}

actor IapEntitlementAPI {
    static let shared = IapEntitlementAPI()

    private let baseURL = URL(string: "https://gateway.youdroid.top/v1/iap")!
    private let appID = "zhuobrowser"
    private let platform = "ios"
    private let installIDKey = "zhuobrowser.iap.install-id"
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchCatalog() async throws -> [IapCatalogProduct] {
        var components = URLComponents(url: baseURL.appendingPathComponent("products"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "platform", value: platform),
            URLQueryItem(name: "app_id", value: appID)
        ]
        let response: CatalogResponse = try await perform(request(url: components.url!, method: "GET"))
        return response.products.filter {
            $0.active && $0.entitlementScope == "pro" && ProCatalog.plan(for: $0.storeProductID) == $0.plan
        }
    }

    func verify(evidence: IapStoreKitEvidence, reason: String) async throws -> IapVerifyResponse {
        let body = VerifyRequest(
            platform: platform,
            appID: appID,
            accountID: installID(),
            evidence: evidence,
            clientEventTime: Int64(Date().timeIntervalSince1970 * 1_000),
            reason: reason
        )
        return try await post(path: "verify", body: body)
    }

    func fetchEntitlement() async throws -> ProEntitlement? {
        var components = URLComponents(url: baseURL.appendingPathComponent("entitlements"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "platform", value: platform),
            URLQueryItem(name: "app_id", value: appID),
            URLQueryItem(name: "account_id", value: installID())
        ]
        let response: EntitlementResponse = try await perform(request(url: components.url!, method: "GET"))
        return response.entitlement
    }

    func appAccountToken() -> UUID {
        if let value = UserDefaults.standard.string(forKey: installIDKey), let token = UUID(uuidString: value) {
            return token
        }
        let token = UUID()
        UserDefaults.standard.set(token.uuidString, forKey: installIDKey)
        return token
    }

    private func installID() -> String {
        appAccountToken().uuidString.lowercased()
    }

    private func post<Response: Decodable, Body: Encodable>(path: String, body: Body) async throws -> Response {
        var request = request(url: baseURL.appendingPathComponent(path), method: "POST")
        request.httpBody = try JSONEncoder().encode(body)
        return try await perform(request)
    }

    private func request(url: URL, method: String) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(appID, forHTTPHeaderField: "X-App-Id")
        request.setValue("iOS", forHTTPHeaderField: "X-Platform")
        return request
    }

    private func perform<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw IapAPIError.serverRejected
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }
}

enum IapAPIError: Error {
    case serverRejected
}

private struct CatalogResponse: Decodable {
    let products: [IapCatalogProduct]
}

private struct EntitlementResponse: Decodable {
    let entitlement: ProEntitlement?
}

private struct VerifyRequest: Encodable {
    let platform: String
    let appID: String
    let accountID: String
    let storeProductID: String
    let productType: String
    let signedTransactionInfo: String
    let transactionID: String
    let originalTransactionID: String
    let appAccountToken: String?
    let environment: String
    let idempotencyKey: String
    let clientEventTime: Int64
    let reason: String

    init(
        platform: String,
        appID: String,
        accountID: String,
        evidence: IapStoreKitEvidence,
        clientEventTime: Int64,
        reason: String
    ) {
        self.platform = platform
        self.appID = appID
        self.accountID = accountID
        storeProductID = evidence.storeProductID
        productType = evidence.productType
        signedTransactionInfo = evidence.signedTransactionInfo
        transactionID = evidence.transactionID
        originalTransactionID = evidence.originalTransactionID
        appAccountToken = evidence.appAccountToken
        environment = evidence.environment
        idempotencyKey = evidence.idempotencyKey
        self.clientEventTime = clientEventTime
        self.reason = reason
    }

    private enum CodingKeys: String, CodingKey {
        case platform
        case appID = "app_id"
        case accountID = "account_id"
        case storeProductID = "store_product_id"
        case productType = "product_type"
        case signedTransactionInfo = "signed_transaction_info"
        case transactionID = "transaction_id"
        case originalTransactionID = "original_transaction_id"
        case appAccountToken = "app_account_token"
        case environment
        case idempotencyKey = "idempotency_key"
        case clientEventTime = "client_event_time"
        case reason
    }
}
