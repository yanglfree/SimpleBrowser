import Foundation

public enum ConsentState: String, Sendable {
    case granted
    case denied
    case unknown
}

public protocol ShuYiShuStorage: AnyObject {
    func readString(forKey key: String) -> String?
    func writeString(_ value: String, forKey key: String)
}

public final class UserDefaultsShuYiShuStorage: ShuYiShuStorage, @unchecked Sendable {
    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public func readString(forKey key: String) -> String? {
        userDefaults.string(forKey: key)
    }

    public func writeString(_ value: String, forKey key: String) {
        userDefaults.set(value, forKey: key)
    }
}

public struct TransportRequest: Sendable {
    public let url: URL
    public let headers: [String: String]
    public let body: String

    public init(url: URL, headers: [String: String], body: String) {
        self.url = url
        self.headers = headers
        self.body = body
    }
}

public struct TransportResponse: Sendable {
    public let statusCode: Int
    public let body: String

    public init(statusCode: Int, body: String) {
        self.statusCode = statusCode
        self.body = body
    }

    public var isSuccess: Bool {
        statusCode >= 200 && statusCode < 300
    }
}

public protocol ShuYiShuTransport: AnyObject {
    func postJson(_ request: TransportRequest) async throws -> TransportResponse
}

public final class URLSessionShuYiShuTransport: ShuYiShuTransport, @unchecked Sendable {
    private let session: URLSession
    private let timeout: TimeInterval

    public init(session: URLSession = .shared, timeout: TimeInterval = 5) {
        self.session = session
        self.timeout = timeout
    }

    public func postJson(_ request: TransportRequest) async throws -> TransportResponse {
        var urlRequest = URLRequest(url: request.url, timeoutInterval: timeout)
        urlRequest.httpMethod = "POST"
        urlRequest.httpBody = request.body.data(using: .utf8)
        for (key, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }
        let (data, response) = try await session.data(for: urlRequest)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        let body = String(data: data, encoding: .utf8) ?? ""
        return TransportResponse(statusCode: statusCode, body: body)
    }
}

public struct ShuYiShuIngestionError: Error, Sendable {
    public let statusCode: Int

    public init(statusCode: Int) {
        self.statusCode = statusCode
    }

    public var isRetryable: Bool {
        statusCode == 408 || statusCode == 425 || statusCode == 429 || statusCode >= 500
    }
}

public struct ShuYiShuEventTooLargeError: Error, Sendable {
    public let actualBytes: Int
    public let maxBytes: Int

    public init(actualBytes: Int, maxBytes: Int) {
        self.actualBytes = actualBytes
        self.maxBytes = maxBytes
    }
}

public final class ShuYiShuAnalytics: @unchecked Sendable {
    private static let defaultQueueStorageKey = "shuyishu.event_queue"
    private static let defaultFirstOpenStorageKey = "shuyishu.first_open_at"
    private static let defaultLastAppVersionStorageKey = "shuyishu.last_app_version"
    private static let forbiddenPropertyFragments: [String] = [
        "access_token",
        "account_id",
        "anonymous_user_id",
        "error_message",
        "exception",
        "image",
        "login",
        "markdown",
        "private_repo",
        "query",
        "raw_error",
        "repo_name",
        "repository_name",
        "search_text",
        "source_code",
        "strokes",
        "text",
        "user_id"
    ]

    private let lock = NSLock()
    private let baseURL: URL
    private let appKey: String
    private let productId: String
    private let platform: String
    private let appVersion: String
    private let buildNumber: String
    private let installationId: String
    private let transport: ShuYiShuTransport
    private let storage: ShuYiShuStorage?
    private let queueStorageKey: String
    private var country: String?
    private var device: [String: Any]?
    private var app: [String: Any]?
    private var network: [String: Any]?
    private var debug: [String: Any]?
    private let locale: String
    private let timezone: String
    private let now: () -> Date
    private let createId: () -> String
    private let maxQueueSize: Int
    private let maxBatchSize: Int
    private let maxPayloadBytes: Int
    private let flushAt: Int
    private let immediateFlushEvents: Set<String>
    private let retryAttempts: Int
    private let retryBaseDelayNanoseconds: UInt64
    private let delay: (UInt64) async throws -> Void
    private let sessionTimeout: TimeInterval
    private let onBatchRejected: (([String: Any]) -> Void)?

    private var consentState: ConsentState
    private var anonymousUserId: String?
    private var superProperties: [String: Any] = [:]
    private var sessionId: String?
    private var sessionStartedAt: Date?
    private var sessionPausedAt: Date?
    private var lastScreenAt: Date?
    private var sessionLastScreen: String?
    private var sessionEventCount: Int = 0
    private var sessionScreenCount: Int = 0
    private var isFlushing: Bool = false
    private var queue: [[String: Any]] = []

    public var pendingCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return queue.count
    }

    public init(
        baseURL: URL,
        appKey: String,
        productId: String,
        platform: String,
        appVersion: String,
        buildNumber: String,
        installationId: String,
        transport: ShuYiShuTransport = URLSessionShuYiShuTransport(),
        device: [String: Any]? = nil,
        app: [String: Any]? = nil,
        network: [String: Any]? = nil,
        debug: [String: Any]? = nil,
        country: String? = nil,
        initialSuperProperties: [String: Any] = [:],
        locale: String = Locale.current.identifier,
        timezone: String = TimeZone.current.identifier,
        maxQueueSize: Int = 500,
        maxBatchSize: Int = 100,
        maxPayloadBytes: Int = 32 * 1024,
        flushAt: Int = 20,
        immediateFlushEvents: Set<String> = [],
        retryAttempts: Int = 2,
        retryBaseDelayNanoseconds: UInt64 = 500_000_000,
        delay: ((UInt64) async throws -> Void)? = nil,
        sessionTimeout: TimeInterval = 30,
        storage: ShuYiShuStorage? = nil,
        queueStorageKey: String = "shuyishu.event_queue",
        firstOpenStorageKey: String = "shuyishu.first_open_at",
        lastAppVersionStorageKey: String = "shuyishu.last_app_version",
        consentState: ConsentState = .unknown,
        onBatchRejected: (([String: Any]) -> Void)? = nil,
        now: @escaping () -> Date = Date.init,
        createId: @escaping () -> String = ShuYiShuAnalytics.defaultEventId
    ) {
        self.baseURL = baseURL
        self.appKey = appKey
        self.productId = productId
        self.platform = platform
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.installationId = installationId
        self.transport = transport
        self.device = device
        self.network = network
        self.debug = debug
        self.country = Self.normalizeCountry(country)
        self.locale = locale
        self.timezone = timezone
        self.maxQueueSize = maxQueueSize
        self.maxBatchSize = maxBatchSize
        self.maxPayloadBytes = maxPayloadBytes
        self.flushAt = flushAt
        self.immediateFlushEvents = immediateFlushEvents
        self.retryAttempts = retryAttempts
        self.retryBaseDelayNanoseconds = retryBaseDelayNanoseconds
        self.delay = delay ?? { nanoseconds in
            try await Task.sleep(nanoseconds: nanoseconds)
        }
        self.sessionTimeout = sessionTimeout
        self.storage = storage
        self.queueStorageKey = queueStorageKey
        self.consentState = consentState
        self.onBatchRejected = onBatchRejected
        self.now = now
        self.createId = createId
        self.superProperties = initialSuperProperties

        let lifecycleApp = Self.resolveInstallLifecycleContext(
            storage: storage,
            firstOpenStorageKey: firstOpenStorageKey,
            lastAppVersionStorageKey: lastAppVersionStorageKey,
            appVersion: appVersion,
            now: now
        )
        var mergedApp = lifecycleApp ?? [:]
        if let app {
            for (key, value) in app {
                mergedApp[key] = value
            }
        }
        self.app = mergedApp.isEmpty ? nil : mergedApp

        self.queue = Self.loadQueue(
            storage: storage,
            queueStorageKey: queueStorageKey,
            maxQueueSize: maxQueueSize
        )
    }

    public func setCountry(_ country: String?) {
        lock.lock()
        defer { lock.unlock() }
        self.country = Self.normalizeCountry(country)
    }

    public func setDeviceContext(_ device: [String: Any]?) {
        lock.lock()
        defer { lock.unlock() }
        self.device = device
    }

    public func setAppContext(_ app: [String: Any]?) {
        lock.lock()
        defer { lock.unlock() }
        self.app = app
    }

    public func setNetworkContext(_ network: [String: Any]?) {
        lock.lock()
        defer { lock.unlock() }
        self.network = network
    }

    public func setDebugContext(_ debug: [String: Any]?) {
        lock.lock()
        defer { lock.unlock() }
        self.debug = debug
    }

    public func setSuperProperties(_ properties: [String: Any]) {
        lock.lock()
        defer { lock.unlock() }
        for (key, value) in properties {
            superProperties[key] = value
        }
    }

    public func setSuperProperty(_ key: String, value: Any?) {
        lock.lock()
        defer { lock.unlock() }
        if let value {
            superProperties[key] = value
        } else {
            superProperties.removeValue(forKey: key)
        }
    }

    public func removeSuperProperty(_ key: String) {
        lock.lock()
        defer { lock.unlock() }
        superProperties.removeValue(forKey: key)
    }

    public func clearSuperProperties() {
        lock.lock()
        defer { lock.unlock() }
        superProperties.removeAll()
    }

    public func track(_ eventName: String, properties: [String: Any] = [:]) {
        let shouldAutoFlush: Bool = withLock {
            enqueueLocked(eventName, properties: properties)
        }
        if shouldAutoFlush {
            Task { [self] in
                try? await self.flush()
            }
        }
    }

    public func screen(_ screenName: String, properties: [String: Any] = [:]) {
        let shouldAutoFlush: Bool = withLock {
            guard consentState == .granted else { return false }
            let currentNow = now()
            var merged: [String: Any] = [:]
            if let sessionLastScreen, sessionLastScreen != screenName {
                merged["previous_screen"] = sessionLastScreen
            }
            if let lastScreenAt {
                let dwellMs = max(0, Int(currentNow.timeIntervalSince(lastScreenAt) * 1000))
                merged["dwell_ms"] = dwellMs
            }
            for (key, value) in properties {
                merged[key] = value
            }
            merged["screen"] = screenName

            sessionLastScreen = screenName
            lastScreenAt = currentNow
            if sessionId != nil {
                sessionScreenCount += 1
            }
            return enqueueLocked("screen_view", properties: merged)
        }
        if shouldAutoFlush {
            Task { [self] in
                try? await self.flush()
            }
        }
    }

    public func startSession(properties: [String: Any] = [:]) {
        let shouldAutoFlush: Bool = withLock {
            startSessionLocked(properties: properties)
        }
        if shouldAutoFlush {
            Task { [self] in
                try? await self.flush()
            }
        }
    }

    public func endSession(properties: [String: Any] = [:], endedAt: Date? = nil) {
        let shouldAutoFlush: Bool = withLock {
            endSessionLocked(properties: properties, endedAt: endedAt)
        }
        if shouldAutoFlush {
            Task { [self] in
                try? await self.flush()
            }
        }
    }

    public func handleAppBackgrounded() async {
        withLock {
            guard consentState == .granted else { return }
            if sessionId != nil {
                if sessionPausedAt == nil {
                    sessionPausedAt = now()
                }
                if sessionTimeout <= 0 {
                    _ = endSessionLocked(
                        properties: ["end_reason": "background_timeout"],
                        endedAt: sessionPausedAt
                    )
                }
            }
        }
        try? await flush()
    }

    @discardableResult
    public func handleAppForegrounded() -> Bool {
        let result: (startedNew: Bool, shouldAutoFlush: Bool) = withLock {
            guard consentState == .granted else { return (false, false) }
            if sessionId == nil {
                let flushNow = startSessionLocked()
                return (true, flushNow)
            }
            if let pausedAt = sessionPausedAt {
                sessionPausedAt = nil
                if now().timeIntervalSince(pausedAt) >= sessionTimeout {
                    let flushEnd = endSessionLocked(
                        properties: ["end_reason": "background_timeout"],
                        endedAt: pausedAt
                    )
                    let flushStart = startSessionLocked()
                    return (true, flushEnd || flushStart)
                }
            }
            return (false, false)
        }
        if result.shouldAutoFlush {
            Task { [self] in
                try? await self.flush()
            }
        }
        return result.startedNew
    }

    public func setConsent(_ consentState: ConsentState) {
        withLock {
            self.consentState = consentState
            if consentState == .denied {
                queue.removeAll()
                superProperties.removeAll()
                sessionId = nil
                sessionStartedAt = nil
                sessionPausedAt = nil
                lastScreenAt = nil
                sessionLastScreen = nil
                sessionEventCount = 0
                sessionScreenCount = 0
                anonymousUserId = nil
                persistQueueLocked()
            }
        }
    }

    public func setUserId(_ userId: String) {
        withLock {
            anonymousUserId = userId
        }
    }

    public func clearUserId() {
        withLock {
            anonymousUserId = nil
        }
    }

    public func flush() async throws {
        let canStart: Bool = withLock {
            guard consentState == .granted, !queue.isEmpty, !isFlushing else { return false }
            isFlushing = true
            return true
        }
        guard canStart else { return }
        defer {
            withLock { isFlushing = false }
        }

        while true {
            let drained: (body: String, events: [[String: Any]])? = try withLock {
                guard consentState == .granted, !queue.isEmpty else { return nil }
                let batch = try nextBatchLocked()
                let events = Array(queue.prefix(batch.eventCount))
                queue.removeFirst(batch.eventCount)
                persistQueueLocked()
                return (body: batch.body, events: events)
            }
            guard let drained else { break }

            do {
                try await postBatchWithRetry(body: drained.body)
            } catch let error as ShuYiShuIngestionError where !error.isRetryable {
                throw error
            } catch {
                withLock {
                    restore(drained.events)
                }
                throw error
            }
        }
    }

    private func startSessionLocked(properties: [String: Any] = [:]) -> Bool {
        guard consentState == .granted, sessionId == nil else { return false }
        sessionId = createId()
        sessionStartedAt = now()
        sessionPausedAt = nil
        lastScreenAt = nil
        sessionLastScreen = nil
        sessionEventCount = 0
        sessionScreenCount = 0
        return enqueueLocked("session_start", properties: properties)
    }

    private func endSessionLocked(properties: [String: Any] = [:], endedAt: Date? = nil) -> Bool {
        guard let endingSessionId = sessionId else { return false }
        let endTime = endedAt ?? now()
        let durationMs = sessionStartedAt.map { max(0, Int(endTime.timeIntervalSince($0) * 1000)) }
        let eventCount = sessionEventCount
        let screenCount = sessionScreenCount
        let lastScreen = sessionLastScreen

        sessionId = nil
        sessionStartedAt = nil
        sessionPausedAt = nil
        lastScreenAt = nil
        sessionLastScreen = nil
        sessionEventCount = 0
        sessionScreenCount = 0

        var merged: [String: Any] = [
            "event_count": eventCount,
            "screen_count": screenCount
        ]
        if let durationMs {
            merged["duration_ms"] = durationMs
        }
        if let lastScreen {
            merged["last_screen"] = lastScreen
        }
        for (key, value) in properties {
            merged[key] = value
        }

        return enqueueLocked("session_end", properties: merged, sessionIdOverride: endingSessionId)
    }

    @discardableResult
    private func enqueueLocked(
        _ eventName: String,
        properties: [String: Any],
        sessionIdOverride: String? = nil
    ) -> Bool {
        guard consentState == .granted else { return false }

        var combinedProperties = superProperties
        for (key, value) in properties {
            combinedProperties[key] = value
        }
        let sanitizedProperties = Self.sanitizeProperties(combinedProperties)

        var event: [String: Any] = [
            "event_schema_version": 1,
            "event_id": createId(),
            "event_name": eventName,
            "product_id": productId,
            "app_key": appKey,
            "platform": platform,
            "app_version": appVersion,
            "build_number": buildNumber,
            "anonymous_installation_id": installationId,
            "timestamp": Self.formatTimestamp(now()),
            "timezone": timezone,
            "locale": locale,
            "properties": sanitizedProperties,
            "consent_state": consentState.rawValue,
            "sdk_name": "shuyishu-ios",
            "sdk_version": "0.3.0"
        ]

        if let anonymousUserId {
            event["anonymous_user_id"] = anonymousUserId
        }
        if let activeSessionId = sessionIdOverride ?? sessionId {
            event["session_id"] = activeSessionId
        }
        if let country {
            event["country"] = country
        }
        if let device, !device.isEmpty {
            event["device"] = device
        }
        if let app, !app.isEmpty {
            event["app"] = app
        }
        if let network, !network.isEmpty {
            event["network"] = network
        }
        if let debug, !debug.isEmpty {
            event["debug"] = debug
        }

        if let bytes = try? measureEnvelopeBytes([event]), bytes > maxPayloadBytes {
            return false
        }

        if sessionIdOverride == nil && sessionId != nil {
            sessionEventCount += 1
        }

        queue.append(event)
        while queue.count > maxQueueSize {
            queue.removeFirst()
        }
        persistQueueLocked()

        return immediateFlushEvents.contains(eventName) || (flushAt > 0 && queue.count >= flushAt)
    }

    private func nextBatchLocked() throws -> (body: String, eventCount: Int) {
        var events: [[String: Any]] = []
        var body = try encodeEnvelope(events)

        for event in queue.prefix(maxBatchSize) {
            let candidate = events + [event]
            let candidateBody = try encodeEnvelope(candidate)
            if candidateBody.utf8.count > maxPayloadBytes {
                break
            }
            events = candidate
            body = candidateBody
        }

        if events.isEmpty, let first = queue.first {
            let bytes = try measureEnvelopeBytes([first])
            throw ShuYiShuEventTooLargeError(actualBytes: bytes, maxBytes: maxPayloadBytes)
        }

        return (body: body, eventCount: events.count)
    }

    private func postBatchWithRetry(body: String) async throws {
        var lastError: Error = ShuYiShuIngestionError(statusCode: 0)

        for attempt in 0...retryAttempts {
            do {
                let response = try await transport.postJson(
                    TransportRequest(
                        url: eventsURL(),
                        headers: ["content-type": "application/json"],
                        body: body
                    )
                )
                if response.isSuccess {
                    notifyPartialRejectionIfNeeded(response.body)
                    return
                }
                let ingestionError = ShuYiShuIngestionError(statusCode: response.statusCode)
                if !ingestionError.isRetryable {
                    throw ingestionError
                }
                lastError = ingestionError
            } catch let error as ShuYiShuIngestionError where !error.isRetryable {
                throw error
            } catch {
                lastError = error
            }

            if attempt < retryAttempts {
                let backoff = retryBaseDelayNanoseconds * UInt64(1 << attempt)
                try await delay(backoff)
            }
        }

        throw lastError
    }

    private func notifyPartialRejectionIfNeeded(_ responseBody: String) {
        guard let onBatchRejected,
              let data = responseBody.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rejected = json["rejected"] as? Int,
              rejected > 0 else {
            return
        }
        onBatchRejected(json)
    }

    private func encodeEnvelope(_ events: [[String: Any]]) throws -> String {
        let payload: [String: Any] = [
            "events": events,
            "sent_at": Self.formatTimestamp(now())
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: payload, options: [])
        return String(data: bodyData, encoding: .utf8) ?? #"{"events":[]}"#
    }

    private func measureEnvelopeBytes(_ events: [[String: Any]]) throws -> Int {
        try encodeEnvelope(events).utf8.count
    }

    private func restore(_ events: [[String: Any]]) {
        queue = Array((events + queue).prefix(maxQueueSize))
        persistQueueLocked()
    }

    private func persistQueueLocked() {
        guard let storage else { return }
        if let data = try? JSONSerialization.data(withJSONObject: queue, options: []),
           let encoded = String(data: data, encoding: .utf8) {
            storage.writeString(encoded, forKey: queueStorageKey)
        }
    }

    private func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try operation()
    }

    private static func sanitizeProperties(_ properties: [String: Any]) -> [String: Any] {
        var clean: [String: Any] = [:]
        for (key, value) in properties {
            let normalized = key.lowercased()
            if forbiddenPropertyFragments.contains(where: { normalized.contains($0) }) {
                continue
            }
            clean[key] = value
        }
        return clean
    }

    private static func resolveInstallLifecycleContext(
        storage: ShuYiShuStorage?,
        firstOpenStorageKey: String,
        lastAppVersionStorageKey: String,
        appVersion: String,
        now: () -> Date
    ) -> [String: Any]? {
        guard let storage else { return nil }
        let currentNow = now()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let storedFirstOpen = storage.readString(forKey: firstOpenStorageKey)
        let firstOpenDate = storedFirstOpen.flatMap { formatter.date(from: $0) }
        let isFirstLaunch = firstOpenDate == nil
        let resolvedFirstOpen = firstOpenDate ?? currentNow
        if isFirstLaunch {
            storage.writeString(formatter.string(from: resolvedFirstOpen), forKey: firstOpenStorageKey)
        }

        let installAgeDays = max(0, Int(currentNow.timeIntervalSince(resolvedFirstOpen) / 86_400))
        let previousVersion = storage.readString(forKey: lastAppVersionStorageKey)
        if previousVersion == nil || previousVersion != appVersion {
            storage.writeString(appVersion, forKey: lastAppVersionStorageKey)
        }

        var context: [String: Any] = [
            "first_open_at": formatter.string(from: resolvedFirstOpen),
            "is_first_launch": isFirstLaunch,
            "install_age_days": installAgeDays
        ]
        if let previousVersion, !previousVersion.isEmpty, previousVersion != appVersion {
            context["previous_app_version"] = previousVersion
        }
        return context
    }

    private static func loadQueue(
        storage: ShuYiShuStorage?,
        queueStorageKey: String,
        maxQueueSize: Int
    ) -> [[String: Any]] {
        guard let storage,
              let raw = storage.readString(forKey: queueStorageKey),
              let data = raw.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return Array(parsed.suffix(maxQueueSize))
    }

    private func eventsURL() -> URL {
        var url = baseURL
        url.appendPathComponent("api")
        url.appendPathComponent("events")
        return url
    }

    private static func normalizeCountry(_ country: String?) -> String? {
        guard let country else { return nil }
        let trimmed = country.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return trimmed.count == 2 ? trimmed : nil
    }

    public static func defaultEventId() -> String {
        "evt_\(UUID().uuidString.lowercased())"
    }

    private static func formatTimestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
