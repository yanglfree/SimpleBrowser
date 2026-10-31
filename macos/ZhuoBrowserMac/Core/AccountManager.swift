import Combine
import Foundation

/// Model representing an authenticated user profile.
public struct UserProfile: Codable, Identifiable, Equatable {
    public let id: String
    public let email: String
    public let displayName: String
    public let createdAt: Int64?

    public init(id: String, email: String, displayName: String, createdAt: Int64? = nil) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.createdAt = createdAt
    }
}

/// Cloud-backed account and cross-device sync manager.
@MainActor
public final class AccountManager: ObservableObject {
    public static let shared = AccountManager()

    public static let serverBaseURL = "https://zhuobrowser-auth-service.memoryphoto.workers.dev"

    private let tokenKey = "ZhuoBrowser_Account_Token"
    private let userProfileKey = "ZhuoBrowser_Account_Profile"
    private let lastSyncKey = "ZhuoBrowser_Account_LastSync"
    private let userDefaults = UserDefaults.standard

    @Published public private(set) var currentUser: UserProfile?
    @Published public private(set) var token: String?
    @Published public private(set) var isLoggedIn: Bool = false
    @Published public private(set) var isSyncing: Bool = false
    @Published public private(set) var lastSyncTime: Date?
    @Published public var errorMessage: String?

    public init() {
        if let savedToken = userDefaults.string(forKey: tokenKey), !savedToken.isEmpty {
            self.token = savedToken
            self.isLoggedIn = true

            if let data = userDefaults.data(forKey: userProfileKey),
               let profile = try? JSONDecoder().decode(UserProfile.self, from: data) {
                self.currentUser = profile
            }

            if let syncTime = userDefaults.object(forKey: lastSyncKey) as? Date {
                self.lastSyncTime = syncTime
            }

            Task {
                await verifySession()
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
                    let profile = UserProfile(id: userId, email: userEmail, displayName: userDisplayName)
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
                    let profile = UserProfile(id: userId, email: userEmail, displayName: userDisplayName)
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
        if let token = self.token, let url = URL(string: "\(Self.serverBaseURL)/api/auth/logout") {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            Task {
                _ = try? await URLSession.shared.data(for: request)
            }
        }

        self.token = nil
        self.currentUser = nil
        self.isLoggedIn = false
        self.userDefaults.removeObject(forKey: tokenKey)
        self.userDefaults.removeObject(forKey: userProfileKey)
    }

    public func syncWithCloud(session: BrowserSession) async {
        guard isLoggedIn, let token = self.token else { return }
        isSyncing = true
        defer { isSyncing = false }

        // 1. Pull cloud bookmarks
        if let pullURL = URL(string: "\(Self.serverBaseURL)/api/sync/pull") {
            var pullReq = URLRequest(url: pullURL)
            pullReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            if let (data, response) = try? await URLSession.shared.data(for: pullReq),
               let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let remoteBookmarks = json["bookmarks"] as? [[String: Any]] {
                // Merge cloud bookmarks into local
                for item in remoteBookmarks {
                    if let title = item["title"] as? String, let url = item["url"] as? String {
                        if !session.isBookmarked(url: url) {
                            session.addBookmark(url: url, title: title)
                        }
                    }
                }
            }
        }

        // 2. Push merged bookmarks to cloud
        if let pushURL = URL(string: "\(Self.serverBaseURL)/api/sync/push") {
            var pushReq = URLRequest(url: pushURL)
            pushReq.httpMethod = "POST"
            pushReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            pushReq.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let localBookmarks = session.bookmarks.map { ["title": $0.title, "url": $0.url] }
            let payload: [String: Any] = [
                "bookmarks": localBookmarks,
                "settings": [
                    "adBlockEnabled": session.settings.adBlockEnabled,
                    "liveWebViewBudget": session.settings.liveWebViewBudget
                ]
            ]

            if let data = try? JSONSerialization.data(withJSONObject: payload) {
                pushReq.httpBody = data
                _ = try? await URLSession.shared.data(for: pushReq)
            }
        }

        let now = Date()
        self.lastSyncTime = now
        self.userDefaults.set(now, forKey: lastSyncKey)
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
                    let profile = UserProfile(id: userId, email: userEmail, displayName: userDisplayName)
                    self.currentUser = profile
                    self.isLoggedIn = true
                }
            } else {
                // Session expired or invalid
                logout()
            }
        } catch {
            // Network failure: keep local offline session intact
        }
    }

    private func saveSession(token: String, profile: UserProfile) {
        self.token = token
        self.currentUser = profile
        self.isLoggedIn = true
        self.userDefaults.set(token, forKey: tokenKey)
        if let data = try? JSONEncoder().encode(profile) {
            self.userDefaults.set(data, forKey: userProfileKey)
        }
    }
}
