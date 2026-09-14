import Foundation
import OSLog

final class TelemetryService {
    static let shared = TelemetryService()

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.youdroid.zhuobrowser",
        category: "telemetry"
    )

    private init() {}

    func recordStartup(milliseconds: Double, context: TelemetryContext) {
        guard TelemetryPolicy.allowsWrite(context) else { return }
        let duration = TelemetryPolicy.clampedMilliseconds(milliseconds)
        logger.info("event=startup duration_ms=\(duration, privacy: .public)")
    }

    func recordPageLoad(milliseconds: Double, context: TelemetryContext) {
        guard TelemetryPolicy.allowsWrite(context) else { return }
        let duration = TelemetryPolicy.clampedMilliseconds(milliseconds)
        logger.info("event=page_load duration_ms=\(duration, privacy: .public)")
    }

    func recordMemoryPressure(context: TelemetryContext) {
        guard TelemetryPolicy.allowsWrite(context) else { return }
        logger.info("event=memory_pressure level=warning")
    }

    func recordActionUsage(_ action: String, context: TelemetryContext) {
        guard TelemetryPolicy.allowsWrite(context),
              let sanitized = TelemetryPolicy.sanitizedAction(action) else {
            return
        }
        logger.info("event=action_usage action=\(sanitized, privacy: .public)")
    }
}
