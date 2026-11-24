package top.youdroid.shuyishu

import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.nio.charset.StandardCharsets
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone
import java.util.UUID
import java.util.concurrent.Executors

enum class ConsentState(val rawValue: String) {
    GRANTED("granted"),
    DENIED("denied"),
    UNKNOWN("unknown")
}

interface ShuYiShuStorage {
    fun readString(key: String): String?
    fun writeString(key: String, value: String)
}

class InMemoryShuYiShuStorage : ShuYiShuStorage {
    private val store = LinkedHashMap<String, String>()

    @Synchronized
    override fun readString(key: String): String? = store[key]

    @Synchronized
    override fun writeString(key: String, value: String) {
        store[key] = value
    }
}

data class TransportRequest(
    val url: String,
    val headers: Map<String, String>,
    val body: String
)

data class TransportResponse(
    val statusCode: Int,
    val body: String
) {
    val isSuccess: Boolean
        get() = statusCode in 200..299
}

interface ShuYiShuTransport {
    fun postJson(request: TransportRequest): TransportResponse
}

class HttpURLConnectionShuYiShuTransport(
    private val connectTimeoutMs: Int = 5_000,
    private val readTimeoutMs: Int = 5_000
) : ShuYiShuTransport {
    override fun postJson(request: TransportRequest): TransportResponse {
        val connection = (URL(request.url).openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            connectTimeout = connectTimeoutMs
            readTimeout = readTimeoutMs
            doOutput = true
            for ((key, value) in request.headers) {
                setRequestProperty(key, value)
            }
        }
        try {
            OutputStreamWriter(connection.outputStream, StandardCharsets.UTF_8).use { writer ->
                writer.write(request.body)
                writer.flush()
            }
            val statusCode = connection.responseCode
            val stream = if (statusCode >= 400) connection.errorStream else connection.inputStream
            val body = stream?.bufferedReader(StandardCharsets.UTF_8)?.use { it.readText() } ?: ""
            return TransportResponse(statusCode = statusCode, body = body)
        } finally {
            connection.disconnect()
        }
    }
}

class ShuYiShuIngestionException(val statusCode: Int) :
    RuntimeException("Ingestion request failed with HTTP $statusCode") {
    val isRetryable: Boolean
        get() = statusCode == 408 || statusCode == 425 || statusCode == 429 || statusCode >= 500
}

class ShuYiShuEventTooLargeException(val actualBytes: Int, val maxBytes: Int) :
    RuntimeException("Event envelope ($actualBytes bytes) exceeds maxPayloadBytes ($maxBytes)")

class ShuYiShuAnalytics(
    baseUrl: String,
    private val appKey: String,
    private val productId: String,
    private val platform: String = "android",
    private val appVersion: String,
    private val buildNumber: String,
    private val installationId: String,
    private val transport: ShuYiShuTransport = HttpURLConnectionShuYiShuTransport(),
    device: Map<String, Any?>? = null,
    app: Map<String, Any?>? = null,
    network: Map<String, Any?>? = null,
    debug: Map<String, Any?>? = null,
    country: String? = null,
    initialSuperProperties: Map<String, Any?> = emptyMap(),
    private val locale: String = Locale.getDefault().toLanguageTag(),
    private val timezone: String = TimeZone.getDefault().id,
    private val maxQueueSize: Int = 500,
    private val maxBatchSize: Int = 100,
    private val maxPayloadBytes: Int = 32 * 1024,
    private val flushAt: Int = 20,
    private val immediateFlushEvents: Set<String> = emptySet(),
    private val retryAttempts: Int = 2,
    private val retryBaseDelayMs: Long = 500L,
    private val sleep: (Long) -> Unit = { millis -> Thread.sleep(millis) },
    private val sessionTimeoutMs: Long = 30_000L,
    private val storage: ShuYiShuStorage? = null,
    private val queueStorageKey: String = DEFAULT_QUEUE_STORAGE_KEY,
    firstOpenStorageKey: String = DEFAULT_FIRST_OPEN_STORAGE_KEY,
    lastAppVersionStorageKey: String = DEFAULT_LAST_APP_VERSION_STORAGE_KEY,
    consentState: ConsentState = ConsentState.UNKNOWN,
    private val onBatchRejected: ((Map<String, Any?>) -> Unit)? = null,
    private val onPropertySanitized: ((String) -> Unit)? = null,
    private val backgroundExecutor: ((Runnable) -> Unit)? = defaultBackgroundExecutor(),
    private val nowMs: () -> Long = { System.currentTimeMillis() },
    private val createId: () -> String = { defaultEventId() }
) {
    private val lock = Any()
    private val normalizedBaseUrl = baseUrl.trimEnd('/')

    private var country: String? = normalizeCountry(country)
    private var device: Map<String, Any?>? = device?.toMap()
    private var app: Map<String, Any?>?
    private var network: Map<String, Any?>? = network?.toMap()
    private var debug: Map<String, Any?>? = debug?.toMap()

    private var consentState: ConsentState = consentState
    private var anonymousUserId: String? = null
    private val superProperties = LinkedHashMap<String, Any?>().apply { putAll(initialSuperProperties) }

    private var sessionId: String? = null
    private var sessionStartedAtMs: Long? = null
    private var sessionPausedAtMs: Long? = null
    private var lastScreenAtMs: Long? = null
    private var sessionLastScreen: String? = null
    private var sessionEventCount: Int = 0
    private var sessionScreenCount: Int = 0
    private var isFlushing: Boolean = false
    private val queue = ArrayList<Map<String, Any?>>()

    init {
        val lifecycleApp = resolveInstallLifecycleContext(
            storage = storage,
            firstOpenStorageKey = firstOpenStorageKey,
            lastAppVersionStorageKey = lastAppVersionStorageKey,
            appVersion = appVersion,
            nowMs = nowMs
        )
        val mergedApp = LinkedHashMap<String, Any?>()
        if (lifecycleApp != null) {
            mergedApp.putAll(lifecycleApp)
        }
        if (app != null) {
            mergedApp.putAll(app)
        }
        this.app = if (mergedApp.isEmpty()) null else mergedApp
        queue.addAll(loadQueue(storage, queueStorageKey, maxQueueSize))
    }

    val pendingCount: Int
        get() = synchronized(lock) { queue.size }

    fun setCountry(country: String?) {
        synchronized(lock) {
            this.country = normalizeCountry(country)
        }
    }

    fun setDeviceContext(device: Map<String, Any?>?) {
        synchronized(lock) {
            this.device = device?.toMap()
        }
    }

    fun setAppContext(app: Map<String, Any?>?) {
        synchronized(lock) {
            this.app = app?.toMap()
        }
    }

    fun setNetworkContext(network: Map<String, Any?>?) {
        synchronized(lock) {
            this.network = network?.toMap()
        }
    }

    fun setDebugContext(debug: Map<String, Any?>?) {
        synchronized(lock) {
            this.debug = debug?.toMap()
        }
    }

    fun setSuperProperties(properties: Map<String, Any?>) {
        synchronized(lock) {
            for ((key, value) in properties) {
                if (value == null) {
                    superProperties.remove(key)
                } else {
                    superProperties[key] = value
                }
            }
        }
    }

    fun setSuperProperty(key: String, value: Any?) {
        synchronized(lock) {
            if (value == null) {
                superProperties.remove(key)
            } else {
                superProperties[key] = value
            }
        }
    }

    fun removeSuperProperty(key: String) {
        synchronized(lock) {
            superProperties.remove(key)
        }
    }

    fun clearSuperProperties() {
        synchronized(lock) {
            superProperties.clear()
        }
    }

    fun track(eventName: String, properties: Map<String, Any?> = emptyMap()) {
        val shouldAutoFlush = synchronized(lock) {
            enqueueLocked(eventName, properties)
        }
        if (shouldAutoFlush) {
            scheduleFlush()
        }
    }

    fun screen(screenName: String, properties: Map<String, Any?> = emptyMap()) {
        val shouldAutoFlush = synchronized(lock) {
            if (consentState != ConsentState.GRANTED) {
                return@synchronized false
            }
            val currentNow = nowMs()
            val merged = LinkedHashMap<String, Any?>()
            val lastScreen = sessionLastScreen
            if (lastScreen != null && lastScreen != screenName) {
                merged["previous_screen"] = lastScreen
            }
            val previousScreenAt = lastScreenAtMs
            if (previousScreenAt != null) {
                merged["dwell_ms"] = maxOf(0L, currentNow - previousScreenAt)
            }
            merged.putAll(properties)
            merged["screen"] = screenName

            sessionLastScreen = screenName
            lastScreenAtMs = currentNow
            if (sessionId != null) {
                sessionScreenCount += 1
            }
            enqueueLocked("screen_view", merged)
        }
        if (shouldAutoFlush) {
            scheduleFlush()
        }
    }

    fun startSession(properties: Map<String, Any?> = emptyMap()) {
        val shouldAutoFlush = synchronized(lock) {
            startSessionLocked(properties)
        }
        if (shouldAutoFlush) {
            scheduleFlush()
        }
    }

    fun endSession(properties: Map<String, Any?> = emptyMap(), endedAtMs: Long? = null) {
        val shouldAutoFlush = synchronized(lock) {
            endSessionLocked(properties, endedAtMs)
        }
        if (shouldAutoFlush) {
            scheduleFlush()
        }
    }

    fun handleAppBackgrounded() {
        synchronized(lock) {
            if (consentState != ConsentState.GRANTED) {
                return@synchronized
            }
            if (sessionId != null) {
                if (sessionPausedAtMs == null) {
                    sessionPausedAtMs = nowMs()
                }
                if (sessionTimeoutMs <= 0L) {
                    endSessionLocked(
                        properties = mapOf("end_reason" to "background_timeout"),
                        endedAtMs = sessionPausedAtMs
                    )
                }
            }
        }
        scheduleFlush()
    }

    fun handleAppForegrounded(): Boolean {
        val (startedNew, shouldAutoFlush) = synchronized(lock) {
            if (consentState != ConsentState.GRANTED) {
                return@synchronized false to false
            }
            if (sessionId == null) {
                val flushNow = startSessionLocked()
                return@synchronized true to flushNow
            }
            val pausedAt = sessionPausedAtMs
            if (pausedAt != null) {
                sessionPausedAtMs = null
                if (nowMs() - pausedAt >= sessionTimeoutMs) {
                    val flushEnd = endSessionLocked(
                        properties = mapOf("end_reason" to "background_timeout"),
                        endedAtMs = pausedAt
                    )
                    val flushStart = startSessionLocked()
                    return@synchronized true to (flushEnd || flushStart)
                }
            }
            false to false
        }
        if (shouldAutoFlush) {
            scheduleFlush()
        }
        return startedNew
    }

    fun setConsent(consentState: ConsentState) {
        synchronized(lock) {
            this.consentState = consentState
            if (consentState == ConsentState.DENIED) {
                queue.clear()
                superProperties.clear()
                sessionId = null
                sessionStartedAtMs = null
                sessionPausedAtMs = null
                lastScreenAtMs = null
                sessionLastScreen = null
                sessionEventCount = 0
                sessionScreenCount = 0
                anonymousUserId = null
                persistQueueLocked()
            }
        }
    }

    fun setUserId(userId: String) {
        synchronized(lock) {
            anonymousUserId = userId
        }
    }

    fun clearUserId() {
        synchronized(lock) {
            anonymousUserId = null
        }
    }

    fun flush() {
        val canStart = synchronized(lock) {
            if (consentState != ConsentState.GRANTED || queue.isEmpty() || isFlushing) {
                false
            } else {
                isFlushing = true
                true
            }
        }
        if (!canStart) {
            return
        }

        try {
            while (true) {
                val drained = synchronized(lock) {
                    if (consentState != ConsentState.GRANTED || queue.isEmpty()) {
                        return@synchronized null
                    }
                    val (body, count) = nextBatchLocked()
                    val drainedEvents = ArrayList(queue.subList(0, count))
                    queue.subList(0, count).clear()
                    persistQueueLocked()
                    body to drainedEvents
                } ?: break

                try {
                    postBatchWithRetry(drained.first)
                } catch (error: ShuYiShuIngestionException) {
                    if (!error.isRetryable) {
                        throw error
                    }
                    synchronized(lock) {
                        restoreLocked(drained.second)
                    }
                    throw error
                } catch (error: Throwable) {
                    synchronized(lock) {
                        restoreLocked(drained.second)
                    }
                    throw error
                }
            }
        } finally {
            synchronized(lock) {
                isFlushing = false
            }
        }
    }

    private fun scheduleFlush() {
        val executor = backgroundExecutor ?: return
        executor.invoke(Runnable {
            try {
                flush()
            } catch (_: Throwable) {
                // Non-fatal in fire-and-forget flush; queue stays persisted for retry.
            }
        })
    }

    private fun startSessionLocked(properties: Map<String, Any?> = emptyMap()): Boolean {
        if (consentState != ConsentState.GRANTED || sessionId != null) {
            return false
        }
        sessionId = createId()
        sessionStartedAtMs = nowMs()
        sessionPausedAtMs = null
        lastScreenAtMs = null
        sessionLastScreen = null
        sessionEventCount = 0
        sessionScreenCount = 0
        return enqueueLocked("session_start", properties)
    }

    private fun endSessionLocked(
        properties: Map<String, Any?> = emptyMap(),
        endedAtMs: Long? = null
    ): Boolean {
        val endingSessionId = sessionId ?: return false
        val endTime = endedAtMs ?: nowMs()
        val durationMs = sessionStartedAtMs?.let { maxOf(0L, endTime - it) }
        val eventCount = sessionEventCount
        val screenCount = sessionScreenCount
        val lastScreen = sessionLastScreen

        sessionId = null
        sessionStartedAtMs = null
        sessionPausedAtMs = null
        lastScreenAtMs = null
        sessionLastScreen = null
        sessionEventCount = 0
        sessionScreenCount = 0

        val merged = LinkedHashMap<String, Any?>()
        merged["event_count"] = eventCount
        merged["screen_count"] = screenCount
        if (durationMs != null) {
            merged["duration_ms"] = durationMs
        }
        if (lastScreen != null) {
            merged["last_screen"] = lastScreen
        }
        merged.putAll(properties)

        return enqueueLocked("session_end", merged, sessionIdOverride = endingSessionId)
    }

    private fun enqueueLocked(
        eventName: String,
        properties: Map<String, Any?>,
        sessionIdOverride: String? = null
    ): Boolean {
        if (consentState != ConsentState.GRANTED) {
            return false
        }

        val combined = LinkedHashMap<String, Any?>()
        combined.putAll(superProperties)
        for ((key, value) in properties) {
            if (value == null) {
                combined.remove(key)
            } else {
                combined[key] = value
            }
        }
        val sanitized = sanitizeProperties(combined)

        val event = LinkedHashMap<String, Any?>()
        event["event_schema_version"] = 1
        event["event_id"] = createId()
        event["event_name"] = eventName
        event["product_id"] = productId
        event["app_key"] = appKey
        event["platform"] = platform
        event["app_version"] = appVersion
        event["build_number"] = buildNumber
        event["anonymous_installation_id"] = installationId
        event["timestamp"] = formatTimestamp(nowMs())
        event["timezone"] = timezone
        event["locale"] = locale
        event["properties"] = sanitized
        event["consent_state"] = consentState.rawValue
        event["sdk_name"] = SDK_NAME
        event["sdk_version"] = SDK_VERSION

        anonymousUserId?.let { event["anonymous_user_id"] = it }
        (sessionIdOverride ?: sessionId)?.let { event["session_id"] = it }
        country?.let { event["country"] = it }
        device?.takeIf { it.isNotEmpty() }?.let { event["device"] = it }
        app?.takeIf { it.isNotEmpty() }?.let { event["app"] = it }
        network?.takeIf { it.isNotEmpty() }?.let { event["network"] = it }
        debug?.takeIf { it.isNotEmpty() }?.let { event["debug"] = it }

        if (measureEnvelopeBytes(listOf(event)) > maxPayloadBytes) {
            return false
        }

        if (sessionIdOverride == null && sessionId != null) {
            sessionEventCount += 1
        }

        queue.add(event)
        while (queue.size > maxQueueSize) {
            queue.removeAt(0)
        }
        persistQueueLocked()

        return immediateFlushEvents.contains(eventName) || (flushAt > 0 && queue.size >= flushAt)
    }

    private fun sanitizeProperties(properties: Map<String, Any?>): Map<String, Any?> {
        val clean = LinkedHashMap<String, Any?>()
        for ((key, value) in properties) {
            if (value == null) continue
            val normalized = key.lowercase(Locale.US)
            if (FORBIDDEN_PROPERTY_FRAGMENTS.any { normalized.contains(it) }) {
                onPropertySanitized?.invoke(key)
                continue
            }
            clean[key] = value
        }
        return clean
    }

    private fun nextBatchLocked(): Pair<String, Int> {
        val events = ArrayList<Map<String, Any?>>()
        var body = encodeEnvelope(events)
        val limit = minOf(maxBatchSize, queue.size)

        for (i in 0 until limit) {
            val event = queue[i]
            val candidate = ArrayList<Map<String, Any?>>(events.size + 1)
            candidate.addAll(events)
            candidate.add(event)
            val candidateBody = encodeEnvelope(candidate)
            if (candidateBody.toByteArray(StandardCharsets.UTF_8).size > maxPayloadBytes) {
                break
            }
            events.add(event)
            body = candidateBody
        }

        if (events.isEmpty() && queue.isNotEmpty()) {
            val bytes = measureEnvelopeBytes(listOf(queue.first()))
            throw ShuYiShuEventTooLargeException(actualBytes = bytes, maxBytes = maxPayloadBytes)
        }

        return body to events.size
    }

    private fun postBatchWithRetry(body: String) {
        var lastError: Throwable = ShuYiShuIngestionException(0)

        for (attempt in 0..retryAttempts) {
            try {
                val response = transport.postJson(
                    TransportRequest(
                        url = eventsUrl(),
                        headers = mapOf("content-type" to "application/json"),
                        body = body
                    )
                )
                if (response.isSuccess) {
                    notifyPartialRejectionIfNeeded(response.body)
                    return
                }
                val ingestionError = ShuYiShuIngestionException(response.statusCode)
                if (!ingestionError.isRetryable) {
                    throw ingestionError
                }
                lastError = ingestionError
            } catch (error: ShuYiShuIngestionException) {
                if (!error.isRetryable) {
                    throw error
                }
                lastError = error
            } catch (error: Throwable) {
                lastError = error
            }

            if (attempt < retryAttempts) {
                val backoff = retryBaseDelayMs * (1L shl attempt)
                sleep(backoff)
            }
        }

        throw lastError
    }

    private fun notifyPartialRejectionIfNeeded(responseBody: String) {
        val callback = onBatchRejected ?: return
        if (responseBody.isBlank()) return
        val parsed = runCatching { ShuYiShuJson.parseObject(responseBody) }.getOrNull() ?: return
        val rejected = (parsed["rejected"] as? Number)?.toInt() ?: return
        if (rejected > 0) {
            callback(parsed)
        }
    }

    private fun encodeEnvelope(events: List<Map<String, Any?>>): String {
        val payload = LinkedHashMap<String, Any?>()
        payload["events"] = events
        payload["sent_at"] = formatTimestamp(nowMs())
        return ShuYiShuJson.stringify(payload)
    }

    private fun measureEnvelopeBytes(events: List<Map<String, Any?>>): Int =
        encodeEnvelope(events).toByteArray(StandardCharsets.UTF_8).size

    private fun restoreLocked(events: List<Map<String, Any?>>) {
        val combined = ArrayList<Map<String, Any?>>(events.size + queue.size)
        combined.addAll(events)
        combined.addAll(queue)
        queue.clear()
        val end = minOf(maxQueueSize, combined.size)
        for (i in 0 until end) {
            queue.add(combined[i])
        }
        persistQueueLocked()
    }

    private fun persistQueueLocked() {
        val store = storage ?: return
        store.writeString(queueStorageKey, ShuYiShuJson.stringify(queue))
    }

    private fun eventsUrl(): String = "$normalizedBaseUrl/api/events"

    companion object {
        const val SDK_NAME = "shuyishu-android"
        const val SDK_VERSION = "0.1.0"
        private const val DEFAULT_QUEUE_STORAGE_KEY = "shuyishu.event_queue"
        private const val DEFAULT_FIRST_OPEN_STORAGE_KEY = "shuyishu.first_open_at"
        private const val DEFAULT_LAST_APP_VERSION_STORAGE_KEY = "shuyishu.last_app_version"
        private const val MILLIS_PER_DAY = 86_400_000L

        private val FORBIDDEN_PROPERTY_FRAGMENTS = listOf(
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
        )

        fun defaultEventId(): String = "evt_${UUID.randomUUID().toString().lowercase(Locale.US)}"

        private fun defaultBackgroundExecutor(): (Runnable) -> Unit {
            val executor = Executors.newSingleThreadExecutor { runnable ->
                Thread(runnable, "shuyishu-analytics").apply { isDaemon = true }
            }
            return { task -> executor.execute(task) }
        }

        private fun normalizeCountry(country: String?): String? {
            if (country == null) return null
            val trimmed = country.trim().uppercase(Locale.US)
            return if (trimmed.length == 2) trimmed else null
        }

        private fun formatTimestamp(epochMs: Long): String {
            val formatter = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
                timeZone = TimeZone.getTimeZone("UTC")
            }
            return formatter.format(epochMs)
        }

        private fun parseTimestamp(value: String): Long? = runCatching {
            val formatter = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
                timeZone = TimeZone.getTimeZone("UTC")
            }
            formatter.parse(value)?.time
        }.getOrNull()

        private fun resolveInstallLifecycleContext(
            storage: ShuYiShuStorage?,
            firstOpenStorageKey: String,
            lastAppVersionStorageKey: String,
            appVersion: String,
            nowMs: () -> Long
        ): Map<String, Any?>? {
            if (storage == null) return null
            val currentNow = nowMs()
            val storedFirstOpen = storage.readString(firstOpenStorageKey)
            val parsedFirstOpenMs = storedFirstOpen?.let { parseTimestamp(it) }
            val isFirstLaunch = parsedFirstOpenMs == null
            val resolvedFirstOpenMs = parsedFirstOpenMs ?: currentNow
            if (isFirstLaunch) {
                storage.writeString(firstOpenStorageKey, formatTimestamp(resolvedFirstOpenMs))
            }

            val installAgeDays = maxOf(0L, (currentNow - resolvedFirstOpenMs) / MILLIS_PER_DAY)
            val previousVersion = storage.readString(lastAppVersionStorageKey)
            if (previousVersion == null || previousVersion != appVersion) {
                storage.writeString(lastAppVersionStorageKey, appVersion)
            }

            val context = LinkedHashMap<String, Any?>()
            context["first_open_at"] = formatTimestamp(resolvedFirstOpenMs)
            context["is_first_launch"] = isFirstLaunch
            context["install_age_days"] = installAgeDays
            if (!previousVersion.isNullOrEmpty() && previousVersion != appVersion) {
                context["previous_app_version"] = previousVersion
            }
            return context
        }

        @Suppress("UNCHECKED_CAST")
        private fun loadQueue(
            storage: ShuYiShuStorage?,
            queueStorageKey: String,
            maxQueueSize: Int
        ): List<Map<String, Any?>> {
            if (storage == null) return emptyList()
            val raw = storage.readString(queueStorageKey) ?: return emptyList()
            val parsed = runCatching { ShuYiShuJson.parseArray(raw) }.getOrNull() ?: return emptyList()
            val items = parsed.mapNotNull { it as? Map<String, Any?> }
            return if (items.size <= maxQueueSize) items else items.takeLast(maxQueueSize)
        }
    }
}

internal object ShuYiShuJson {
    fun stringify(value: Any?): String {
        val sb = StringBuilder()
        writeValue(value, sb)
        return sb.toString()
    }

    private fun writeValue(value: Any?, sb: StringBuilder) {
        when (value) {
            null -> sb.append("null")
            is Boolean -> sb.append(if (value) "true" else "false")
            is Int, is Long -> sb.append(value.toString())
            is Double -> {
                if (value.isNaN() || value.isInfinite()) sb.append("null")
                else if (value == value.toLong().toDouble()) sb.append(value.toLong().toString())
                else sb.append(value.toString())
            }
            is Float -> {
                if (value.isNaN() || value.isInfinite()) sb.append("null")
                else sb.append(value.toString())
            }
            is Number -> sb.append(value.toString())
            is String -> writeString(value, sb)
            is Map<*, *> -> {
                sb.append('{')
                var first = true
                for ((k, v) in value) {
                    if (k == null) continue
                    if (!first) sb.append(',')
                    first = false
                    writeString(k.toString(), sb)
                    sb.append(':')
                    writeValue(v, sb)
                }
                sb.append('}')
            }
            is Iterable<*> -> {
                sb.append('[')
                var first = true
                for (item in value) {
                    if (!first) sb.append(',')
                    first = false
                    writeValue(item, sb)
                }
                sb.append(']')
            }
            is Array<*> -> {
                sb.append('[')
                for (i in value.indices) {
                    if (i > 0) sb.append(',')
                    writeValue(value[i], sb)
                }
                sb.append(']')
            }
            else -> writeString(value.toString(), sb)
        }
    }

    private fun writeString(text: String, sb: StringBuilder) {
        sb.append('"')
        for (ch in text) {
            when (ch) {
                '"' -> sb.append("\\\"")
                '\\' -> sb.append("\\\\")
                '\b' -> sb.append("\\b")
                '\u000C' -> sb.append("\\f")
                '\n' -> sb.append("\\n")
                '\r' -> sb.append("\\r")
                '\t' -> sb.append("\\t")
                else -> {
                    if (ch.code < 0x20) {
                        sb.append(String.format(Locale.US, "\\u%04x", ch.code))
                    } else {
                        sb.append(ch)
                    }
                }
            }
        }
        sb.append('"')
    }

    @Suppress("UNCHECKED_CAST")
    fun parseObject(json: String): Map<String, Any?> = Parser(json).parseRootObject()

    fun parseArray(json: String): List<Any?> = Parser(json).parseRootArray()

    private class Parser(private val src: String) {
        private var pos = 0

        fun parseRootObject(): Map<String, Any?> {
            skipWhitespace()
            val obj = readObject()
            skipWhitespace()
            if (pos != src.length) throw IllegalArgumentException("Trailing JSON characters")
            return obj
        }

        fun parseRootArray(): List<Any?> {
            skipWhitespace()
            val arr = readArray()
            skipWhitespace()
            if (pos != src.length) throw IllegalArgumentException("Trailing JSON characters")
            return arr
        }

        private fun readValue(): Any? {
            skipWhitespace()
            if (pos >= src.length) throw IllegalArgumentException("Unexpected end of JSON")
            return when (src[pos]) {
                '{' -> readObject()
                '[' -> readArray()
                '"' -> readString()
                't' -> readLiteral("true", true)
                'f' -> readLiteral("false", false)
                'n' -> readLiteral("null", null)
                '-', in '0'..'9' -> readNumber()
                else -> throw IllegalArgumentException("Unexpected char '${src[pos]}' at $pos")
            }
        }

        private fun readObject(): Map<String, Any?> {
            expect('{')
            val map = LinkedHashMap<String, Any?>()
            skipWhitespace()
            if (peek('}')) {
                pos++
                return map
            }
            while (true) {
                skipWhitespace()
                val key = readString()
                skipWhitespace()
                expect(':')
                val value = readValue()
                map[key] = value
                skipWhitespace()
                when {
                    peek(',') -> pos++
                    peek('}') -> {
                        pos++
                        return map
                    }
                    else -> throw IllegalArgumentException("Expected ',' or '}' at $pos")
                }
            }
        }

        private fun readArray(): List<Any?> {
            expect('[')
            val list = ArrayList<Any?>()
            skipWhitespace()
            if (peek(']')) {
                pos++
                return list
            }
            while (true) {
                list.add(readValue())
                skipWhitespace()
                when {
                    peek(',') -> pos++
                    peek(']') -> {
                        pos++
                        return list
                    }
                    else -> throw IllegalArgumentException("Expected ',' or ']' at $pos")
                }
            }
        }

        private fun readString(): String {
            expect('"')
            val sb = StringBuilder()
            while (pos < src.length) {
                val ch = src[pos++]
                when (ch) {
                    '"' -> return sb.toString()
                    '\\' -> {
                        if (pos >= src.length) throw IllegalArgumentException("Unterminated escape")
                        when (val esc = src[pos++]) {
                            '"' -> sb.append('"')
                            '\\' -> sb.append('\\')
                            '/' -> sb.append('/')
                            'b' -> sb.append('\b')
                            'f' -> sb.append('\u000C')
                            'n' -> sb.append('\n')
                            'r' -> sb.append('\r')
                            't' -> sb.append('\t')
                            'u' -> {
                                if (pos + 4 > src.length) throw IllegalArgumentException("Invalid unicode escape")
                                val hex = src.substring(pos, pos + 4)
                                pos += 4
                                sb.append(hex.toInt(16).toChar())
                            }
                            else -> throw IllegalArgumentException("Invalid escape '\\$esc'")
                        }
                    }
                    else -> sb.append(ch)
                }
            }
            throw IllegalArgumentException("Unterminated string")
        }

        private fun readNumber(): Number {
            val start = pos
            if (peek('-')) pos++
            while (pos < src.length && src[pos] in '0'..'9') pos++
            var isFloat = false
            if (peek('.')) {
                isFloat = true
                pos++
                while (pos < src.length && src[pos] in '0'..'9') pos++
            }
            if (pos < src.length && (src[pos] == 'e' || src[pos] == 'E')) {
                isFloat = true
                pos++
                if (peek('+') || peek('-')) pos++
                while (pos < src.length && src[pos] in '0'..'9') pos++
            }
            val token = src.substring(start, pos)
            return if (isFloat) token.toDouble() else {
                val longVal = token.toLong()
                if (longVal in Int.MIN_VALUE..Int.MAX_VALUE) longVal.toInt() else longVal
            }
        }

        private fun <T> readLiteral(literal: String, value: T): T {
            if (!src.startsWith(literal, pos)) {
                throw IllegalArgumentException("Expected $literal at $pos")
            }
            pos += literal.length
            return value
        }

        private fun skipWhitespace() {
            while (pos < src.length && src[pos].isWhitespace()) pos++
        }

        private fun peek(expected: Char): Boolean = pos < src.length && src[pos] == expected

        private fun expect(expected: Char) {
            if (pos >= src.length || src[pos] != expected) {
                throw IllegalArgumentException("Expected '$expected' at $pos")
            }
            pos++
        }
    }
}
