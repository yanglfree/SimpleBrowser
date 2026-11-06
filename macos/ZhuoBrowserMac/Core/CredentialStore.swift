import Foundation
import Security

/// A website login stored as a real macOS **internet password** item in the login keychain.
///
/// Why this shape:
/// * the item appears in Keychain Access ("密码" category) and is encrypted by the system keychain,
///   instead of living in a private JSON blob in UserDefaults;
/// * the secret is not part of the model — it is fetched from the keychain only when the user picks
///   the entry, so listing suggestions never loads passwords into memory;
/// * a sandboxed app only sees items created by itself, so listing never exposes other apps'
///   passwords, and `kSecAttrGeneric` marks the items as ours in case the sandbox is ever removed.
///
/// Biometric (`SecAccessControl`/`touchID`) protection is not usable here: it needs a
/// `keychain-access-groups` entitlement backed by a provisioning profile, which this Developer ID
/// build does not have (the system kills an app that declares it). Touch ID is therefore enforced by
/// `LAContext` immediately before the secret is read — see `TabController.authorizeAndFill`.
public struct SavedCredential: Identifiable, Equatable, Sendable {
    public let domain: String
    public let username: String
    public let rootDomain: String

    public var id: String { "\(domain)|\(username)" }

    public init(domain: String, username: String) {
        let normalized = domain.lowercased()
        self.domain = normalized
        self.username = username
        self.rootDomain = Self.extractRootDomain(from: normalized)
    }

    /// The placeholder written by the old demo seeder. It is not a secret and must never be stored
    /// or filled; it is only kept so the legacy migration can recognise and drop those records.
    public static let legacyPlaceholderPassword = "••••••••"

    public static func isFillablePassword(_ password: String) -> Bool {
        !password.isEmpty && password != legacyPlaceholderPassword
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

    /// The host plus each parent domain down to the registrable root, so a password saved on
    /// `apple.com` is also offered on `appleid.apple.com` (and vice versa is not implied).
    public static func candidateHosts(for hostname: String) -> [String] {
        let host = hostname.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { return [] }
        let root = extractRootDomain(from: host)
        var labels = host.split(separator: ".").map(String.init)
        var candidates: [String] = []
        while labels.count >= 2 {
            let candidate = labels.joined(separator: ".")
            candidates.append(candidate)
            if candidate == root { break }
            labels.removeFirst()
        }
        return candidates.isEmpty ? [host] : candidates
    }
}

/// A record of the retired private store, decoded only to migrate it into the login keychain.
struct LegacyStoredCredential: Decodable, Equatable {
    let domain: String
    let username: String
    let password: String
}

/// Reads and writes website passwords in the macOS login keychain.
@MainActor
public final class CredentialStore {
    public static let shared = CredentialStore()

    /// Marks items created by this app inside `kSecAttrGeneric`, so queries never touch items that
    /// belong to Safari or other keychain clients.
    static let serviceMarker = Data("com.youdroid.zhuobrowser.password".utf8)

    /// The retired private store: generic-password items under this service plus a plaintext JSON
    /// copy in UserDefaults. Both are migrated and deleted on first launch of this build.
    static let legacyService = "com.youdroid.zhuobrowser.passwords"
    public static let legacyMetadataKey = "ZhuoBrowser_CredentialStore_Metadata_v1"

    private init() {
        migrateLegacyStoreIfNeeded()
    }

    // MARK: - Queries

    /// Lists saved accounts for a host without reading any secret.
    public func credentials(for hostname: String) -> [SavedCredential] {
        let exactHost = hostname.lowercased()
        var seen = Set<String>()
        var found: [SavedCredential] = []

        for host in SavedCredential.candidateHosts(for: hostname) {
            for row in attributeRows(forServer: host) {
                guard let server = row[kSecAttrServer as String] as? String,
                      let account = row[kSecAttrAccount as String] as? String,
                      !server.isEmpty,
                      !account.isEmpty else { continue }
                let credential = SavedCredential(domain: server, username: account)
                if seen.insert(credential.id).inserted {
                    found.append(credential)
                }
            }
        }

        return found.sorted { lhs, rhs in
            let lhsExact = lhs.domain == exactHost
            let rhsExact = rhs.domain == exactHost
            if lhsExact != rhsExact { return lhsExact }
            if lhs.domain != rhs.domain { return lhs.domain < rhs.domain }
            return lhs.username.localizedStandardCompare(rhs.username) == .orderedAscending
        }
    }

    public func hasCredential(domain: String, username: String) -> Bool {
        !attributeRows(forServer: domain.lowercased(), account: username).isEmpty
    }

    /// Reads the secret for one entry. Callers must verify the user with Touch ID first.
    public func password(for credential: SavedCredential) -> String? {
        password(forDomain: credential.domain, username: credential.username)
    }

    public func password(forDomain domain: String, username: String) -> String? {
        var query = Self.baseQuery(server: domain.lowercased(), account: username)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let password = String(data: data, encoding: .utf8) else {
            return nil
        }
        return password
    }

    // MARK: - Mutations

    /// Stores or updates a password. Returns false when the secret is unusable or the keychain
    /// rejected the write; callers must not pretend the password was saved.
    @discardableResult
    public func save(domain: String, username: String, password: String) -> Bool {
        let server = domain.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !server.isEmpty, SavedCredential.isFillablePassword(password) else { return false }
        let account = username.isEmpty ? "未命名账户" : username

        // Never rewrite an identical secret: a form submit right after AutoFill would otherwise
        // prompt the user to save the password they just filled.
        if self.password(forDomain: server, username: account) == password { return true }

        let query = Self.baseQuery(server: server, account: account)
        let data = Data(password.utf8)
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return true }
        guard updateStatus == errSecItemNotFound else { return false }

        var add = query
        add[kSecAttrLabel as String] = "ZhuoBrowser — \(server)"
        add[kSecAttrDescription as String] = "ZhuoBrowser 网站登录密码"
        add[kSecValueData as String] = data
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    public func delete(_ credential: SavedCredential) {
        SecItemDelete(
            Self.baseQuery(server: credential.domain, account: credential.username) as CFDictionary
        )
    }

    // MARK: - Keychain plumbing

    nonisolated private static func baseQuery(server: String? = nil, account: String? = nil) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrGeneric as String: serviceMarker,
            kSecAttrProtocol as String: kSecAttrProtocolHTTPS
        ]
        if let server { query[kSecAttrServer as String] = server }
        if let account { query[kSecAttrAccount as String] = account }
        return query
    }

    private func attributeRows(forServer server: String, account: String? = nil) -> [[String: Any]] {
        var query = Self.baseQuery(server: server, account: account)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitAll

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return [] }
        if let list = result as? [[String: Any]] { return list }
        if let single = result as? [String: Any] { return [single] }
        return []
    }

    // MARK: - Legacy migration

    private func migrateLegacyStoreIfNeeded() {
        migrateLegacyKeychainItems()
        migrateLegacyMetadata()
    }

    /// Old builds wrote generic-password items keyed `domain|username`. Move the real secrets into
    /// internet-password items and delete the old copies (including the fabricated demo records).
    private func migrateLegacyKeychainItems() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.legacyService,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return }
        let rows: [[String: Any]]
        if let list = result as? [[String: Any]] {
            rows = list
        } else if let single = result as? [String: Any] {
            rows = [single]
        } else {
            return
        }

        for row in rows {
            guard let accountKey = row[kSecAttrAccount as String] as? String else { continue }
            let parts = accountKey.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
            if parts.count == 2,
               let data = row[kSecValueData as String] as? Data,
               let password = String(data: data, encoding: .utf8),
               SavedCredential.isFillablePassword(password) {
                // Keep the legacy item if the keychain write fails, so a later launch can retry
                // instead of dropping the only copy of the secret.
                guard save(domain: String(parts[0]), username: String(parts[1]), password: password) else {
                    continue
                }
            }

            let deleteQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: Self.legacyService,
                kSecAttrAccount as String: accountKey
            ]
            SecItemDelete(deleteQuery as CFDictionary)
        }
    }

    /// The retired store also kept a plaintext JSON copy in UserDefaults (so passwords survived even
    /// when the keychain write failed). Migrate anything real and delete the whole blob.
    private func migrateLegacyMetadata() {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: Self.legacyMetadataKey) else { return }

        // Undecodable or empty blobs are of no use; real entries are only dropped from the blob once
        // every one of them made it into the keychain, so a failed write can be retried next launch.
        guard let entries = try? JSONDecoder().decode([LegacyStoredCredential].self, from: data) else {
            defaults.removeObject(forKey: Self.legacyMetadataKey)
            return
        }

        var allMigrated = true
        for entry in Self.migratableLegacyEntries(from: entries) {
            if hasCredential(domain: entry.domain, username: entry.username) { continue }
            if !save(domain: entry.domain, username: entry.username, password: entry.password) {
                allMigrated = false
            }
        }
        if allMigrated {
            defaults.removeObject(forKey: Self.legacyMetadataKey)
        }
    }

    /// Drops empty and fabricated (bullet-mask) passwords so they never reach the system keychain.
    nonisolated static func migratableLegacyEntries(from entries: [LegacyStoredCredential]) -> [LegacyStoredCredential] {
        entries.filter { entry in
            !entry.domain.isEmpty && SavedCredential.isFillablePassword(entry.password)
        }
    }
}
