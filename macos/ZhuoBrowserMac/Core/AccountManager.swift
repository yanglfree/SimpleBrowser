import AppKit
import Combine
import Foundation
import Security

/// Keychain helper for securely storing sensitive authentication tokens.
public enum KeychainHelper {
    private static let service = "com.youdroid.zhuobrowser.mac.auth"
    private static let account = "authToken"
    private static let lock = NSLock()
    private static var unitTestToken: String?

    @discardableResult
    public static func saveToken(_ token: String) -> Bool {
        if RuntimeEnvironment.isRunningUnitTests {
            lock.lock()
            unitTestToken = token
            lock.unlock()
            return true
        }

        guard let data = token.data(using: .utf8) else { return false }

        let matchQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributesToUpdate: [String: Any] = [
            kSecValueData as String: data
        ]
        let updateStatus = SecItemUpdate(matchQuery as CFDictionary, attributesToUpdate as CFDictionary)
        if updateStatus == errSecSuccess {
            return true
        }

        deleteToken()
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        return addStatus == errSecSuccess
    }

    public static func loadToken() -> String? {
        if RuntimeEnvironment.isRunningUnitTests {
            lock.lock()
            defer { lock.unlock() }
            return unitTestToken
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func deleteToken() {
        if RuntimeEnvironment.isRunningUnitTests {
            lock.lock()
            unitTestToken = nil
            lock.unlock()
            return
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// Model representing an authenticated user profile.
public struct UserProfile: Codable, Identifiable, Equatable {
    public let id: String
    public let email: String
    public let displayName: String
    public let avatarUrl: String?
    public let createdAt: Int64?

    public init(id: String, email: String, displayName: String, avatarUrl: String? = nil, createdAt: Int64? = nil) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.avatarUrl = avatarUrl
        self.createdAt = createdAt
    }

    public var resolvedAvatarURL: URL? {
        guard let avatarUrl = avatarUrl, !avatarUrl.isEmpty else { return nil }
        if avatarUrl.hasPrefix("http://") || avatarUrl.hasPrefix("https://") {
            return URL(string: avatarUrl)
        }
        return URL(string: "\(AccountManager.serverBaseURL)\(avatarUrl)")
    }
}

private struct PersistedAccountSession: Codable {
    let token: String
    let profile: UserProfile?
    let lastSyncTime: Date?
    let cachedAvatarUrl: String?
    let cachedAvatarData: Data?
    let boundProfileID: UUID?
}

/// Cloud-backed account and cross-device sync manager.
@MainActor
public final class AccountManager: ObservableObject {
    public static let shared = AccountManager()

    nonisolated public static let serverBaseURL = "https://auth.zhuobrowser.youdroid.top"
    nonisolated public static let fallbackServerBaseURL = "https://zhuobrowser-auth-service.memoryphoto.workers.dev"
    nonisolated public static let maxAvatarDimension: Int = 160
    nonisolated public static let avatarCompressionQuality: CGFloat = 0.75
    nonisolated private static let legacyAvatarByteThreshold: Int = 20 * 1024

    private let tokenKey = "ZhuoBrowser_Account_Token"
    private let userProfileKey = "ZhuoBrowser_Account_Profile"
    private let lastSyncKey = "ZhuoBrowser_Account_LastSync"
    private let cachedAvatarUrlKey = "ZhuoBrowser_Account_AvatarURL"
    private let cachedAvatarDataKey = "ZhuoBrowser_Account_AvatarData"
    private let deviceIDKey = "ZhuoBrowser_Account_DeviceID"
    private let userDefaults: UserDefaults
    private let sessionFileURL: URL?
    private let avatarFileURL: URL?
    private let isPersistenceEnabled: Bool
    private let oauthCoordinator = MacOAuthCoordinator()
    private var cachedAvatarUrl: String?
    private var cachedAvatarData: Data?
    private var settingsSyncTask: Task<Void, Never>?
    private var scopeVersions: [String: Int] = [:]

    @Published public private(set) var currentUser: UserProfile?
    @Published public private(set) var avatarImage: NSImage?
    @Published public private(set) var token: String?
    @Published public private(set) var isLoggedIn: Bool = false
    @Published public private(set) var isSyncing: Bool = false
    @Published public private(set) var lastSyncTime: Date?
    @Published public private(set) var linkedIdentities: [LinkedIdentityInfo] = []
    @Published public private(set) var proEntitlement: CloudProEntitlement?
    @Published public private(set) var remoteDeviceTabs: [RemoteDeviceTabGroup] = []
    @Published public private(set) var boundProfileID: UUID = ProfileManager.defaultFallbackProfileID
    @Published public var errorMessage: String?
    @Published public var syncErrorMessage: String?

    public init(isPersistenceEnabled: Bool = !RuntimeEnvironment.isRunningUnitTests) {
        self.isPersistenceEnabled = isPersistenceEnabled
        if isPersistenceEnabled {
            self.userDefaults = .standard
            if let base = try? FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ) {
                let dir = base.appendingPathComponent("ZhuoBrowserMac", isDirectory: true)
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                self.sessionFileURL = dir.appendingPathComponent("account-session.json")
                self.avatarFileURL = dir.appendingPathComponent("avatar-cache.jpg")
            } else {
                self.sessionFileURL = nil
                self.avatarFileURL = nil
            }
        } else {
            let suite = UserDefaults(suiteName: "com.youdroid.zhuobrowser.mac.unit-tests.\(UUID().uuidString)") ?? .standard
            self.userDefaults = suite
            self.sessionFileURL = nil
            self.avatarFileURL = nil
        }

        reloadStoredSession()
    }

    private var deviceId: String {
        if let existing = userDefaults.string(forKey: deviceIDKey), !existing.isEmpty {
            return existing
        }
        let generated = "mac-\(UUID().uuidString.lowercased())"
        userDefaults.set(generated, forKey: deviceIDKey)
        return generated
    }

    private var deviceName: String {
        Host.current().localizedName ?? "Mac"
    }

    private static var baseURLCandidates: [String] {
        [serverBaseURL, fallbackServerBaseURL]
    }

    private func dataWithFallback(buildRequest: (String) -> URLRequest?) async throws -> (Data, HTTPURLResponse) {
        var lastError: Error?
        for base in Self.baseURLCandidates {
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
        throw lastError ?? NSError(domain: "ZhuoBrowserAuth", code: -1, userInfo: [NSLocalizedDescriptionKey: "网络连接失败"])
    }

    /// Center-crops an image to 1:1 square and downscales it to `maxDimension` px as a compact JPEG.
    nonisolated public static func compressAvatarImage(
        _ image: NSImage,
        maxDimension: Int = AccountManager.maxAvatarDimension,
        compressionQuality: CGFloat = AccountManager.avatarCompressionQuality
    ) -> Data? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        let srcWidth = cgImage.width
        let srcHeight = cgImage.height
        guard srcWidth > 0, srcHeight > 0 else { return nil }

        let cropSide = min(srcWidth, srcHeight)
        let cropX = (srcWidth - cropSide) / 2
        let cropY = (srcHeight - cropSide) / 2
        let cropRect = CGRect(x: cropX, y: cropY, width: cropSide, height: cropSide)
        let squareCGImage = cgImage.cropping(to: cropRect) ?? cgImage

        let targetSide = max(1, min(maxDimension, cropSide))
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: targetSide,
            pixelsHigh: targetSide,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }
        rep.size = NSSize(width: targetSide, height: targetSide)

        NSGraphicsContext.saveGraphicsState()
        if let ctx = NSGraphicsContext(bitmapImageRep: rep) {
            NSGraphicsContext.current = ctx
            ctx.imageInterpolation = .high
            NSColor.white.setFill()
            NSRect(x: 0, y: 0, width: targetSide, height: targetSide).fill()
            let croppedNSImage = NSImage(cgImage: squareCGImage, size: NSSize(width: targetSide, height: targetSide))
            croppedNSImage.draw(
                in: NSRect(x: 0, y: 0, width: targetSide, height: targetSide),
                from: .zero,
                operation: .sourceOver,
                fraction: 1.0
            )
        }
        NSGraphicsContext.restoreGraphicsState()

        return rep.representation(using: .jpeg, properties: [.compressionFactor: compressionQuality])
    }

    nonisolated public static func compressAvatarData(
        _ data: Data,
        maxDimension: Int = AccountManager.maxAvatarDimension,
        compressionQuality: CGFloat = AccountManager.avatarCompressionQuality
    ) -> Data? {
        guard let image = NSImage(data: data) else { return nil }
        return compressAvatarImage(image, maxDimension: maxDimension, compressionQuality: compressionQuality)
    }

    func reloadStoredSession() {
        let fileSession = Self.loadFileSession(from: sessionFileURL)
        let defaultsProfile: UserProfile? = {
            guard let data = userDefaults.data(forKey: userProfileKey) else { return nil }
            return try? JSONDecoder().decode(UserProfile.self, from: data)
        }()
        let resolvedProfile = defaultsProfile ?? fileSession?.profile
        let resolvedSyncTime = (userDefaults.object(forKey: lastSyncKey) as? Date) ?? fileSession?.lastSyncTime

        if let resolvedProfile {
            self.currentUser = resolvedProfile
        }
        if let resolvedSyncTime {
            self.lastSyncTime = resolvedSyncTime
        }
        if let storedProfileID = fileSession?.boundProfileID {
            self.boundProfileID = storedProfileID
        }

        let storedAvatarUrl = userDefaults.string(forKey: cachedAvatarUrlKey) ?? fileSession?.cachedAvatarUrl
        let storedAvatarData = userDefaults.data(forKey: cachedAvatarDataKey)
            ?? fileSession?.cachedAvatarData
            ?? (avatarFileURL.flatMap { try? Data(contentsOf: $0) })

        if let storedAvatarData, let image = NSImage(data: storedAvatarData) {
            self.cachedAvatarUrl = storedAvatarUrl ?? resolvedProfile?.avatarUrl
            self.cachedAvatarData = storedAvatarData
            self.avatarImage = image
        }

        var resolvedToken = KeychainHelper.loadToken()
        if resolvedToken == nil || resolvedToken?.isEmpty == true {
            if let savedToken = userDefaults.string(forKey: tokenKey), !savedToken.isEmpty {
                resolvedToken = savedToken
            } else if let fileToken = fileSession?.token, !fileToken.isEmpty {
                resolvedToken = fileToken
            }
        }

        if let token = resolvedToken, !token.isEmpty {
            self.token = token
            self.isLoggedIn = true
            persistSessionLocally(token: token, profile: self.currentUser)

            if isPersistenceEnabled {
                if let profile = self.currentUser {
                    Task {
                        await fetchAndCacheAvatarIfNeeded(for: profile)
                    }
                }
                Task {
                    await verifySession()
                    await refreshProEntitlement()
                }
            }
        }
    }

    // MARK: - Auth Flows (Email OTP, Email Password, Apple, non-CN Google)

    public func sendEmailOTP(email: String) async -> Bool {
        errorMessage = nil
        let cleaned = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            errorMessage = "请输入邮箱地址"
            return false
        }

        do {
            let payload = try JSONSerialization.data(withJSONObject: ["email": cleaned])
            let (data, http) = try await dataWithFallback { base in
                guard let url = URL(string: "\(base)/api/auth/otp/send") else { return nil }
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = payload
                return req
            }
            let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            if http.statusCode == 200 {
                return true
            }
            errorMessage = json["error"] as? String ?? "验证码发送失败 (HTTP \(http.statusCode))"
        } catch {
            errorMessage = error.localizedDescription
        }
        return false
    }

    public func verifyEmailOTP(email: String, code: String, displayName: String = "") async -> Bool {
        errorMessage = nil
        let body: [String: Any] = [
            "email": email.trimmingCharacters(in: .whitespacesAndNewlines),
            "code": code.trimmingCharacters(in: .whitespacesAndNewlines),
            "displayName": displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            "deviceId": deviceId,
            "deviceName": deviceName,
            "platform": "macos"
        ]
        return await performAuthPost(path: "/api/auth/otp/verify", body: body)
    }

    public func register(email: String, password: String, displayName: String) async -> Bool {
        errorMessage = nil
        let body: [String: Any] = [
            "email": email.trimmingCharacters(in: .whitespacesAndNewlines),
            "password": password,
            "displayName": displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            "deviceId": deviceId,
            "deviceName": deviceName,
            "platform": "macos"
        ]
        return await performAuthPost(path: "/api/auth/register", body: body)
    }

    public func login(email: String, password: String) async -> Bool {
        errorMessage = nil
        let body: [String: Any] = [
            "email": email.trimmingCharacters(in: .whitespacesAndNewlines),
            "password": password,
            "deviceId": deviceId,
            "deviceName": deviceName,
            "platform": "macos"
        ]
        return await performAuthPost(path: "/api/auth/login", body: body)
    }

    public func signInWithApple() async -> Bool {
        errorMessage = nil
        do {
            let native = try await oauthCoordinator.performNativeAppleSignIn()
            var body: [String: Any] = [
                "provider": "apple",
                "idToken": native.identityToken,
                "deviceId": deviceId,
                "deviceName": deviceName,
                "platform": "macos"
            ]
            if let displayName = native.displayName {
                body["displayName"] = displayName
            }
            return await performAuthPost(path: "/api/auth/oauth/native", body: body, bearerToken: self.token)
        } catch {
            // Fallback to browser PKCE OAuth when native Apple Sign-In entitlement is absent in local/DMG build
            do {
                let ticket = try await oauthCoordinator.performWebOAuth(provider: "apple", baseURL: Self.serverBaseURL)
                return await performAuthPost(path: "/api/auth/oauth/exchange", body: ["ticket": ticket])
            } catch let fallbackError {
                errorMessage = fallbackError.localizedDescription
                return false
            }
        }
    }

    public func signInWithGoogle() async -> Bool {
        guard RegionAuthPolicy.isGoogleSignInAvailable() else {
            errorMessage = "当前地区暂不支持 Google 登录"
            return false
        }
        errorMessage = nil
        do {
            let ticket = try await oauthCoordinator.performWebOAuth(provider: "google", baseURL: Self.serverBaseURL)
            return await performAuthPost(path: "/api/auth/oauth/exchange", body: ["ticket": ticket])
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func performAuthPost(path: String, body: [String: Any], bearerToken: String? = nil) async -> Bool {
        guard let payload = try? JSONSerialization.data(withJSONObject: body) else { return false }
        do {
            let (data, httpResponse) = try await dataWithFallback { base in
                guard let url = URL(string: "\(base)\(path)") else { return nil }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                if let bearerToken {
                    request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
                }
                request.httpBody = payload
                return request
            }
            let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            if httpResponse.statusCode == 200 || httpResponse.statusCode == 201 {
                if let receivedToken = json["token"] as? String,
                   let userDict = json["user"] as? [String: Any],
                   let profile = Self.parseUserProfile(userDict) {
                    self.linkedIdentities = Self.parseIdentities(json["identities"])
                    saveSession(token: receivedToken, profile: profile)
                    if isPersistenceEnabled {
                        Task { await refreshProEntitlement() }
                    }
                    return true
                }
            }
            errorMessage = json["error"] as? String ?? "认证失败，请稍后重试"
        } catch {
            errorMessage = error.localizedDescription
        }
        return false
    }

    @discardableResult
    public func unlinkIdentity(provider: String) async -> Bool {
        guard let token = self.token else { return false }
        errorMessage = nil
        do {
            let (data, http) = try await dataWithFallback { base in
                guard let url = URL(string: "\(base)/api/auth/identities/\(provider)") else { return nil }
                var req = URLRequest(url: url)
                req.httpMethod = "DELETE"
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                return req
            }
            let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            if http.statusCode == 200 {
                self.linkedIdentities = Self.parseIdentities(json["identities"])
                return true
            }
            errorMessage = json["error"] as? String ?? "解绑失败"
        } catch {
            errorMessage = error.localizedDescription
        }
        return false
    }

    public func refreshProEntitlement() async {
        guard let token = self.token, isPersistenceEnabled else { return }
        do {
            let (data, http) = try await dataWithFallback { base in
                guard let url = URL(string: "\(base)/api/pro/entitlement") else { return nil }
                var req = URLRequest(url: url)
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                return req
            }
            guard http.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let entDict = json["entitlement"] as? [String: Any],
                  let entData = try? JSONSerialization.data(withJSONObject: entDict),
                  let decoded = try? JSONDecoder().decode(CloudProEntitlement.self, from: entData) else {
                self.proEntitlement = nil
                return
            }
            self.proEntitlement = decoded
        } catch {
            // Keep existing entitlement snapshot on transient error
        }
    }

    public func logout() {
        logout(clearLocalSyncedData: false)
    }

    public func logout(clearLocalSyncedData: Bool) {
        if isPersistenceEnabled, let token = self.token {
            Task {
                _ = try? await dataWithFallback { base in
                    guard let url = URL(string: "\(base)/api/auth/logout") else { return nil }
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    return request
                }
            }
        }

        if clearLocalSyncedData {
            let targetSession = ProfileManager.shared.session(for: boundProfileID)
            targetSession.applySyncResult(folders: [], bookmarks: [], tombstones: [])
        }
        clearLocalSessionState()
    }

    /// Permanently deletes the authenticated user's cloud account, sync data, and avatar,
    /// then clears all local credentials and session files (App Store Guideline 5.1.1(v)).
    @discardableResult
    public func deleteAccount() async -> Bool {
        errorMessage = nil
        guard isLoggedIn, let token = self.token else {
            errorMessage = "当前未登录账号"
            return false
        }

        if !isPersistenceEnabled {
            clearLocalSessionState()
            return true
        }

        do {
            let (data, httpResponse) = try await dataWithFallback { base in
                guard let url = URL(string: "\(base)/api/auth/account") else { return nil }
                var request = URLRequest(url: url)
                request.httpMethod = "DELETE"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                return request
            }
            if httpResponse.statusCode == 200 || httpResponse.statusCode == 401 || httpResponse.statusCode == 404 {
                clearLocalSessionState()
                return true
            }
            let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            errorMessage = json["error"] as? String ?? "账号注销失败 (HTTP \(httpResponse.statusCode))"
            return false
        } catch {
            errorMessage = "账号注销失败：\(error.localizedDescription)"
            return false
        }
    }

    private func clearLocalSessionState() {
        KeychainHelper.deleteToken()
        self.token = nil
        self.currentUser = nil
        self.isLoggedIn = false
        self.linkedIdentities = []
        self.proEntitlement = nil
        self.remoteDeviceTabs = []
        self.scopeVersions = [:]
        self.syncErrorMessage = nil
        clearCachedAvatar()
        self.userDefaults.removeObject(forKey: tokenKey)
        self.userDefaults.removeObject(forKey: userProfileKey)
        if let sessionFileURL {
            try? FileManager.default.removeItem(at: sessionFileURL)
        }
    }

    @discardableResult
    public func uploadAvatar(imageData: Data, mimeType: String = "image/jpeg") async -> Bool {
        errorMessage = nil
        guard let token = self.token, let currentUser = self.currentUser else {
            errorMessage = "尚未登录"
            return false
        }

        let compactData = Self.compressAvatarData(imageData) ?? imageData
        let uploadMimeType = compactData == imageData ? mimeType : "image/jpeg"

        if let optimisticImage = NSImage(data: compactData) {
            self.avatarImage = optimisticImage
        }

        do {
            let (data, httpResponse) = try await dataWithFallback { base in
                guard let url = URL(string: "\(base)/api/user/avatar") else { return nil }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue(uploadMimeType, forHTTPHeaderField: "Content-Type")
                request.setValue("ZhuoBrowserMac/1.0", forHTTPHeaderField: "User-Agent")
                request.httpBody = compactData
                return request
            }

            let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            if httpResponse.statusCode == 200 {
                let returnedAvatarUrl = json["avatarUrl"] as? String
                let resolvedAvatarUrl = returnedAvatarUrl ?? currentUser.avatarUrl
                let updatedProfile = UserProfile(
                    id: currentUser.id,
                    email: currentUser.email,
                    displayName: currentUser.displayName,
                    avatarUrl: resolvedAvatarUrl,
                    createdAt: currentUser.createdAt
                )
                self.currentUser = updatedProfile
                cacheAvatarLocally(data: compactData, for: resolvedAvatarUrl)
                persistSessionLocally(token: token, profile: updatedProfile)
                return true
            } else {
                errorMessage = json["error"] as? String ?? "头像上传失败 (HTTP \(httpResponse.statusCode))"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        return false
    }

    // MARK: - Settings Mapping & Scoped Sync v3

    nonisolated public static func extractUpdatedAt(from dict: [String: Any]) -> Int64 {
        if let number = dict["updatedAt"] as? NSNumber {
            let raw = number.int64Value
            return raw > 0 && raw < 10_000_000_000 ? raw * 1000 : raw
        }
        if let str = dict["updatedAt"] as? String, let parsed = Int64(str) {
            return parsed > 0 && parsed < 10_000_000_000 ? parsed * 1000 : parsed
        }
        return 0
    }

    public func shouldApplyRemoteSettings(_ remoteSettings: [String: Any], to settings: BrowserSettings) -> Bool {
        let remoteUpdatedAt = Self.extractUpdatedAt(from: remoteSettings)
        if settings.hasPendingLocalChanges {
            return remoteUpdatedAt > 0 && remoteUpdatedAt > settings.updatedAt
        }
        if settings.updatedAt == 0 {
            return true
        }
        return remoteUpdatedAt > settings.updatedAt
    }

    public func applySettings(_ dict: [String: Any], to settings: BrowserSettings) {
        applySettingsInternal(dict, to: settings, includeDesktopDeviceSettings: true)
    }

    public func applyRemoteSyncSettings(_ dict: [String: Any], to settings: BrowserSettings) {
        applySettingsInternal(dict, to: settings, includeDesktopDeviceSettings: false)
    }

    private func applySettingsInternal(
        _ dict: [String: Any],
        to settings: BrowserSettings,
        includeDesktopDeviceSettings: Bool
    ) {
        let remoteUpdatedAt = Self.extractUpdatedAt(from: dict)
        settings.performRemoteUpdate(remoteUpdatedAt: remoteUpdatedAt > 0 ? remoteUpdatedAt : nil) { target in
            if let blockAds = dict["blockAds"] as? Bool {
                target.adBlockEnabled = blockAds
            } else if let adBlock = dict["adBlockEnabled"] as? Bool {
                target.adBlockEnabled = adBlock
            }
            if let blockTrackers = dict["blockTrackers"] as? Bool {
                target.cosmeticCleanupEnabled = blockTrackers
            } else if let cosmetic = dict["cosmeticCleanupEnabled"] as? Bool {
                target.cosmeticCleanupEnabled = cosmetic
            }
            if let allowlisted = dict["adBlockAllowlistedHosts"] as? [String] {
                target.adBlockAllowlistedHosts = PersistedBrowserSettings.normalizeHosts(allowlisted)
            }
            if includeDesktopDeviceSettings {
                if let budget = dict["liveWebViewBudget"] as? Int {
                    target.liveWebViewBudget = budget
                }
                if let hibernation = dict["tabHibernationEnabled"] as? Bool {
                    target.tabHibernationEnabled = hibernation
                }
                if let restoreSession = dict["restoreSessionOnLaunch"] as? Bool {
                    target.restoreSessionOnLaunch = restoreSession
                }
            }
            if let quickSites = dict["quickSitesEnabled"] as? Bool {
                target.quickSitesEnabled = quickSites
            }
            if let engineRaw = dict["searchEngine"] as? String,
               let engine = SearchEngine.from(engineRaw) {
                target.searchEngine = engine
            } else if let engineNum = dict["searchEngine"] as? Int {
                switch engineNum {
                case 0: target.searchEngine = .bing
                case 1: target.searchEngine = .baidu
                case 2: target.searchEngine = .google
                case 3: target.searchEngine = .duckDuckGo
                default: break
                }
            }
            if let safeRaw = dict["safeBrowsingLevel"] as? String,
               let safeLevel = SafeBrowsingLevel(rawValue: safeRaw) {
                target.safeBrowsingLevel = safeLevel
            }
            if let alwaysHTTPS = dict["alwaysUseSecureConnections"] as? Bool {
                target.alwaysUseSecureConnections = alwaysHTTPS
            }
            if let leakedPw = dict["leakedPasswordDetectionEnabled"] as? Bool {
                target.leakedPasswordDetectionEnabled = leakedPw
            }
            if let secDNS = dict["secureDNSEnabled"] as? Bool {
                target.secureDNSEnabled = secDNS
            }
            if let dnsProvRaw = dict["secureDNSProvider"] as? String,
               let dnsProv = SecureDNSProvider(rawValue: dnsProvRaw) {
                target.secureDNSProvider = dnsProv
            }
            if let customDNS = dict["customSecureDNSURL"] as? String {
                target.customSecureDNSURL = customDNS
            }
            if let jsJIT = dict["javascriptJITOptimizationEnabled"] as? Bool {
                target.javascriptJITOptimizationEnabled = jsJIT
            }
        }
    }

    public func settingsPayload(from settings: BrowserSettings) -> [String: Any] {
        crossPlatformSettingsPayload(from: settings)
    }

    /// Emits cross-platform user-intent preferences without overwriting device-specific memory budgets.
    public func crossPlatformSettingsPayload(from settings: BrowserSettings) -> [String: Any] {
        let timestamp = settings.updatedAt > 0 ? settings.updatedAt : BrowserSettings.currentTimestampMillis()
        return [
            "adBlockEnabled": settings.adBlockEnabled,
            "blockAds": settings.adBlockEnabled,
            "cosmeticCleanupEnabled": settings.cosmeticCleanupEnabled,
            "blockTrackers": settings.cosmeticCleanupEnabled,
            "adBlockAllowlistedHosts": settings.adBlockAllowlistedHosts,
            "quickSitesEnabled": settings.quickSitesEnabled,
            "searchEngine": settings.searchEngine.rawValue,
            "safeBrowsingLevel": settings.safeBrowsingLevel.rawValue,
            "alwaysUseSecureConnections": settings.alwaysUseSecureConnections,
            "leakedPasswordDetectionEnabled": settings.leakedPasswordDetectionEnabled,
            "secureDNSEnabled": settings.secureDNSEnabled,
            "secureDNSProvider": settings.secureDNSProvider.rawValue,
            "customSecureDNSURL": settings.customSecureDNSURL,
            "javascriptJITOptimizationEnabled": settings.javascriptJITOptimizationEnabled,
            "updatedAt": timestamp
        ]
    }

    /// Schedules a debounced cloud sync whenever the bound profile changes a preference locally.
    public func scheduleSettingsSync(for session: BrowserSession? = nil) {
        guard isPersistenceEnabled, isLoggedIn else { return }
        let targetSession = session ?? ProfileManager.shared.session(for: boundProfileID)
        guard targetSession.profileID == boundProfileID else { return }

        settingsSyncTask?.cancel()
        settingsSyncTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, let self else { return }
            while self.isSyncing {
                try? await Task.sleep(nanoseconds: 150_000_000)
                guard !Task.isCancelled else { return }
            }
            if targetSession.settings.hasPendingLocalChanges {
                await self.syncWithCloud(session: targetSession)
            }
        }
    }

    public func syncWithCloud(session: BrowserSession) async {
        guard isLoggedIn, let token = self.token else { return }
        guard session.profileID == boundProfileID || session.isDefaultProfile else {
            syncErrorMessage = "当前个人资料未绑定云同步账号，为避免数据串写已跳过同步"
            return
        }

        isSyncing = true
        syncErrorMessage = nil
        defer { isSyncing = false }

        var remoteFolders: [BookmarkFolder] = []
        var remoteBookmarks: [BookmarkEntry] = []
        var remoteTombstones: [BookmarkTombstone] = []
        var remoteSettings: [String: Any]?
        var remoteAllowlistedHosts: [String] = []
        var bookmarksBaseVersion = scopeVersions["bookmarks"] ?? 0
        var settingsBaseVersion = scopeVersions["settings"] ?? 0
        var siteControlsBaseVersion = scopeVersions["site_controls"] ?? 0

        // 1. Pull v3 scopes & remote device tabs
        do {
            let encodedDevice = deviceId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? deviceId
            let pullPath = "/api/sync/v3/pull?scopes=bookmarks,settings,site_controls,device_tabs&excludeDeviceId=\(encodedDevice)"
            let (data, httpResp) = try await dataWithFallback { base in
                guard let pullURL = URL(string: "\(base)\(pullPath)") else { return nil }
                var pullReq = URLRequest(url: pullURL)
                pullReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                return pullReq
            }

            if httpResp.statusCode == 401 || httpResp.statusCode == 403 {
                logout()
                syncErrorMessage = "登录凭据已过期，请重新登录"
                return
            }
            guard httpResp.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                syncErrorMessage = "云端拉取失败 (HTTP \(httpResp.statusCode))"
                return
            }

            if let scopes = json["scopes"] as? [String: Any] {
                if let bmScope = scopes["bookmarks"] as? [String: Any] {
                    bookmarksBaseVersion = (bmScope["version"] as? NSNumber)?.intValue ?? 0
                    let parsed = LibraryPolicy.parseRemoteBookmarksPayload(bmScope["payload"])
                    remoteFolders = parsed.folders
                    remoteBookmarks = parsed.bookmarks
                    remoteTombstones = parsed.tombstones
                }
                if let stScope = scopes["settings"] as? [String: Any] {
                    settingsBaseVersion = (stScope["version"] as? NSNumber)?.intValue ?? 0
                    remoteSettings = stScope["payload"] as? [String: Any]
                }
                if let scScope = scopes["site_controls"] as? [String: Any] {
                    siteControlsBaseVersion = (scScope["version"] as? NSNumber)?.intValue ?? 0
                    if let scPayload = scScope["payload"] as? [String: Any],
                       let controls = scPayload["controls"] as? [[String: Any]] {
                        remoteAllowlistedHosts = controls.compactMap { row -> String? in
                            guard let host = row["host"] as? String,
                                  (row["networkBlocking"] as? NSNumber)?.intValue == 2 else { return nil }
                            return host
                        }
                    }
                }
            }

            self.remoteDeviceTabs = Self.parseRemoteDevices(json["remoteDevices"])
        } catch {
            syncErrorMessage = "同步拉取失败：\(error.localizedDescription)"
            return
        }

        // 2. Merge locally & push with CAS conflict retry
        var attempts = 0
        var pushedSettingsTimestamp: Int64 = 0
        while attempts < 3 {
            attempts += 1
            let mergeResult = LibraryPolicy.mergeSync(
                localFolders: session.bookmarkFolders,
                localBookmarks: session.bookmarks,
                localTombstones: session.tombstones,
                remoteFolders: remoteFolders,
                remoteBookmarks: remoteBookmarks,
                remoteTombstones: remoteTombstones
            )
            session.applySyncResult(
                folders: mergeResult.mergedFolders,
                bookmarks: mergeResult.mergedBookmarks,
                tombstones: mergeResult.mergedTombstones
            )

            if let remoteSettings, shouldApplyRemoteSettings(remoteSettings, to: session.settings) {
                applyRemoteSyncSettings(remoteSettings, to: session.settings)
                session.applyContentProtectionSettingsToAllTabs()
            }

            if !remoteAllowlistedHosts.isEmpty {
                let mergedHosts = PersistedBrowserSettings.normalizeHosts(
                    session.settings.adBlockAllowlistedHosts + remoteAllowlistedHosts
                )
                if mergedHosts != session.settings.adBlockAllowlistedHosts {
                    session.settings.performRemoteUpdate(remoteUpdatedAt: BrowserSettings.currentTimestampMillis()) { target in
                        target.adBlockAllowlistedHosts = mergedHosts
                    }
                }
            }

            let structuredBookmarksPayload = LibraryPolicy.encodeBookmarksPayload(
                folders: session.bookmarkFolders,
                bookmarks: session.bookmarks,
                tombstones: session.tombstones
            )
            let localSettings = crossPlatformSettingsPayload(from: session.settings)
            pushedSettingsTimestamp = Self.extractUpdatedAt(from: localSettings)
            let nowMs = BrowserSettings.currentTimestampMillis()
            let siteControlsPayload: [String: Any] = [
                "controls": session.settings.adBlockAllowlistedHosts.map { host -> [String: Any] in
                    [
                        "host": host,
                        "networkBlocking": 2,
                        "trackerBlocking": 0,
                        "cosmeticCleanup": 0,
                        "autoReader": 0,
                        "darkMode": 0,
                        "desktopUserAgent": 0,
                        "updatedAt": nowMs
                    ]
                },
                "tombstones": [],
                "updatedAt": nowMs
            ]

            let pushBody: [String: Any] = [
                "deviceId": deviceId,
                "deviceName": deviceName,
                "platform": "macos",
                "scopes": [
                    "bookmarks": [
                        "baseVersion": bookmarksBaseVersion,
                        "encryptionMode": "none",
                        "payload": structuredBookmarksPayload
                    ],
                    "settings": [
                        "baseVersion": settingsBaseVersion,
                        "encryptionMode": "none",
                        "payload": localSettings
                    ],
                    "site_controls": [
                        "baseVersion": siteControlsBaseVersion,
                        "encryptionMode": "none",
                        "payload": siteControlsPayload
                    ]
                ],
                "deviceTabs": RegionAuthPolicy.sanitizeDeviceTabs(session.tabs)
            ]

            guard let bodyData = try? JSONSerialization.data(withJSONObject: pushBody) else {
                syncErrorMessage = "推送数据序列化失败"
                return
            }

            do {
                let (data, httpResp) = try await dataWithFallback { base in
                    guard let pushURL = URL(string: "\(base)/api/sync/v3/push") else { return nil }
                    var pushReq = URLRequest(url: pushURL)
                    pushReq.httpMethod = "POST"
                    pushReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    pushReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    pushReq.httpBody = bodyData
                    return pushReq
                }

                if httpResp.statusCode == 401 || httpResp.statusCode == 403 {
                    logout()
                    syncErrorMessage = "登录凭据已过期，请重新登录"
                    return
                }

                let respJson = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
                if let applied = respJson["appliedScopes"] as? [String: [String: Any]] {
                    for (scope, info) in applied {
                        if let v = (info["version"] as? NSNumber)?.intValue {
                            scopeVersions[scope] = v
                        }
                    }
                }

                if httpResp.statusCode == 409,
                   let conflicts = respJson["conflicts"] as? [[String: Any]] {
                    for conflict in conflicts {
                        guard let scope = conflict["scope"] as? String else { continue }
                        let currentVersion = (conflict["currentVersion"] as? NSNumber)?.intValue ?? 0
                        if scope == "bookmarks" {
                            bookmarksBaseVersion = currentVersion
                            let parsed = LibraryPolicy.parseRemoteBookmarksPayload(conflict["currentPayload"])
                            remoteFolders = parsed.folders
                            remoteBookmarks = parsed.bookmarks
                            remoteTombstones = parsed.tombstones
                        } else if scope == "settings" {
                            settingsBaseVersion = currentVersion
                            remoteSettings = conflict["currentPayload"] as? [String: Any]
                        } else if scope == "site_controls" {
                            siteControlsBaseVersion = currentVersion
                        }
                    }
                    continue
                }

                guard httpResp.statusCode == 200 else {
                    syncErrorMessage = "云端推送失败 (HTTP \(httpResp.statusCode))"
                    return
                }

                break
            } catch {
                syncErrorMessage = "同步推送失败：\(error.localizedDescription)"
                return
            }
        }

        if session.settings.updatedAt <= pushedSettingsTimestamp {
            session.settings.markSynced(at: pushedSettingsTimestamp)
        }
        let now = Date()
        self.lastSyncTime = now
        self.userDefaults.set(now, forKey: lastSyncKey)
        persistSessionLocally(token: token, profile: self.currentUser)
        self.syncErrorMessage = nil
    }

    private func verifySession() async {
        guard let token = self.token else { return }

        do {
            let (data, httpResponse) = try await dataWithFallback { base in
                guard let url = URL(string: "\(base)/api/auth/me") else { return nil }
                var request = URLRequest(url: url)
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                return request
            }

            if httpResponse.statusCode == 200 {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let userDict = json["user"] as? [String: Any],
                   let profile = Self.parseUserProfile(userDict) {
                    self.currentUser = profile
                    self.isLoggedIn = true
                    self.linkedIdentities = Self.parseIdentities(json["identities"])
                    persistSessionLocally(token: token, profile: profile)
                    await fetchAndCacheAvatarIfNeeded(for: profile)
                }
            } else if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                logout()
            } else {
                syncErrorMessage = "账号服务暂时不可用 (HTTP \(httpResponse.statusCode))，已保留本地登录状态"
            }
        } catch {
            // Network failure: keep local offline session intact
        }
    }

    func saveSession(token: String, profile: UserProfile) {
        self.token = token
        self.currentUser = profile
        self.isLoggedIn = true
        persistSessionLocally(token: token, profile: profile)
        if isPersistenceEnabled {
            Task {
                await fetchAndCacheAvatarIfNeeded(for: profile)
            }
        }
    }

    func cacheAvatarLocally(data: Data, for avatarUrl: String?) {
        guard let image = NSImage(data: data) else { return }
        self.cachedAvatarUrl = avatarUrl
        self.cachedAvatarData = data
        self.avatarImage = image
        if let avatarUrl {
            self.userDefaults.set(avatarUrl, forKey: cachedAvatarUrlKey)
        } else {
            self.userDefaults.removeObject(forKey: cachedAvatarUrlKey)
        }
        self.userDefaults.set(data, forKey: cachedAvatarDataKey)
        if isPersistenceEnabled, let avatarFileURL {
            try? data.write(to: avatarFileURL, options: .atomic)
        }
    }

    private func clearCachedAvatar() {
        self.avatarImage = nil
        self.cachedAvatarUrl = nil
        self.cachedAvatarData = nil
        self.userDefaults.removeObject(forKey: cachedAvatarUrlKey)
        self.userDefaults.removeObject(forKey: cachedAvatarDataKey)
        if let avatarFileURL {
            try? FileManager.default.removeItem(at: avatarFileURL)
        }
    }

    private func fetchAndCacheAvatarIfNeeded(for profile: UserProfile) async {
        guard let avatarUrl = profile.avatarUrl, !avatarUrl.isEmpty, let remoteURL = profile.resolvedAvatarURL else {
            clearCachedAvatar()
            return
        }

        if self.cachedAvatarUrl == avatarUrl,
           let existingData = self.cachedAvatarData,
           self.avatarImage != nil,
           existingData.count <= Self.legacyAvatarByteThreshold {
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: remoteURL)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  !data.isEmpty else {
                return
            }

            let compactData = Self.compressAvatarData(data) ?? data
            cacheAvatarLocally(data: compactData, for: avatarUrl)
            if let token = self.token {
                persistSessionLocally(token: token, profile: self.currentUser)
            }

            if data.count > Self.legacyAvatarByteThreshold && compactData.count < data.count {
                _ = await uploadAvatar(imageData: compactData, mimeType: "image/jpeg")
            }
        } catch {
            // Keep existing cached avatar if network fails
        }
    }

    private func persistSessionLocally(token: String, profile: UserProfile?) {
        _ = KeychainHelper.saveToken(token)
        self.userDefaults.set(token, forKey: tokenKey)
        if let profile, let data = try? JSONEncoder().encode(profile) {
            self.userDefaults.set(data, forKey: userProfileKey)
        }
        if isPersistenceEnabled, let sessionFileURL {
            let persisted = PersistedAccountSession(
                token: token,
                profile: profile,
                lastSyncTime: self.lastSyncTime,
                cachedAvatarUrl: self.cachedAvatarUrl,
                cachedAvatarData: self.cachedAvatarData,
                boundProfileID: self.boundProfileID
            )
            if let encoded = try? JSONEncoder().encode(persisted) {
                try? encoded.write(to: sessionFileURL, options: .atomic)
            }
        }
    }

    private static func loadFileSession(from url: URL?) -> PersistedAccountSession? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PersistedAccountSession.self, from: data)
    }

    private static func parseUserProfile(_ dict: [String: Any]) -> UserProfile? {
        guard let userId = dict["id"] as? String,
              let userEmail = dict["email"] as? String,
              let userDisplayName = dict["displayName"] as? String else {
            return nil
        }
        let userAvatarUrl = dict["avatarUrl"] as? String ?? dict["avatar_url"] as? String
        return UserProfile(id: userId, email: userEmail, displayName: userDisplayName, avatarUrl: userAvatarUrl)
    }

    private static func parseIdentities(_ raw: Any?) -> [LinkedIdentityInfo] {
        guard let list = raw as? [[String: Any]] else { return [] }
        return list.compactMap { item in
            guard let provider = item["provider"] as? String else { return nil }
            let email = item["email"] as? String
            let verified = item["emailVerified"] as? Bool ?? false
            return LinkedIdentityInfo(provider: provider, email: email, emailVerified: verified)
        }
    }

    private static func parseRemoteDevices(_ raw: Any?) -> [RemoteDeviceTabGroup] {
        guard let list = raw as? [[String: Any]],
              let data = try? JSONSerialization.data(withJSONObject: list),
              let decoded = try? JSONDecoder().decode([RemoteDeviceTabGroup].self, from: data) else {
            return []
        }
        return decoded
    }
}
