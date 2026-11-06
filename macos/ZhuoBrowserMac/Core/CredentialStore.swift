import Foundation
import Security

/// Represents a login credential stored securely for a domain.
///
/// This store holds passwords only. Passkeys never live here: a passkey is an asymmetric key held
/// by the platform authenticator (iCloud Keychain), and the app can only obtain an assertion for it
/// from WebKit. Persisting a "passkey" row with a placeholder password is what produced the
/// "此网站的通行密钥" entry that silently submitted eight bullet characters to apple.com.
public struct SavedCredential: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var domain: String
    public var rootDomain: String
    public var username: String
    public var password: String
    public var lastUsed: Date
    public var createdAt: Date

    /// The placeholder the old demo seeder wrote instead of a secret. It must never be injected
    /// into a page: submitting it is guaranteed to fail server-side and looks like a broken login.
    public static let legacyPlaceholderPassword = "••••••••"

    public init(
        id: UUID = UUID(),
        domain: String,
        rootDomain: String? = nil,
        username: String,
        password: String = "",
        lastUsed: Date = Date(),
        createdAt: Date = Date()
    ) {
        self.id = id
        self.domain = domain.lowercased()
        self.rootDomain = rootDomain?.lowercased() ?? Self.extractRootDomain(from: domain)
        self.username = username
        self.password = password
        self.lastUsed = lastUsed
        self.createdAt = createdAt
    }

    /// A credential without a real secret cannot be filled. An empty string leaves the page blank;
    /// the legacy placeholder submits the mask itself, which no server accepts.
    public var isFillable: Bool {
        !password.isEmpty && password != Self.legacyPlaceholderPassword
    }

    /// Detects the two demo records `ac05863` injected into every install ("apple.com" passkey and
    /// the Huawei account). Both are matched together with the placeholder password so a genuine
    /// record for the same account (real password) is never removed.
    public var isLegacyDemoRecord: Bool {
        guard password == Self.legacyPlaceholderPassword else { return false }
        switch (domain, username) {
        case ("apple.com", "yangliangsky@gmail.com"),
             ("id1.cloud.huawei.com", "18627178676"):
            return true
        default:
            return false
        }
    }

    /// Derives the effective root domain (e.g. "id1.cloud.huawei.com" -> "huawei.com", "appleid.apple.com" -> "apple.com")
    public static func extractRootDomain(from host: String) -> String {
        let clean = host.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = clean.split(separator: ".").map(String.init)
        guard parts.count >= 2 else { return clean }
        // Handle common second-level domains like com.cn, co.uk if needed, otherwise take last 2 components
        if parts.count >= 3 && ["com", "co", "org", "net", "edu", "gov"].contains(parts[parts.count - 2]) {
            return parts.suffix(3).joined(separator: ".")
        }
        return parts.suffix(2).joined(separator: ".")
    }
}

/// Thread-safe manager for browser passwords & credentials using macOS Keychain Services.
@MainActor
public final class CredentialStore: ObservableObject {
    public static let shared = CredentialStore()

    public static let keychainServiceName = "com.youdroid.zhuobrowser.passwords"
    private static let metadataKey = "ZhuoBrowser_CredentialStore_Metadata_v1"

    @Published public private(set) var credentials: [SavedCredential] = []

    private init() {
        loadCredentials()
        purgeLegacyDemoRecords()
    }

    /// Removes the fabricated demo records older builds wrote into UserDefaults + Keychain.
    /// They survive upgrades, so merely deleting the seeder would leave the fake apple.com
    /// "passkey" (and its bullet-mask password) offered to every user forever.
    private func purgeLegacyDemoRecords() {
        let stale = credentials.filter(\.isLegacyDemoRecord)
        guard !stale.isEmpty else { return }
        credentials = Self.removingLegacyDemoRecords(from: credentials)
        for item in stale {
            deleteFromKeychain(account: item.username, domain: item.domain)
        }
        persistMetadata()
    }

    /// Pure filter used by the migration above and by unit tests.
    nonisolated public static func removingLegacyDemoRecords(from list: [SavedCredential]) -> [SavedCredential] {
        list.filter { !$0.isLegacyDemoRecord }
    }

    /// True when at least one stored credential actually has a secret to fill.
    nonisolated public static func canOfferAutoFill(_ candidates: [SavedCredential]) -> Bool {
        candidates.contains(where: \.isFillable)
    }

    /// Queries credentials matching a specific hostname or its root domain.
    public func credentials(for hostname: String) -> [SavedCredential] {
        let targetHost = hostname.lowercased()
        let targetRoot = SavedCredential.extractRootDomain(from: targetHost)

        return credentials.filter { item in
            let itemHost = item.domain.lowercased()
            let itemRoot = item.rootDomain.lowercased()
            return itemHost == targetHost || itemRoot == targetRoot || targetHost.hasSuffix("." + itemHost) || itemHost.hasSuffix("." + targetHost)
        }.sorted { (a, b) -> Bool in
            // Exact host match comes first, then the most recently used password.
            let aExact = a.domain == targetHost
            let bExact = b.domain == targetHost
            if aExact != bExact { return aExact }
            return a.lastUsed > b.lastUsed
        }
    }

    /// Saves or updates a credential entry in Keychain and in-memory cache.
    public func save(credential: SavedCredential) {
        var updated = credential
        updated.lastUsed = Date()

        if let index = credentials.firstIndex(where: { $0.id == updated.id || ($0.domain == updated.domain && $0.username == updated.username) }) {
            credentials[index] = updated
        } else {
            credentials.append(updated)
        }

        saveToKeychain(credential: updated)
        persistMetadata()
    }

    /// Deletes a saved credential.
    public func delete(id: UUID) {
        guard let item = credentials.first(where: { $0.id == id }) else { return }
        credentials.removeAll(where: { $0.id == id })
        deleteFromKeychain(account: item.username, domain: item.domain)
        persistMetadata()
    }

    // MARK: - Keychain Implementation

    private func saveToKeychain(credential: SavedCredential) {
        guard let passwordData = credential.password.data(using: .utf8) else { return }
        let accountKey = "\(credential.domain)|\(credential.username)"

        // Query if existing
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainServiceName,
            kSecAttrAccount as String: accountKey
        ]

        let attributesToUpdate: [String: Any] = [
            kSecValueData as String: passwordData
        ]

        let status = SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)
        if status == errSecItemNotFound {
            var newItem = query
            newItem[kSecValueData as String] = passwordData
            SecItemAdd(newItem as CFDictionary, nil)
        }
    }

    private func deleteFromKeychain(account: String, domain: String) {
        let accountKey = "\(domain)|\(account)"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainServiceName,
            kSecAttrAccount as String: accountKey
        ]
        SecItemDelete(query as CFDictionary)
    }

    private func loadPasswordFromKeychain(account: String, domain: String) -> String? {
        let accountKey = "\(domain)|\(account)"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainServiceName,
            kSecAttrAccount as String: accountKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data, let pw = String(data: data, encoding: .utf8) {
            return pw
        }
        return nil
    }

    private func persistMetadata() {
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(credentials) {
            UserDefaults.standard.set(encoded, forKey: Self.metadataKey)
        }
    }

    private func loadCredentials() {
        guard let data = UserDefaults.standard.data(forKey: Self.metadataKey),
              let list = try? JSONDecoder().decode([SavedCredential].self, from: data) else {
            return
        }

        var loaded: [SavedCredential] = []
        for var item in list {
            if let pw = loadPasswordFromKeychain(account: item.username, domain: item.domain) {
                item.password = pw
            }
            loaded.append(item)
        }
        self.credentials = loaded
    }
}
