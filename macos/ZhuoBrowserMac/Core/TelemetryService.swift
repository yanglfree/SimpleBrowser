import Foundation

public enum MacTelemetryPolicy {
    public static func allowsWrite(enabled: Bool, isPrivate: Bool) -> Bool {
        enabled && !isPrivate
    }

    public static func clampedMilliseconds(_ value: Double) -> Int {
        guard value.isFinite, value > 0 else { return 0 }
        return min(86_400_000, Int(value.rounded()))
    }

    public static func sanitizedAction(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        guard trimmed.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        return String(trimmed.prefix(40))
    }
}

private final class NoOpShuYiShuTransport: ShuYiShuTransport, @unchecked Sendable {
    func postJson(_ request: TransportRequest) async throws -> TransportResponse {
        TransportResponse(statusCode: 200, body: "{\"accepted\":0,\"duplicates\":0,\"rejected\":0}")
    }
}

public final class TelemetryService {
    public static let shared = TelemetryService()

    public static let defaultBaseURL = URL(string: "https://trending.youdroid.top")!
    public static let productId = "product-zhuobrowser"
    public static let defaultEnabledKey = "ZhuoBrowser_TelemetryEnabled"
    private static let installationIdKey = "shuyishu.zhuobrowser.macos.installation_id"

    private let analytics: ShuYiShuAnalytics?
    private let userDefaults: UserDefaults
    private let enabledKey: String
    private let bypassTestGuard: Bool

    public var isEnabled: Bool {
        if let stored = userDefaults.object(forKey: enabledKey) as? Bool {
            return stored
        }
        return true
    }

    public var pendingEventCount: Int {
        analytics?.pendingCount ?? 0
    }

    private convenience init() {
        let defaults = UserDefaults.standard
        let installationId: String
        if let existing = defaults.string(forKey: Self.installationIdKey), !existing.isEmpty {
            installationId = existing
        } else {
            let created = UUID().uuidString.lowercased()
            defaults.set(created, forKey: Self.installationIdKey)
            installationId = created
        }

        let info = Bundle.main.infoDictionary
        let appVersion = (info?["CFBundleShortVersionString"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let buildNumber = (info?["CFBundleVersion"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        #if DEBUG
        let appKey = "dev_zhuobrowser_macos"
        let buildMode = "debug"
        #else
        let appKey = "prod_zhuobrowser_macos"
        let buildMode = "release"
        #endif

        let transport: ShuYiShuTransport = RuntimeEnvironment.isRunningUnitTests
            ? NoOpShuYiShuTransport()
            : URLSessionShuYiShuTransport()

        let enabled = defaults.object(forKey: Self.defaultEnabledKey) as? Bool ?? true
        let client = ShuYiShuAnalytics(
            baseURL: Self.defaultBaseURL,
            appKey: appKey,
            productId: Self.productId,
            platform: "macos",
            appVersion: (appVersion?.isEmpty == false ? appVersion : nil) ?? "1.0.0",
            buildNumber: (buildNumber?.isEmpty == false ? buildNumber : nil) ?? "1",
            installationId: installationId,
            transport: transport,
            device: [
                "kind": "desktop",
                "os": "macOS",
                "os_version": ProcessInfo.processInfo.operatingSystemVersionString
            ],
            app: [
                "distribution": DistributionChannel.current.rawValue,
                "build_mode": buildMode
            ],
            debug: [
                "build_mode": buildMode,
                "is_simulator": false
            ],
            storage: UserDefaultsShuYiShuStorage(userDefaults: defaults),
            queueStorageKey: "shuyishu.zhuobrowser.macos.event_queue",
            firstOpenStorageKey: "shuyishu.zhuobrowser.macos.first_open_at",
            lastAppVersionStorageKey: "shuyishu.zhuobrowser.macos.last_app_version",
            consentState: enabled ? .granted : .denied
        )
        self.init(
            analytics: client,
            userDefaults: defaults,
            enabledKey: Self.defaultEnabledKey,
            bypassTestGuard: false
        )
    }

    public init(
        analytics: ShuYiShuAnalytics?,
        userDefaults: UserDefaults,
        enabledKey: String = TelemetryService.defaultEnabledKey,
        bypassTestGuard: Bool = false
    ) {
        self.analytics = analytics
        self.userDefaults = userDefaults
        self.enabledKey = enabledKey
        self.bypassTestGuard = bypassTestGuard
    }

    private var shouldRecord: Bool {
        bypassTestGuard || !RuntimeEnvironment.isRunningUnitTests
    }

    public func setEnabled(_ enabled: Bool) {
        userDefaults.set(enabled, forKey: enabledKey)
        analytics?.setConsent(enabled ? .granted : .denied)
    }

    public func handleAppForegrounded(isPrivate: Bool = false) {
        guard shouldRecord,
              MacTelemetryPolicy.allowsWrite(enabled: isEnabled, isPrivate: isPrivate) else {
            return
        }
        analytics?.setConsent(.granted)
        _ = analytics?.handleAppForegrounded()
    }

    public func handleAppBackgrounded(isPrivate: Bool = false) {
        guard shouldRecord,
              MacTelemetryPolicy.allowsWrite(enabled: isEnabled, isPrivate: isPrivate),
              let analytics else {
            return
        }
        Task {
            await analytics.handleAppBackgrounded()
            try? await analytics.flush()
        }
    }

    public func recordActionUsage(_ action: String, isPrivate: Bool) {
        guard shouldRecord,
              MacTelemetryPolicy.allowsWrite(enabled: isEnabled, isPrivate: isPrivate),
              let sanitized = MacTelemetryPolicy.sanitizedAction(action) else {
            return
        }
        analytics?.setConsent(.granted)
        analytics?.track("action_usage", properties: ["action": sanitized])
    }

    public func recordMemoryPressure(level: String, isPrivate: Bool = false) {
        guard shouldRecord,
              MacTelemetryPolicy.allowsWrite(enabled: isEnabled, isPrivate: isPrivate) else {
            return
        }
        analytics?.setConsent(.granted)
        analytics?.track("memory_pressure", properties: ["level": level])
    }

    public func flushAsync() {
        guard shouldRecord, isEnabled, let analytics else { return }
        Task {
            try? await analytics.flush()
        }
    }

    public func flush() async throws {
        try await analytics?.flush()
    }
}
