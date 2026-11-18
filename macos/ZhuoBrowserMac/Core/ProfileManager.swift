import AppKit
import Foundation
import WebKit

/// Weak wrapper so tracking open `NSWindow` instances never retains closed windows.
private final class WeakWindowBox {
    weak var window: NSWindow?

    init(_ window: NSWindow) {
        self.window = window
    }
}

/// Manages Chrome-style browser profiles, per-profile WebKit data isolation,
/// window registration, and multi-window lifecycle.
///
/// The default profile preserves the original root storage paths and
/// `WKWebsiteDataStore.default()` so upgrading users keep all existing Google
/// logins, cookies, bookmarks, history, and open tabs without interruption.
/// Every additional profile receives a dedicated `WKWebsiteDataStore(forIdentifier:)`
/// and isolated disk directories under `Profiles/<uuid>/`, allowing multiple
/// Google accounts to stay signed in simultaneously without cross-contamination.
public final class ProfileManager: ObservableObject {
    public static let shared = ProfileManager()
    public static let defaultFallbackProfileID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    public static let windowGroupID = "browser-profile"

    @Published public private(set) var profiles: [BrowserProfile] = []
    @Published public private(set) var openProfileIDs: Set<UUID> = []
    @Published public var focusedProfileID: UUID

    public let isPersistenceEnabled: Bool
    public let rootDirectory: URL
    private let fileManager: FileManager
    private let registryFileURL: URL?
    private let usesPersistentDataStores: Bool

    private var sessions: [UUID: BrowserSession] = [:]
    private var windowBoxes: [UUID: WeakWindowBox] = [:]

    public init(
        fileManager: FileManager = .default,
        rootDirectory: URL? = nil,
        isPersistenceEnabled: Bool = !RuntimeEnvironment.isRunningUnitTests,
        usesPersistentDataStores: Bool? = nil
    ) {
        self.fileManager = fileManager
        self.isPersistenceEnabled = isPersistenceEnabled
        self.usesPersistentDataStores = usesPersistentDataStores ?? isPersistenceEnabled

        if let rootDirectory {
            self.rootDirectory = rootDirectory
            if isPersistenceEnabled {
                try? fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
            }
            self.registryFileURL = isPersistenceEnabled
                ? rootDirectory.appendingPathComponent("profiles.json")
                : nil
        } else if isPersistenceEnabled,
                  let appSupport = try? fileManager.url(
                      for: .applicationSupportDirectory,
                      in: .userDomainMask,
                      appropriateFor: nil,
                      create: true
                  ) {
            let dir = appSupport.appendingPathComponent("ZhuoBrowserMac", isDirectory: true)
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            self.rootDirectory = dir
            self.registryFileURL = dir.appendingPathComponent("profiles.json")
        } else {
            let tempRoot = fileManager.temporaryDirectory
                .appendingPathComponent("ZhuoBrowserMacProfilesTests-\(UUID().uuidString)", isDirectory: true)
            self.rootDirectory = tempRoot
            self.registryFileURL = nil
        }

        let initialState = Self.loadOrSeedRegistry(from: registryFileURL)
        self.profiles = initialState.profiles
        let fallbackID = initialState.profiles.first?.id ?? Self.defaultFallbackProfileID
        if let lastID = initialState.lastActiveProfileID,
           initialState.profiles.contains(where: { $0.id == lastID }) {
            self.focusedProfileID = lastID
        } else {
            self.focusedProfileID = fallbackID
        }

        if isPersistenceEnabled {
            persistRegistry()
        }
    }

    // MARK: - Accessors

    public var defaultProfile: BrowserProfile {
        if let existing = profiles.first(where: \.isDefault) ?? profiles.first {
            return existing
        }
        let fallback = Self.makeDefaultProfile()
        profiles = [fallback]
        return fallback
    }

    public var initialLaunchProfileID: UUID {
        if let existing = existingProfile(for: focusedProfileID) {
            return existing.id
        }
        return defaultProfile.id
    }

    public var focusedProfile: BrowserProfile {
        existingProfile(for: focusedProfileID) ?? defaultProfile
    }

    public var defaultSession: BrowserSession {
        session(for: defaultProfile.id)
    }

    public var focusedSession: BrowserSession {
        session(for: focusedProfile.id)
    }

    public var activeSessions: [BrowserSession] {
        Array(sessions.values)
    }

    public func existingProfile(for id: UUID) -> BrowserProfile? {
        profiles.first(where: { $0.id == id })
    }

    public func profile(for id: UUID) -> BrowserProfile {
        existingProfile(for: id) ?? defaultProfile
    }

    public func loadedSession(for id: UUID) -> BrowserSession? {
        sessions[id]
    }

    public func session(containingTabID tabID: String) -> BrowserSession? {
        for session in sessions.values {
            if session.tabs.contains(where: { $0.id == tabID }) {
                return session
            }
        }
        return nil
    }

    /// Returns the isolated `BrowserSession` for `profileID`, creating it on demand.
    public func session(for profileID: UUID) -> BrowserSession {
        let resolvedProfile = profile(for: profileID)
        if let existing = sessions[resolvedProfile.id] {
            return existing
        }
        let created = buildSession(for: resolvedProfile)
        sessions[resolvedProfile.id] = created
        return created
    }

    /// Resolves the `WKWebsiteDataStore` assigned to a profile.
    public func websiteDataStore(for profile: BrowserProfile) -> WKWebsiteDataStore {
        if !usesPersistentDataStores {
            return .nonPersistent()
        }
        if profile.isDefault {
            return .default()
        }
        return WKWebsiteDataStore(forIdentifier: profile.id)
    }

    /// Returns the root folder for a non-default profile's isolated persistence files.
    public func storageDirectoryURL(for profile: BrowserProfile) -> URL {
        if profile.isDefault {
            return rootDirectory
        }
        return rootDirectory
            .appendingPathComponent("Profiles", isDirectory: true)
            .appendingPathComponent(profile.id.uuidString, isDirectory: true)
    }

    // MARK: - Profile Mutations

    public func suggestedNextProfileName() -> String {
        let existingNames = Set(profiles.map { $0.displayName.lowercased() })
        var index = max(2, profiles.count + 1)
        while existingNames.contains("个人资料 \(index)".lowercased()) {
            index += 1
        }
        return "个人资料 \(index)"
    }

    @discardableResult
    public func createProfile(
        name: String,
        avatarSymbol: String? = nil,
        colorHex: String? = nil
    ) -> BrowserProfile {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = trimmed.isEmpty ? suggestedNextProfileName() : trimmed
        let count = profiles.count
        let newProfile = BrowserProfile(
            id: UUID(),
            name: resolvedName,
            avatarSymbol: avatarSymbol ?? ProfilePalette.nextSuggestedSymbol(existingCount: count),
            colorHex: colorHex ?? ProfilePalette.nextSuggestedColorHex(existingCount: count),
            isDefault: false,
            createdAt: Date(),
            lastActiveAt: Date()
        )
        profiles.append(newProfile)
        persistRegistry()
        return newProfile
    }

    public func updateProfile(
        id: UUID,
        name: String,
        avatarSymbol: String,
        colorHex: String
    ) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            profiles[index].name = trimmed
        }
        profiles[index].avatarSymbol = avatarSymbol
        profiles[index].colorHex = colorHex
        persistRegistry()
        sessions[id]?.objectWillChange.send()
    }

    /// Deletes a non-default profile, closes any open window, tears down its WebViews,
    /// deletes its local storage folder, and purges its WebKit data store container.
    @discardableResult
    public func deleteProfile(id: UUID, completion: (() -> Void)? = nil) -> Bool {
        guard let index = profiles.firstIndex(where: { $0.id == id }),
              !profiles[index].isDefault else {
            completion?()
            return false
        }

        let targetProfile = profiles[index]
        profiles.remove(at: index)

        if focusedProfileID == id {
            focusedProfileID = defaultProfile.id
        }
        openProfileIDs.remove(id)
        persistRegistry()

        if let window = windowBoxes.removeValue(forKey: id)?.window {
            window.close()
        }

        if let session = sessions.removeValue(forKey: id) {
            session.shutdownAllWebViews()
        }

        if isPersistenceEnabled {
            let profileDir = storageDirectoryURL(for: targetProfile)
            try? fileManager.removeItem(at: profileDir)
        }

        if usesPersistentDataStores {
            WKWebsiteDataStore.remove(forIdentifier: id) { _ in
                DispatchQueue.main.async {
                    completion?()
                }
            }
        } else {
            completion?()
        }

        return true
    }

    // MARK: - Window & Session Lifecycle

    public func registerWindow(_ window: NSWindow, forProfileID id: UUID) {
        let resolvedID = existingProfile(for: id)?.id ?? defaultProfile.id
        windowBoxes[resolvedID] = WeakWindowBox(window)
        openProfileIDs.insert(resolvedID)
        sessions[resolvedID]?.hostWindow = window
        if window.isKeyWindow || openProfileIDs.count == 1 {
            markProfileFocused(resolvedID)
        }
    }

    public func markProfileFocused(_ id: UUID) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        if focusedProfileID != id {
            focusedProfileID = id
        }
        profiles[index].lastActiveAt = Date()
        persistRegistry()
    }

    public func handleWindowClosing(forProfileID id: UUID) {
        if let session = sessions[id] {
            session.cookieSessionStore.persistSessionCookies()
            session.webSessionStorageStore.flushAsync()
            session.captureSessionOnResignActive()
            session.hostWindow = nil
        }
        windowBoxes.removeValue(forKey: id)
        openProfileIDs.remove(id)
        if focusedProfileID == id {
            if let nextOpen = openProfileIDs.first {
                focusedProfileID = nextOpen
            } else {
                focusedProfileID = defaultProfile.id
            }
        }
    }

    public func window(forProfileID id: UUID) -> NSWindow? {
        guard let box = windowBoxes[id], let window = box.window else {
            windowBoxes.removeValue(forKey: id)
            return nil
        }
        return window
    }

    /// Focuses an already-open window for `id`, returning `true` if one existed.
    @discardableResult
    public func focusExistingWindow(forProfileID id: UUID) -> Bool {
        guard let existingWindow = window(forProfileID: id) else {
            return false
        }
        if existingWindow.isMiniaturized {
            existingWindow.deminiaturize(nil)
        }
        existingWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        markProfileFocused(id)
        return true
    }

    public func persistAllSessionsForResignActive() {
        for session in sessions.values {
            session.cookieSessionStore.persistSessionCookies()
            session.webSessionStorageStore.flushAsync()
            session.captureSessionOnResignActive()
        }
        persistRegistry()
    }

    public func flushAllSessionsForTermination() {
        for session in sessions.values {
            session.cookieSessionStore.persistSessionCookiesSynchronously()
            session.webSessionStorageStore.flushSynchronously()
            session.captureSessionForTermination(synchronously: true)
        }
        persistRegistry()
    }

    // MARK: - Private Builders & Persistence

    private func buildSession(for profile: BrowserProfile) -> BrowserSession {
        let dataStore = websiteDataStore(for: profile)

        let profileDir = storageDirectoryURL(for: profile)
        let sessionCookiesDir = profileDir.appendingPathComponent("SessionCookies", isDirectory: true)
        let cookieArchiveURL = sessionCookiesDir.appendingPathComponent("session-cookies.archive")
        let sessionStorageURL = sessionCookiesDir.appendingPathComponent("web-session-storage.json")
        let tabStateDir = profileDir.appendingPathComponent("TabState", isDirectory: true)

        let cookieStore: CookieSessionStore
        let webSessionStorageStore: WebSessionStorageStore
        let stateStore: TabStateStore
        let libraryStore: LibraryStore
        let favoritesManager: FavoritesManager

        if profile.isDefault && rootDirectory == Self.defaultAppSupportDirectory(fileManager: fileManager) {
            cookieStore = isPersistenceEnabled ? CookieSessionStore.shared : CookieSessionStore(
                dataStore: dataStore,
                isPersistenceEnabled: false
            )
            webSessionStorageStore = isPersistenceEnabled ? WebSessionStorageStore.shared : WebSessionStorageStore(
                isPersistenceEnabled: false
            )
            stateStore = isPersistenceEnabled ? TabStateStore.shared : TabStateStore(
                isPersistenceEnabled: false
            )
            libraryStore = isPersistenceEnabled ? LibraryStore.shared : LibraryStore(
                isPersistenceEnabled: false
            )
            favoritesManager = Self.resolveMainActor { FavoritesManager.shared }
        } else {
            cookieStore = CookieSessionStore(
                dataStore: dataStore,
                fileManager: fileManager,
                isPersistenceEnabled: isPersistenceEnabled,
                archiveURL: isPersistenceEnabled ? cookieArchiveURL : nil
            )
            webSessionStorageStore = WebSessionStorageStore(
                fileManager: fileManager,
                isPersistenceEnabled: isPersistenceEnabled,
                storageURL: isPersistenceEnabled ? sessionStorageURL : nil
            )
            stateStore = TabStateStore(
                fileManager: fileManager,
                isPersistenceEnabled: isPersistenceEnabled,
                rootURL: isPersistenceEnabled ? tabStateDir : nil
            )
            libraryStore = LibraryStore(
                isPersistenceEnabled: isPersistenceEnabled,
                directoryURL: isPersistenceEnabled ? profileDir : nil
            )
            favoritesManager = Self.resolveMainActor {
                profile.isDefault ? FavoritesManager.shared : FavoritesManager()
            }
        }

        return BrowserSession(
            profileID: profile.id,
            isDefaultProfile: profile.isDefault,
            websiteDataStore: dataStore,
            cookieSessionStore: cookieStore,
            webSessionStorageStore: webSessionStorageStore,
            stateStore: stateStore,
            libraryStore: libraryStore,
            favoritesManager: favoritesManager
        )
    }

    private static func resolveMainActor<T>(_ work: @MainActor () -> T) -> T {
        if Thread.isMainThread {
            return MainActor.assumeIsolated { work() }
        }
        return DispatchQueue.main.sync {
            MainActor.assumeIsolated { work() }
        }
    }

    private static func defaultAppSupportDirectory(fileManager: FileManager) -> URL? {
        guard let base = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else {
            return nil
        }
        return base.appendingPathComponent("ZhuoBrowserMac", isDirectory: true)
    }

    private static func makeDefaultProfile() -> BrowserProfile {
        BrowserProfile(
            id: defaultFallbackProfileID,
            name: "个人",
            avatarSymbol: ProfilePalette.defaultSymbol,
            colorHex: ProfilePalette.defaultColorHex,
            isDefault: true
        )
    }

    private static func loadOrSeedRegistry(from url: URL?) -> PersistedProfileRegistry {
        if let url,
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(PersistedProfileRegistry.self, from: data),
           !decoded.profiles.isEmpty {
            var profiles = decoded.profiles
            if !profiles.contains(where: \.isDefault) {
                let first = profiles[0]
                profiles[0] = BrowserProfile(
                    id: first.id,
                    name: first.name,
                    avatarSymbol: first.avatarSymbol,
                    colorHex: first.colorHex,
                    isDefault: true,
                    createdAt: first.createdAt,
                    lastActiveAt: first.lastActiveAt
                )
            }
            return PersistedProfileRegistry(
                profiles: profiles,
                lastActiveProfileID: decoded.lastActiveProfileID
            )
        }
        let defaultProfile = makeDefaultProfile()
        return PersistedProfileRegistry(
            profiles: [defaultProfile],
            lastActiveProfileID: defaultProfile.id
        )
    }

    private func persistRegistry() {
        guard isPersistenceEnabled, let registryFileURL else { return }
        let payload = PersistedProfileRegistry(
            profiles: profiles,
            lastActiveProfileID: focusedProfileID
        )
        if let data = try? JSONEncoder().encode(payload) {
            try? data.write(to: registryFileURL, options: .atomic)
        }
    }
}
