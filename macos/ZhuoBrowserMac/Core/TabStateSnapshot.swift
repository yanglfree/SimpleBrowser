import Foundation

/// Immutable snapshot of a tab's *rendered* page state.
///
/// This is the safety net, not the normal path. Tabs normally keep their live
/// `WKWebView` for as long as they are open (see `TabHibernationMode`), so switching
/// back is a pure view re-attach. A snapshot only exists for the exceptional cases:
/// system memory pressure, an explicitly opted-in memory-saver mode, or restoring the
/// previous session at launch.
public struct TabStateSnapshot: Equatable {
    public let url: String
    public let title: String
    public let scrollPositionY: Double
    public let canGoBack: Bool
    public let canGoForward: Bool
    public let capturedAt: Date
    /// Disk-serialisable form of the WebKit interaction archive.
    public let interactionState: Data?
    /// The live WebKit object. Preferred over `interactionState` whenever it is still
    /// available, because WebKit does not guarantee the archive is a `Data`.
    public let rawInteractionState: Any?

    public init(
        url: String,
        title: String,
        scrollPositionY: Double,
        canGoBack: Bool,
        canGoForward: Bool,
        capturedAt: Date = Date(),
        interactionState: Data?,
        rawInteractionState: Any? = nil
    ) {
        self.url = url
        self.title = title
        self.scrollPositionY = scrollPositionY
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
        self.capturedAt = capturedAt
        self.interactionState = interactionState
        self.rawInteractionState = rawInteractionState
    }

    /// True when the snapshot can rebuild the page without hitting the network.
    public var hasRestorableState: Bool {
        if rawInteractionState != nil { return true }
        guard let interactionState else { return false }
        return !interactionState.isEmpty
    }

    /// The value to assign to `WKWebView.interactionState`.
    public func restorableInteractionState() -> Any? {
        if let rawInteractionState { return rawInteractionState }
        guard let interactionState else { return nil }
        return InteractionStateCodec.decode(interactionState)
    }

    public func withScrollPosition(_ y: Double) -> TabStateSnapshot {
        TabStateSnapshot(
            url: url,
            title: title,
            scrollPositionY: y,
            canGoBack: canGoBack,
            canGoForward: canGoForward,
            capturedAt: capturedAt,
            interactionState: interactionState,
            rawInteractionState: rawInteractionState
        )
    }

    public func age(now: Date = Date()) -> TimeInterval {
        max(0, now.timeIntervalSince(capturedAt))
    }

    public static func == (lhs: TabStateSnapshot, rhs: TabStateSnapshot) -> Bool {
        // The opaque WebKit object has no meaningful equality; compare the value parts.
        lhs.url == rhs.url
            && lhs.title == rhs.title
            && lhs.scrollPositionY == rhs.scrollPositionY
            && lhs.canGoBack == rhs.canGoBack
            && lhs.canGoForward == rhs.canGoForward
            && lhs.capturedAt == rhs.capturedAt
            && lhs.interactionState == rhs.interactionState
    }
}

extension TabStateSnapshot: Codable {
    private enum CodingKeys: String, CodingKey {
        case url, title, scrollPositionY, canGoBack, canGoForward, capturedAt, interactionState
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = try container.decode(String.self, forKey: .url)
        title = try container.decode(String.self, forKey: .title)
        scrollPositionY = try container.decode(Double.self, forKey: .scrollPositionY)
        canGoBack = try container.decode(Bool.self, forKey: .canGoBack)
        canGoForward = try container.decode(Bool.self, forKey: .canGoForward)
        capturedAt = try container.decode(Date.self, forKey: .capturedAt)
        interactionState = try container.decodeIfPresent(Data.self, forKey: .interactionState)
        rawInteractionState = nil
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(url, forKey: .url)
        try container.encode(title, forKey: .title)
        try container.encode(scrollPositionY, forKey: .scrollPositionY)
        try container.encode(canGoBack, forKey: .canGoBack)
        try container.encode(canGoForward, forKey: .canGoForward)
        try container.encode(capturedAt, forKey: .capturedAt)
        try container.encodeIfPresent(interactionState, forKey: .interactionState)
    }
}

/// Translates `WKWebView.interactionState` (an opaque `Any?`) into storable bytes.
///
/// WebKit hands back an opaque archive; on Apple platforms it is normally a `Data`
/// payload it accepts back verbatim. We prefix a marker byte so the stored blob is
/// self-describing and a future format change can never be misread as raw bytes.
public enum InteractionStateCodec {
    private static let rawDataMarker: UInt8 = 0x01

    public static func encode(_ state: Any?) -> Data? {
        guard let state, let payload = state as? Data, !payload.isEmpty else { return nil }
        var blob = Data([rawDataMarker])
        blob.append(payload)
        return blob
    }

    public static func decode(_ blob: Data) -> Any? {
        guard blob.count > 1, blob.first == rawDataMarker else { return nil }
        return blob.subdata(in: 1..<blob.count)
    }
}

/// Pure decision table for how a tab should be brought back into view.
public struct TabRestorePolicy {
    /// After this age a snapshot-revived page is flagged in the UI as possibly stale.
    public static let staleInterval: TimeInterval = 15 * 60
    /// After this age the snapshot is restored instantly and then refreshed.
    public static let expirationInterval: TimeInterval = 60 * 60

    public enum Strategy: Equatable {
        /// The WebView never left memory: just re-attach it (zero work).
        case reuseLiveWebView
        /// Rebuild the page from the interaction archive: no explicit navigation.
        case restoreState
        /// Same instant restore, but the UI marks the content as possibly stale.
        case restoreStateMarkedStale
        /// Instant restore for continuity, then a single smooth background refresh.
        case restoreStateThenRefresh
        /// Nothing restorable: a real navigation is unavoidable.
        case reload

        public var restoresFromSnapshot: Bool {
            self == .restoreState || self == .restoreStateMarkedStale || self == .restoreStateThenRefresh
        }

        /// True when coming back to this tab costs the user a page rebuild.
        public var rebuildsPage: Bool {
            self != .reuseLiveWebView
        }
    }

    public static func decide(
        hasLiveWebView: Bool,
        snapshot: TabStateSnapshot?,
        now: Date = Date()
    ) -> Strategy {
        if hasLiveWebView { return .reuseLiveWebView }
        guard let snapshot, snapshot.hasRestorableState else { return .reload }

        let age = snapshot.age(now: now)
        if age >= expirationInterval { return .restoreStateThenRefresh }
        if age >= staleInterval { return .restoreStateMarkedStale }
        return .restoreState
    }
}

/// Lightweight record of an open tab, persisted so a relaunch can rebuild the
/// tab strip and hand each tab its frozen page snapshot.
public struct PersistedTabState: Codable, Equatable {
    public let id: String
    public let url: String
    public let title: String
    public let isActive: Bool
    public let lastActiveTime: Date

    public init(id: String, url: String, title: String, isActive: Bool, lastActiveTime: Date) {
        self.id = id
        self.url = url
        self.title = title
        self.isActive = isActive
        self.lastActiveTime = lastActiveTime
    }
}
