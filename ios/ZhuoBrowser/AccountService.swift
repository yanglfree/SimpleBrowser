import AuthenticationServices
import Foundation
import Security
import UIKit

enum IosAuthKeychain {
    private static let service = "com.youdroid.zhuobrowser.auth"
    private static let account = "authToken"

    @discardableResult
    static func saveToken(_ token: String) -> Bool {
        guard let data = token.data(using: .utf8) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary) == errSecSuccess {
            return true
        }
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    static func loadToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func deleteToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

@MainActor
private final class IosOAuthCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding, ASWebAuthenticationPresentationContextProviding {
    static let callbackScheme = "zhuobrowser-auth"
    static let callbackURL = "zhuobrowser-auth://oauth/callback"

    private var appleContinuation: CheckedContinuation<(idToken: String, displayName: String?), Error>?
    private var webAuthSession: ASWebAuthenticationSession?

    func performNativeAppleSignIn() async throws -> (idToken: String, displayName: String?) {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        return try await withCheckedThrowingContinuation { continuation in
            self.appleContinuation = continuation
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    func performWebOAuth(provider: String, baseURL: String) async throws -> String {
        guard var components = URLComponents(string: "\(baseURL)/api/auth/oauth/\(provider)/start") else {
            throw NSError(domain: "ZhuoBrowserAuth", code: -1, userInfo: [NSLocalizedDescriptionKey: "无效的认证地址"])
        }
        components.queryItems = [
            URLQueryItem(name: "platform", value: "ios"),
            URLQueryItem(name: "client_redirect_uri", value: Self.callbackURL)
        ]
        guard let startURL = components.url else {
            throw NSError(domain: "ZhuoBrowserAuth", code: -1, userInfo: [NSLocalizedDescriptionKey: "无效的认证地址"])
        }

        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: startURL, callbackURLScheme: Self.callbackScheme) { [weak self] callbackURL, error in
                self?.webAuthSession = nil
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let callbackURL,
                      let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems else {
                    continuation.resume(throwing: NSError(domain: "ZhuoBrowserAuth", code: -2, userInfo: [NSLocalizedDescriptionKey: "未收到授权回调"]))
                    return
                }
                if let err = items.first(where: { $0.name == "error" })?.value {
                    continuation.resume(throwing: NSError(domain: "ZhuoBrowserAuth", code: -3, userInfo: [NSLocalizedDescriptionKey: "授权失败: \(err)"]))
                    return
                }
                guard let ticket = items.first(where: { $0.name == "ticket" })?.value, !ticket.isEmpty else {
                    continuation.resume(throwing: NSError(domain: "ZhuoBrowserAuth", code: -4, userInfo: [NSLocalizedDescriptionKey: "授权票据为空"]))
                    return
                }
                continuation.resume(returning: ticket)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.webAuthSession = session
            if !session.start() {
                self.webAuthSession = nil
                continuation.resume(throwing: NSError(domain: "ZhuoBrowserAuth", code: -5, userInfo: [NSLocalizedDescriptionKey: "无法启动系统认证窗口"]))
            }
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let data = credential.identityToken,
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty else {
            appleContinuation?.resume(throwing: NSError(domain: "ZhuoBrowserAuth", code: -10, userInfo: [NSLocalizedDescriptionKey: "Apple 登录未返回身份令牌"]))
            appleContinuation = nil
            return
        }
        let formatter = PersonNameComponentsFormatter()
        let name = credential.fullName.map { formatter.string(from: $0).trimmingCharacters(in: .whitespacesAndNewlines) }
        appleContinuation?.resume(returning: (token, name?.isEmpty == false ? name : nil))
        appleContinuation = nil
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        appleContinuation?.resume(throwing: error)
        appleContinuation = nil
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        Self.activeWindow()
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        Self.activeWindow()
    }

    private static func activeWindow() -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.first?.windows.first ?? UIWindow()
    }
}

@MainActor
final class AccountService: ObservableObject {
    static let shared = AccountService()

    static let primaryBaseURL = "https://auth.zhuobrowser.youdroid.top"
    static let fallbackBaseURL = "https://zhuobrowser-auth-service.memoryphoto.workers.dev"

    @Published private(set) var currentUser: CloudUserProfile?
    @Published private(set) var token: String?
    @Published private(set) var isLoggedIn = false
    @Published private(set) var linkedIdentities: [LinkedIdentityRecord] = []
    @Published private(set) var cloudProEntitlement: ProEntitlement?
    @Published private(set) var isSyncing = false
    @Published private(set) var lastSyncTime: Date?
    @Published private(set) var remoteDeviceTabs: [RemoteDeviceTabGroup] = []
    @Published var errorMessage: String?
    @Published var syncErrorMessage: String?

    private let defaults = UserDefaults.standard
    private let profileKey = "zhuobrowser.account.profile"
    private let tokenFallbackKey = "zhuobrowser.account.token"
    private let deviceIDKey = "zhuobrowser.account.device-id"
    private let lastSyncKey = "zhuobrowser.account.last-sync"
    private let oauth = IosOAuthCoordinator()
    var scopeVersions: [String: Int] = [:]

    private init() {
        restoreSession()
    }

    var deviceId: String {
        if let existing = defaults.string(forKey: deviceIDKey), !existing.isEmpty {
            return existing
        }
        let generated = "ios-\(UUID().uuidString.lowercased())"
        defaults.set(generated, forKey: deviceIDKey)
        return generated
    }

    var deviceName: String {
        UIDevice.current.name
    }

    func restoreSession() {
        if let data = defaults.data(forKey: profileKey),
           let profile = try? JSONDecoder().decode(CloudUserProfile.self, from: data) {
            currentUser = profile
        }
        lastSyncTime = defaults.object(forKey: lastSyncKey) as? Date
        let loadedToken = IosAuthKeychain.loadToken() ?? defaults.string(forKey: tokenFallbackKey)
        if let loadedToken, !loadedToken.isEmpty {
            token = loadedToken
            isLoggedIn = true
            Task { await verifyMe() }
        }
    }

    func dataWithFallback(buildRequest: (String) -> URLRequest?) async throws -> (Data, HTTPURLResponse) {
        var lastError: Error?
        for base in [Self.primaryBaseURL, Self.fallbackBaseURL] {
            guard let request = buildRequest(base) else { continue }
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse {
                    return (data, http)
                }
            } catch {
                lastError = error
            }
        }
        throw lastError ?? NSError(domain: "ZhuoBrowserAuth", code: -1, userInfo: [NSLocalizedDescriptionKey: "网络请求失败"])
    }

    func sendEmailOTP(email: String) async -> Bool {
        errorMessage = nil
        let cleaned = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            errorMessage = "请输入邮箱地址"
            return false
        }
        do {
            let body = try JSONSerialization.data(withJSONObject: ["email": cleaned])
            let (data, http) = try await dataWithFallback { base in
                guard let url = URL(string: "\(base)/api/auth/otp/send") else { return nil }
                var req = URLRequest(url: url, timeoutInterval: 15)
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = body
                return req
            }
            let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            if http.statusCode == 200 { return true }
            errorMessage = json["error"] as? String ?? "验证码发送失败"
        } catch {
            errorMessage = error.localizedDescription
        }
        return false
    }

    func verifyEmailOTP(email: String, code: String, displayName: String = "") async -> Bool {
        await performAuthPost(path: "/api/auth/otp/verify", body: [
            "email": email.trimmingCharacters(in: .whitespacesAndNewlines),
            "code": code.trimmingCharacters(in: .whitespacesAndNewlines),
            "displayName": displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            "deviceId": deviceId,
            "deviceName": deviceName,
            "platform": "ios"
        ])
    }

    func login(email: String, password: String) async -> Bool {
        await performAuthPost(path: "/api/auth/login", body: [
            "email": email.trimmingCharacters(in: .whitespacesAndNewlines),
            "password": password,
            "deviceId": deviceId,
            "deviceName": deviceName,
            "platform": "ios"
        ])
    }

    func register(email: String, password: String, displayName: String) async -> Bool {
        await performAuthPost(path: "/api/auth/register", body: [
            "email": email.trimmingCharacters(in: .whitespacesAndNewlines),
            "password": password,
            "displayName": displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            "deviceId": deviceId,
            "deviceName": deviceName,
            "platform": "ios"
        ])
    }

    func signInWithApple() async -> Bool {
        errorMessage = nil
        do {
            let native = try await oauth.performNativeAppleSignIn()
            var body: [String: Any] = [
                "provider": "apple",
                "idToken": native.idToken,
                "deviceId": deviceId,
                "deviceName": deviceName,
                "platform": "ios"
            ]
            if let displayName = native.displayName {
                body["displayName"] = displayName
            }
            return await performAuthPost(path: "/api/auth/oauth/native", body: body, bearerToken: token)
        } catch {
            do {
                let ticket = try await oauth.performWebOAuth(provider: "apple", baseURL: Self.primaryBaseURL)
                return await performAuthPost(path: "/api/auth/oauth/exchange", body: ["ticket": ticket])
            } catch let fallbackError {
                errorMessage = fallbackError.localizedDescription
                return false
            }
        }
    }

    func signInWithGoogle() async -> Bool {
        guard RegionAuthPolicy.isGoogleSignInAvailable() else {
            errorMessage = "当前地区暂不支持 Google 登录"
            return false
        }
        errorMessage = nil
        do {
            let ticket = try await oauth.performWebOAuth(provider: "google", baseURL: Self.primaryBaseURL)
            return await performAuthPost(path: "/api/auth/oauth/exchange", body: ["ticket": ticket])
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func performAuthPost(path: String, body: [String: Any], bearerToken: String? = nil) async -> Bool {
        errorMessage = nil
        guard let payload = try? JSONSerialization.data(withJSONObject: body) else { return false }
        do {
            let (data, http) = try await dataWithFallback { base in
                guard let url = URL(string: "\(base)\(path)") else { return nil }
                var req = URLRequest(url: url, timeoutInterval: 20)
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                if let bearerToken {
                    req.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
                }
                req.httpBody = payload
                return req
            }
            let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            if (200..<300).contains(http.statusCode),
               let receivedToken = json["token"] as? String,
               let userDict = json["user"] as? [String: Any],
               let profile = Self.decodeProfile(userDict) {
                self.token = receivedToken
                self.currentUser = profile
                self.isLoggedIn = true
                self.linkedIdentities = Self.decodeIdentities(json["identities"])
                persistLocally(token: receivedToken, profile: profile)
                await bindCurrentInstallForPro()
                _ = await fetchCloudProEntitlement()
                return true
            }
            errorMessage = json["error"] as? String ?? "认证失败"
        } catch {
            errorMessage = error.localizedDescription
        }
        return false
    }

    func unlinkIdentity(provider: String) async {
        guard let token else { return }
        do {
            let (data, http) = try await dataWithFallback { base in
                guard let url = URL(string: "\(base)/api/auth/identities/\(provider)") else { return nil }
                var req = URLRequest(url: url, timeoutInterval: 15)
                req.httpMethod = "DELETE"
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                return req
            }
            let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            if http.statusCode == 200 {
                linkedIdentities = Self.decodeIdentities(json["identities"])
            } else {
                errorMessage = json["error"] as? String ?? "解绑失败"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func bindCurrentInstallForPro() async {
        guard let token else { return }
        let installID = await IapEntitlementAPI.shared.currentInstallID()
        guard let payload = try? JSONSerialization.data(withJSONObject: [
            "platform": "ios",
            "installId": installID
        ]) else { return }
        _ = try? await dataWithFallback { base in
            guard let url = URL(string: "\(base)/api/pro/bind") else { return nil }
            var req = URLRequest(url: url, timeoutInterval: 15)
            req.httpMethod = "POST"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = payload
            return req
        }
    }

    func fetchCloudProEntitlement() async -> ProEntitlement? {
        guard let token else { return nil }
        do {
            let (data, http) = try await dataWithFallback { base in
                guard let url = URL(string: "\(base)/api/pro/entitlement") else { return nil }
                var req = URLRequest(url: url, timeoutInterval: 15)
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                return req
            }
            guard http.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let ent = json["entitlement"] as? [String: Any],
                  let active = ent["active"] as? Bool, active,
                  let productID = ent["productId"] as? String else {
                cloudProEntitlement = nil
                return nil
            }
            let resolvedPlan = ProPlan(rawValue: ent["plan"] as? String ?? "") ?? ProCatalog.plan(for: productID) ?? .yearly
            let resolvedProductID: String = {
                if ProCatalog.plan(for: productID) == resolvedPlan { return productID }
                switch resolvedPlan {
                case .monthly: return ProCatalog.monthlyProductID
                case .lifetime: return ProCatalog.lifetimeProductID
                case .yearly: return ProCatalog.yearlyProductID
                }
            }()
            let decoded = ProEntitlement(
                active: true,
                scope: ent["scope"] as? String ?? "pro",
                plan: resolvedPlan,
                productID: resolvedProductID,
                expiresAt: (ent["expiresAt"] as? NSNumber)?.doubleValue ?? 0,
                source: ent["source"] as? String ?? "cloud_sync",
                verifiedAt: (ent["verifiedAt"] as? NSNumber)?.doubleValue ?? (Date().timeIntervalSince1970 * 1000)
            )
            cloudProEntitlement = decoded
            return decoded
        } catch {
            return nil
        }
    }

    func logout() {
        if let token {
            Task {
                _ = try? await dataWithFallback { base in
                    guard let url = URL(string: "\(base)/api/auth/logout") else { return nil }
                    var req = URLRequest(url: url)
                    req.httpMethod = "POST"
                    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    return req
                }
            }
        }
        clearLocalSession()
    }

    func deleteAccount() async -> Bool {
        guard let token else { return false }
        errorMessage = nil
        do {
            let (data, http) = try await dataWithFallback { base in
                guard let url = URL(string: "\(base)/api/auth/account") else { return nil }
                var req = URLRequest(url: url, timeoutInterval: 20)
                req.httpMethod = "DELETE"
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                return req
            }
            if http.statusCode == 200 || http.statusCode == 401 || http.statusCode == 404 {
                clearLocalSession()
                return true
            }
            let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            errorMessage = json["error"] as? String ?? "注销失败"
        } catch {
            errorMessage = error.localizedDescription
        }
        return false
    }

    func updateSyncState(syncing: Bool? = nil, remoteTabs: [RemoteDeviceTabGroup]? = nil, error: String? = nil, syncedNow: Bool = false) {
        if let syncing { isSyncing = syncing }
        if let remoteTabs { remoteDeviceTabs = remoteTabs }
        syncErrorMessage = error
        if syncedNow {
            let now = Date()
            lastSyncTime = now
            defaults.set(now, forKey: lastSyncKey)
        }
    }

    private func verifyMe() async {
        guard let token else { return }
        do {
            let (data, http) = try await dataWithFallback { base in
                guard let url = URL(string: "\(base)/api/auth/me") else { return nil }
                var req = URLRequest(url: url, timeoutInterval: 15)
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                return req
            }
            if http.statusCode == 200,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let userDict = json["user"] as? [String: Any],
               let profile = Self.decodeProfile(userDict) {
                currentUser = profile
                linkedIdentities = Self.decodeIdentities(json["identities"])
                persistLocally(token: token, profile: profile)
                await bindCurrentInstallForPro()
                _ = await fetchCloudProEntitlement()
            } else if http.statusCode == 401 || http.statusCode == 403 {
                clearLocalSession()
            }
        } catch {
            // Keep offline login state
        }
    }

    private func persistLocally(token: String, profile: CloudUserProfile) {
        _ = IosAuthKeychain.saveToken(token)
        defaults.set(token, forKey: tokenFallbackKey)
        if let data = try? JSONEncoder().encode(profile) {
            defaults.set(data, forKey: profileKey)
        }
    }

    private func clearLocalSession() {
        IosAuthKeychain.deleteToken()
        defaults.removeObject(forKey: tokenFallbackKey)
        defaults.removeObject(forKey: profileKey)
        token = nil
        currentUser = nil
        isLoggedIn = false
        linkedIdentities = []
        cloudProEntitlement = nil
        remoteDeviceTabs = []
        scopeVersions = [:]
        syncErrorMessage = nil
    }

    private static func decodeProfile(_ dict: [String: Any]) -> CloudUserProfile? {
        guard let id = dict["id"] as? String,
              let email = dict["email"] as? String,
              let displayName = dict["displayName"] as? String else { return nil }
        return CloudUserProfile(id: id, email: email, displayName: displayName, avatarUrl: dict["avatarUrl"] as? String)
    }

    private static func decodeIdentities(_ raw: Any?) -> [LinkedIdentityRecord] {
        guard let list = raw as? [[String: Any]] else { return [] }
        return list.compactMap { item in
            guard let provider = item["provider"] as? String else { return nil }
            return LinkedIdentityRecord(
                provider: provider,
                email: item["email"] as? String,
                emailVerified: item["emailVerified"] as? Bool ?? false
            )
        }
    }
}
