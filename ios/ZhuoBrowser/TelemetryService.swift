import Foundation
import OSLog
#if canImport(UIKit)
import UIKit
#endif

final class TelemetryService {
    static let shared = TelemetryService()

    private static let defaultBaseURL = URL(string: "https://trending.youdroid.top")!
    private static let productId = "product-zhuobrowser"
    private static let installationIdKey = "shuyishu.zhuobrowser.installation_id"

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.youdroid.zhuobrowser",
        category: "telemetry"
    )
    private let analytics: ShuYiShuAnalytics?

    var pendingEventCount: Int {
        analytics?.pendingCount ?? 0
    }

    private convenience init() {
        let userDefaults = UserDefaults.standard
        let installationId: String
        if let existing = userDefaults.string(forKey: Self.installationIdKey), !existing.isEmpty {
            installationId = existing
        } else {
            let created = UUID().uuidString.lowercased()
            userDefaults.set(created, forKey: Self.installationIdKey)
            installationId = created
        }

        let info = Bundle.main.infoDictionary
        let appVersion = (info?["CFBundleShortVersionString"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let buildNumber = (info?["CFBundleVersion"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        #if DEBUG
        let appKey = "dev_zhuobrowser_ios"
        let buildMode = "debug"
        #else
        let appKey = "prod_zhuobrowser_ios"
        let buildMode = "release"
        #endif

        #if targetEnvironment(simulator)
        let isSimulator = true
        #else
        let isSimulator = false
        #endif

        let deviceContext: [String: Any]
        #if canImport(UIKit)
        let idiom = UIDevice.current.userInterfaceIdiom
        let kind = idiom == .pad ? "pad" : "phone"
        deviceContext = [
            "kind": kind,
            "os": "iOS",
            "os_version": UIDevice.current.systemVersion
        ]
        #else
        deviceContext = [
            "kind": "phone",
            "os": "iOS"
        ]
        #endif

        let client = ShuYiShuAnalytics(
            baseURL: Self.defaultBaseURL,
            appKey: appKey,
            productId: Self.productId,
            platform: "ios",
            appVersion: (appVersion?.isEmpty == false ? appVersion : nil) ?? "1.0.0",
            buildNumber: (buildNumber?.isEmpty == false ? buildNumber : nil) ?? "1",
            installationId: installationId,
            transport: URLSessionShuYiShuTransport(),
            device: deviceContext,
            app: ["build_mode": buildMode],
            debug: [
                "build_mode": buildMode,
                "is_simulator": isSimulator
            ],
            storage: UserDefaultsShuYiShuStorage(userDefaults: userDefaults),
            queueStorageKey: "shuyishu.zhuobrowser.ios.event_queue",
            firstOpenStorageKey: "shuyishu.zhuobrowser.ios.first_open_at",
            lastAppVersionStorageKey: "shuyishu.zhuobrowser.ios.last_app_version",
            consentState: .denied
        )
        self.init(analytics: client)
    }

    init(analytics: ShuYiShuAnalytics?) {
        self.analytics = analytics
    }

    static func makeForTesting(
        storage: ShuYiShuStorage,
        transport: ShuYiShuTransport,
        consentState: ConsentState = .denied
    ) -> TelemetryService {
        let client = ShuYiShuAnalytics(
            baseURL: defaultBaseURL,
            appKey: "dev_zhuobrowser_ios",
            productId: productId,
            platform: "ios",
            appVersion: "1.0.0",
            buildNumber: "1",
            installationId: "test-install-ios",
            transport: transport,
            storage: storage,
            queueStorageKey: "shuyishu.test.event_queue",
            firstOpenStorageKey: "shuyishu.test.first_open_at",
            lastAppVersionStorageKey: "shuyishu.test.last_app_version",
            consentState: consentState
        )
        return TelemetryService(analytics: client)
    }

    func syncConsent(consentAccepted: Bool, enabled: Bool) {
        analytics?.setConsent(consentAccepted && enabled ? .granted : .denied)
    }

    func recordStartup(milliseconds: Double, context: TelemetryContext) {
        guard TelemetryPolicy.allowsWrite(context) else { return }
        let duration = TelemetryPolicy.clampedMilliseconds(milliseconds)
        logger.info("event=startup duration_ms=\(duration, privacy: .public)")
        analytics?.setConsent(.granted)
        analytics?.track("app_startup", properties: ["duration_ms": duration])
    }

    func recordPageLoad(milliseconds: Double, context: TelemetryContext) {
        guard TelemetryPolicy.allowsWrite(context) else { return }
        let duration = TelemetryPolicy.clampedMilliseconds(milliseconds)
        logger.info("event=page_load duration_ms=\(duration, privacy: .public)")
        analytics?.setConsent(.granted)
        analytics?.track("page_load", properties: ["duration_ms": duration])
    }

    func recordMemoryPressure(context: TelemetryContext) {
        guard TelemetryPolicy.allowsWrite(context) else { return }
        logger.info("event=memory_pressure level=warning")
        analytics?.setConsent(.granted)
        analytics?.track("memory_pressure", properties: ["level": "warning"])
    }

    func recordActionUsage(_ action: String, context: TelemetryContext) {
        guard TelemetryPolicy.allowsWrite(context),
              let sanitized = TelemetryPolicy.sanitizedAction(action) else {
            return
        }
        logger.info("event=action_usage action=\(sanitized, privacy: .public)")
        analytics?.setConsent(.granted)
        analytics?.track("action_usage", properties: ["action": sanitized])
    }

    func handleAppForegrounded(context: TelemetryContext) {
        guard TelemetryPolicy.allowsWrite(context) else { return }
        analytics?.setConsent(.granted)
        _ = analytics?.handleAppForegrounded()
    }

    func handleAppBackgrounded(context: TelemetryContext) {
        guard TelemetryPolicy.allowsWrite(context) else { return }
        guard let analytics else { return }
        Task {
            await analytics.handleAppBackgrounded()
            try? await analytics.flush()
        }
    }

    func flush() async throws {
        try await analytics?.flush()
    }
}
