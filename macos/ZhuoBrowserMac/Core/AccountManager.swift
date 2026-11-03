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
}

/// Cloud-backed account and cross-device sync manager.
@MainActor
public final class AccountManager: ObservableObject {
    public static let shared = AccountManager()

    nonisolated public static let serverBaseURL = "https://zhuobrowser-auth-service.memoryphoto.workers.dev"
    nonisolated public static let maxAvatarDimension: Int = 160
    nonisolated public static let avatarCompressionQuality: CGFloat = 0.75
    nonisolated private static let legacyAvatarByteThreshold: Int = 20 * 1024

    private let tokenKey = "ZhuoBrowser_Account_Token"
    private let userProfileKey = "ZhuoBrowser_Account_Profile"
    private let lastSyncKey = "ZhuoBrowser_Account_LastSync"
    private let cachedAvatarUrlKey = "ZhuoBrowser_Account_AvatarURL"
    private let cachedAvatarDataKey = "ZhuoBrowser_Account_AvatarData"
    private let userDefaults: UserDefaults
    private let sessionFileURL: URL?
    private let avatarFileURL: URL?
    private let isPersistenceEnabled: Bool
    private var cachedAvatarUrl: String?
    private var cachedAvatarData: Data?
    private var settingsSyncTask: Task<Void, Never>?

    @Published public private(set) var currentUser: UserProfile?
    @Published public private(set) var avatarImage: NSImage?
    @Published public private(set) var token: String?
    @Published public private(set) var isLoggedIn: Bool = false
    @Published public private(set) var isSyncing: Bool = false
    @Published public private(set) var lastSyncTime: Date?
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

    /// Downscales and compresses raw image data into a compact square avatar JPEG.
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
                }
            }
        }
    }

    public func register(email: String, password: String, displayName: String) async -> Bool {
        errorMessage = nil
        guard let url = URL(string: "\(Self.serverBaseURL)/api/auth/register") else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "email": email.trimmingCharacters(in: .whitespacesAndNewlines),
            "password": password,
            "displayName": displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        ]

        guard let payload = try? JSONSerialization.data(withJSONObject: body) else { return false }
        request.httpBody = payload

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return false }

            let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]

            if httpResponse.statusCode == 201 || httpResponse.statusCode == 200 {
                if let receivedToken = json["token"] as? String,
                   let userDict = json["user"] as? [String: Any],
                   let userId = userDict["id"] as? String,
                   let userEmail = userDict["email"] as? String,
                   let userDisplayName = userDict["displayName"] as? String {
                    let userAvatarUrl = userDict["avatarUrl"] as? String ?? userDict["avatar_url"] as? String
                    let profile = UserProfile(id: userId, email: userEmail, displayName: userDisplayName, avatarUrl: userAvatarUrl)
                    saveSession(token: receivedToken, profile: profile)
                    return true
                }
            } else {
                errorMessage = json["error"] as? String ?? "注册失败，请稍后重试"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        return false
    }

    public func login(email: String, password: String) async -> Bool {
        errorMessage = nil
        guard let url = URL(string: "\(Self.serverBaseURL)/api/auth/login") else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "email": email.trimmingCharacters(in: .whitespacesAndNewlines),
            "password": password
        ]

        guard let payload = try? JSONSerialization.data(withJSONObject: body) else { return false }
        request.httpBody = payload

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return false }

            let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]

            if httpResponse.statusCode == 200 {
                if let receivedToken = json["token"] as? String,
                   let userDict = json["user"] as? [String: Any],
                   let userId = userDict["id"] as? String,
                   let userEmail = userDict["email"] as? String,
                   let userDisplayName = userDict["displayName"] as? String {
                    let userAvatarUrl = userDict["avatarUrl"] as? String ?? userDict["avatar_url"] as? String
                    let profile = UserProfile(id: userId, email: userEmail, displayName: userDisplayName, avatarUrl: userAvatarUrl)
                    saveSession(token: receivedToken, profile: profile)
                    return true
                }
            } else {
                errorMessage = json["error"] as? String ?? "账号或密码错误"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        return false
    }

    public func logout() {
        if isPersistenceEnabled,
           let token = self.token,
           let url = URL(string: "\(Self.serverBaseURL)/api/auth/logout") {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            Task {
                _ = try? await URLSession.shared.data(for: request)
            }
        }

        KeychainHelper.deleteToken()
        self.token = nil
        self.currentUser = nil
        self.isLoggedIn = false
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
        guard let url = URL(string: "\(Self.serverBaseURL)/api/user/avatar") else {
            errorMessage = "上传地址无效"
            return false
        }

        let compactData = Self.compressAvatarData(imageData) ?? imageData
        let uploadMimeType = compactData == imageData ? mimeType : "image/jpeg"

        if let optimisticImage = NSImage(data: compactData) {
            self.avatarImage = optimisticImage
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(uploadMimeType, forHTTPHeaderField: "Content-Type")
        request.setValue("ZhuoBrowserMac/1.0", forHTTPHeaderField: "User-Agent")
        request.httpBody = compactData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                errorMessage = "未收到服务器响应"
                return false
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

    nonisolated public static func extractUpdatedAt(from dict: [String: Any]) -> Int64 {
        if let number = dict["updatedAt"] as? NSNumber {
            return number.int64Value
        }
        if let str = dict["updatedAt"] as? String, let parsed = Int64(str) {
            return parsed
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
        let remoteUpdatedAt = Self.extractUpdatedAt(from: dict)
        settings.performRemoteUpdate(remoteUpdatedAt: remoteUpdatedAt > 0 ? remoteUpdatedAt : nil) { target in
            if let adBlock = dict["adBlockEnabled"] as? Bool {
                target.adBlockEnabled = adBlock
            }
            if let cosmetic = dict["cosmeticCleanupEnabled"] as? Bool {
                target.cosmeticCleanupEnabled = cosmetic
            }
            if let budget = dict["liveWebViewBudget"] as? Int {
                target.liveWebViewBudget = budget
            }
            if let hibernation = dict["tabHibernationEnabled"] as? Bool {
                target.tabHibernationEnabled = hibernation
            }
            if let quickSites = dict["quickSitesEnabled"] as? Bool {
                target.quickSitesEnabled = quickSites
            }
            if let restoreSession = dict["restoreSessionOnLaunch"] as? Bool {
                target.restoreSessionOnLaunch = restoreSession
            }
            if let engineRaw = dict["searchEngine"] as? String,
               let engine = SearchEngine.from(engineRaw) {
                target.searchEngine = engine
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
        let timestamp = settings.updatedAt > 0 ? settings.updatedAt : BrowserSettings.currentTimestampMillis()
        return [
            "adBlockEnabled": settings.adBlockEnabled,
            "cosmeticCleanupEnabled": settings.cosmeticCleanupEnabled,
            "liveWebViewBudget": settings.liveWebViewBudget,
            "tabHibernationEnabled": settings.tabHibernationEnabled,
            "quickSitesEnabled": settings.quickSitesEnabled,
            "restoreSessionOnLaunch": settings.restoreSessionOnLaunch,
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

    /// Schedules a debounced cloud sync whenever the user changes a preference locally.
    public func scheduleSettingsSync() {
        guard isPersistenceEnabled, isLoggedIn else { return }
        settingsSyncTask?.cancel()
        settingsSyncTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, let self else { return }
            while self.isSyncing {
                try? await Task.sleep(nanoseconds: 150_000_000)
                guard !Task.isCancelled else { return }
            }
            if BrowserSettings.shared.hasPendingLocalChanges {
                await self.syncWithCloud(session: BrowserSession.shared)
            }
        }
    }

    public func syncWithCloud(session: BrowserSession) async {
        guard isLoggedIn, let token = self.token else { return }
        isSyncing = true
        syncErrorMessage = nil
        defer { isSyncing = false }

        // 1. Pull cloud bookmarks & settings
        guard let pullURL = URL(string: "\(Self.serverBaseURL)/api/sync/pull") else {
            syncErrorMessage = "同步地址无效"
            return
        }

        var pullReq = URLRequest(url: pullURL)
        pullReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let remoteBookmarks: [[String: Any]]
        let remoteSettings: [String: Any]?

        do {
            let (data, response) = try await URLSession.shared.data(for: pullReq)
            guard let httpResp = response as? HTTPURLResponse else {
                syncErrorMessage = "未收到云端响应"
                return
            }

            if httpResp.statusCode == 401 || httpResp.statusCode == 403 {
                logout()
                syncErrorMessage = "登录凭据已过期，请重新登录"
                return
            }

            guard httpResp.statusCode == 200 else {
                syncErrorMessage = "云端拉取失败 (HTTP \(httpResp.statusCode))"
                return
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                syncErrorMessage = "云端数据解析失败"
                return
            }

            remoteBookmarks = (json["bookmarks"] as? [[String: Any]]) ?? []
            remoteSettings = json["settings"] as? [String: Any]
        } catch {
            // CRITICAL DEFENSIVE GUARD: Abort immediately when pull fails to avoid overwriting remote data.
            syncErrorMessage = "同步拉取失败：\(error.localizedDescription)"
            return
        }

        // Merge cloud bookmarks into local
        for item in remoteBookmarks {
            if let title = item["title"] as? String, let url = item["url"] as? String {
                let normURL = LibraryPolicy.normalizeComparableURL(url)
                if !session.isBookmarked(url: url) {
                    session.addBookmark(url: url, title: title)
                } else if let existing = session.bookmarks.first(where: { LibraryPolicy.normalizeComparableURL($0.url) == normURL }),
                          existing.title != title && !title.isEmpty {
                    // Update title if edited on another device
                    session.updateBookmark(id: existing.id, title: title, url: url)
                }
            }
        }

        // Apply remote settings only when remote is newer than local settings and local has no pending edits.
        if let remoteSettings = remoteSettings,
           shouldApplyRemoteSettings(remoteSettings, to: session.settings) {
            applySettings(remoteSettings, to: session.settings)
            session.enforceMemoryBudget()
            session.applyContentProtectionSettingsToAllTabs()
        }

        // 2. Push merged bookmarks & settings to cloud
        guard let pushURL = URL(string: "\(Self.serverBaseURL)/api/sync/push") else {
            syncErrorMessage = "推送地址无效"
            return
        }

        var pushReq = URLRequest(url: pushURL)
        pushReq.httpMethod = "POST"
        pushReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        pushReq.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let localBookmarks = session.bookmarks.map { ["title": $0.title, "url": $0.url] }
        let localSettings = settingsPayload(from: session.settings)
        let pushedSettingsTimestamp = Self.extractUpdatedAt(from: localSettings)

        let payload: [String: Any] = [
            "bookmarks": localBookmarks,
            "settings": localSettings
        ]

        do {
            guard let data = try? JSONSerialization.data(withJSONObject: payload) else {
                syncErrorMessage = "推送数据序列化失败"
                return
            }
            pushReq.httpBody = data

            let (_, response) = try await URLSession.shared.data(for: pushReq)
            guard let httpResp = response as? HTTPURLResponse else {
                syncErrorMessage = "推送未收到云端响应"
                return
            }

            if httpResp.statusCode == 401 || httpResp.statusCode == 403 {
                logout()
                syncErrorMessage = "登录凭据已过期，请重新登录"
                return
            }

            guard httpResp.statusCode == 200 else {
                syncErrorMessage = "云端推送失败 (HTTP \(httpResp.statusCode))"
                return
            }
        } catch {
            syncErrorMessage = "同步推送失败：\(error.localizedDescription)"
            return
        }

        if session.settings.updatedAt <= pushedSettingsTimestamp {
            session.settings.markSynced(at: pushedSettingsTimestamp)
        }
        let now = Date()
        self.lastSyncTime = now
        self.userDefaults.set(now, forKey: lastSyncKey)
        if let token = self.token {
            persistSessionLocally(token: token, profile: self.currentUser)
        }
        self.syncErrorMessage = nil
    }

    private func verifySession() async {
        guard let token = self.token, let url = URL(string: "\(Self.serverBaseURL)/api/auth/me") else { return }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return }

            if httpResponse.statusCode == 200 {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let userDict = json["user"] as? [String: Any],
                   let userId = userDict["id"] as? String,
                   let userEmail = userDict["email"] as? String,
                   let userDisplayName = userDict["displayName"] as? String {
                    let userAvatarUrl = userDict["avatarUrl"] as? String ?? userDict["avatar_url"] as? String
                    let profile = UserProfile(id: userId, email: userEmail, displayName: userDisplayName, avatarUrl: userAvatarUrl)
                    self.currentUser = profile
                    self.isLoggedIn = true
                    persistSessionLocally(token: token, profile: profile)
                    await fetchAndCacheAvatarIfNeeded(for: profile)
                }
            } else if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                // Only an explicit auth rejection may destroy the local session.
                logout()
            } else {
                // Transient server/CDN failure: keep the user signed in locally instead
                // of silently wiping the keychain token and cached profile.
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

            // Automatically shrink and re-upload legacy oversized avatars once so Cloudflare R2 stays fast for all pulls.
            if data.count > Self.legacyAvatarByteThreshold && compactData.count < data.count {
                _ = await uploadAvatar(imageData: compactData, mimeType: "image/jpeg")
            }
        } catch {
            // Keep existing cached avatar if network fails
        }
    }

    private func persistSessionLocally(token: String, profile: UserProfile?) {
        _ = KeychainHelper.saveToken(token)
        // Always retain redundant copies in UserDefaults and Application Support so that
        // rebuilding or re-signing the app via run_release never drops the auth token
        // when macOS legacy Keychain ACL rejects a new binary CDHash.
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
                cachedAvatarData: self.cachedAvatarData
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
}
