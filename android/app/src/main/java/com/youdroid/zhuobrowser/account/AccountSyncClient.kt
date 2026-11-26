package com.youdroid.zhuobrowser.account

import android.content.Context
import android.os.Build
import com.youdroid.zhuobrowser.policy.SearchEngine
import com.youdroid.zhuobrowser.session.BrowserSettings
import com.youdroid.zhuobrowser.session.BrowserTab
import com.youdroid.zhuobrowser.session.SavedItem
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.util.UUID

data class AuthActionResult(
    val ok: Boolean,
    val user: AccountUserProfile? = null,
    val identities: List<LinkedIdentityItem> = emptyList(),
    val pro: ProEntitlementState? = null,
    val errorMessage: String? = null
)

data class SyncRunOutcome(
    val ok: Boolean,
    val folders: List<BookmarkFolder> = emptyList(),
    val items: List<SavedItem> = emptyList(),
    val tombstones: List<BookmarkTombstone> = emptyList(),
    val settings: BrowserSettings? = null,
    val allowedHosts: List<String>? = null,
    val remoteDeviceTabs: List<RemoteDeviceTabGroup> = emptyList(),
    val pro: ProEntitlementState? = null,
    val lastSyncAt: Long = 0L,
    val unauthorized: Boolean = false,
    val errorMessage: String? = null
)

/**
 * Handles authentication, Pro entitlement binding, and v3 CAS scoped sync against auth-service.
 */
class AccountSyncClient(context: Context) {
    private val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    private val scopeVersions = mutableMapOf<String, Int>()
    private var cachedRemoteSettingsJson: JSONObject? = null
    private var cachedRemoteSiteControlsArray: JSONArray? = null

    init {
        restoreScopeVersions()
    }

    val deviceId: String
        get() {
            val existing = prefs.getString(KEY_DEVICE_ID, "").orEmpty()
            if (existing.isNotEmpty()) return existing
            val created = "android-${UUID.randomUUID()}"
            prefs.edit().putString(KEY_DEVICE_ID, created).apply()
            return created
        }

    val installId: String
        get() {
            val existing = prefs.getString(KEY_INSTALL_ID, "").orEmpty()
            if (existing.isNotEmpty()) return existing
            val created = "android-install-${UUID.randomUUID()}"
            prefs.edit().putString(KEY_INSTALL_ID, created).apply()
            return created
        }

    val deviceName: String
        get() = listOfNotNull(Build.MANUFACTURER, Build.MODEL)
            .joinToString(" ")
            .ifBlank { "Android" }

    var token: String
        get() = prefs.getString(KEY_TOKEN, "").orEmpty()
        private set(value) {
            prefs.edit().putString(KEY_TOKEN, value).apply()
        }

    var lastSyncAt: Long
        get() = prefs.getLong(KEY_LAST_SYNC_AT, 0L)
        private set(value) {
            prefs.edit().putLong(KEY_LAST_SYNC_AT, value).apply()
        }

    fun isLoggedIn(): Boolean = token.isNotEmpty() && savedUser() != null

    fun savedUser(): AccountUserProfile? {
        val raw = prefs.getString(KEY_PROFILE, "").orEmpty()
        if (raw.isEmpty()) return null
        return runCatching { parseUser(JSONObject(raw)) }.getOrNull()
    }

    fun savedProState(): ProEntitlementState {
        val raw = prefs.getString(KEY_PRO, "").orEmpty()
        if (raw.isEmpty()) return ProEntitlementState()
        return runCatching { parsePro(JSONObject(raw)) }.getOrDefault(ProEntitlementState())
    }

    fun sendEmailOtp(email: String): AuthActionResult {
        val clean = email.trim()
        if (clean.isEmpty()) return AuthActionResult(ok = false, errorMessage = "请输入邮箱地址")
        val body = JSONObject().put("email", clean)
        val res = requestJson("/api/auth/otp/send", "POST", body)
        return if (res.first == 200) {
            AuthActionResult(ok = true)
        } else {
            AuthActionResult(ok = false, errorMessage = res.second?.optString("error").orEmpty().ifEmpty { "发送验证码失败" })
        }
    }

    fun verifyEmailOtp(email: String, code: String, displayName: String): AuthActionResult {
        val body = JSONObject()
            .put("email", email.trim())
            .put("code", code.trim())
            .put("displayName", displayName.trim())
            .put("deviceId", deviceId)
            .put("deviceName", deviceName)
            .put("platform", "android")
        return performAuth("/api/auth/otp/verify", body)
    }

    fun loginWithPassword(email: String, password: String): AuthActionResult {
        val body = JSONObject()
            .put("email", email.trim())
            .put("password", password)
            .put("deviceId", deviceId)
            .put("deviceName", deviceName)
            .put("platform", "android")
        return performAuth("/api/auth/login", body)
    }

    fun registerWithPassword(email: String, password: String, displayName: String): AuthActionResult {
        val body = JSONObject()
            .put("email", email.trim())
            .put("password", password)
            .put("displayName", displayName.trim())
            .put("deviceId", deviceId)
            .put("deviceName", deviceName)
            .put("platform", "android")
        return performAuth("/api/auth/register", body)
    }

    fun buildGoogleWebOAuthStartUrl(): String {
        val redirectUri = URLEncoder.encode(OAUTH_CALLBACK_URI, "UTF-8")
        val encodedDeviceId = URLEncoder.encode(deviceId, "UTF-8")
        val encodedDeviceName = URLEncoder.encode(deviceName, "UTF-8")
        return "$PRIMARY_AUTH_BASE_URL/api/auth/oauth/google/start" +
            "?platform=android&client_redirect_uri=$redirectUri&device_id=$encodedDeviceId&device_name=$encodedDeviceName"
    }

    fun exchangeOAuthCallback(uriString: String): AuthActionResult {
        val query = uriString.substringAfter('?', "")
        val ticket = query.split('&')
            .mapNotNull { part ->
                val idx = part.indexOf('=')
                if (idx <= 0) null else part.substring(0, idx) to java.net.URLDecoder.decode(part.substring(idx + 1), "UTF-8")
            }
            .firstOrNull { it.first == "ticket" }
            ?.second
            .orEmpty()
        if (ticket.isEmpty()) {
            return AuthActionResult(ok = false, errorMessage = "OAuth 回调缺少 ticket")
        }
        return performAuth("/api/auth/oauth/exchange", JSONObject().put("ticket", ticket))
    }

    fun refreshMeAndPro(): AuthActionResult {
        val activeToken = token
        if (activeToken.isEmpty()) return AuthActionResult(ok = false)
        val res = requestJson("/api/auth/me", "GET", null, activeToken)
        if (res.first == 401 || res.first == 403) {
            clearLocalSession()
            return AuthActionResult(ok = false, errorMessage = "登录已过期，请重新登录")
        }
        if (res.first != 200 || res.second == null) {
            return AuthActionResult(ok = false, user = savedUser(), pro = savedProState())
        }
        val payload = res.second!!
        val user = payload.optJSONObject("user")?.let { parseUser(it) } ?: savedUser()
        val identities = parseIdentities(payload.optJSONArray("identities"))
        user?.let { saveUser(it, identities) }
        val pro = fetchProEntitlement()
        return AuthActionResult(ok = true, user = user, identities = identities, pro = pro)
    }

    fun fetchProEntitlement(): ProEntitlementState {
        val activeToken = token
        if (activeToken.isEmpty()) return ProEntitlementState()
        val res = requestJson("/api/pro/entitlement", "GET", null, activeToken)
        if (res.first != 200) return savedProState()
        val entObj = res.second?.optJSONObject("entitlement")
        val state = if (entObj != null) parsePro(entObj) else ProEntitlementState()
        prefs.edit().putString(KEY_PRO, encodePro(state).toString()).apply()
        return state
    }

    fun logout() {
        val activeToken = token
        if (activeToken.isNotEmpty()) {
            runCatching { requestJson("/api/auth/logout", "POST", JSONObject(), activeToken) }
        }
        clearLocalSession()
    }

    fun deleteAccount(): AuthActionResult {
        val activeToken = token
        if (activeToken.isEmpty()) return AuthActionResult(ok = false, errorMessage = "尚未登录")
        val res = requestJson("/api/auth/account", "DELETE", null, activeToken)
        return if (res.first == 200 || res.first == 401 || res.first == 404) {
            clearLocalSession()
            AuthActionResult(ok = true)
        } else {
            AuthActionResult(ok = false, errorMessage = res.second?.optString("error").orEmpty().ifEmpty { "账号注销失败" })
        }
    }

    fun syncV3(
        localFolders: List<BookmarkFolder>,
        localItems: List<SavedItem>,
        localTombstones: List<BookmarkTombstone>,
        localSettings: BrowserSettings,
        localAllowedHosts: List<String>,
        localTabs: List<BrowserTab>
    ): SyncRunOutcome {
        val activeToken = token
        if (activeToken.isEmpty()) {
            return SyncRunOutcome(ok = false, errorMessage = "尚未登录")
        }
        val encodedDeviceId = URLEncoder.encode(deviceId, "UTF-8")
        val pullRes = requestJson(
            "/api/sync/v3/pull?scopes=bookmarks,settings,site_controls,device_tabs&excludeDeviceId=$encodedDeviceId",
            "GET",
            null,
            activeToken
        )
        if (pullRes.first == 401 || pullRes.first == 403) {
            clearLocalSession()
            return SyncRunOutcome(ok = false, unauthorized = true, errorMessage = "登录凭据已过期，请重新登录")
        }
        if (pullRes.first != 200 || pullRes.second == null) {
            return SyncRunOutcome(ok = false, errorMessage = "拉取云端数据失败 (HTTP ${pullRes.first})")
        }
        val pullJson = pullRes.second!!
        val scopesObj = pullJson.optJSONObject("scopes") ?: JSONObject()

        var remoteFolders = emptyList<BookmarkFolder>()
        var remoteItems = emptyList<SavedItem>()
        var remoteTombstones = emptyList<BookmarkTombstone>()
        scopesObj.optJSONObject("bookmarks")?.let { env ->
            scopeVersions["bookmarks"] = env.optInt("version", 0)
            val parsed = parseBookmarksPayload(env.optJSONObject("payload"))
            remoteFolders = parsed.folders
            remoteItems = parsed.items
            remoteTombstones = parsed.tombstones
        }

        var remoteSettingsObj: JSONObject? = null
        scopesObj.optJSONObject("settings")?.let { env ->
            scopeVersions["settings"] = env.optInt("version", 0)
            remoteSettingsObj = env.optJSONObject("payload")
            if (remoteSettingsObj != null) cachedRemoteSettingsJson = remoteSettingsObj
        }

        var remoteSiteControlsArray: JSONArray? = null
        scopesObj.optJSONObject("site_controls")?.let { env ->
            scopeVersions["site_controls"] = env.optInt("version", 0)
            remoteSiteControlsArray = env.optJSONObject("payload")?.optJSONArray("controls")
            if (remoteSiteControlsArray != null) cachedRemoteSiteControlsArray = remoteSiteControlsArray
        }

        val remoteDeviceTabs = parseDeviceTabs(pullJson.optJSONArray("deviceTabs"))
        var mergedSettings = applySettingsFromRemote(localSettings, remoteSettingsObj)
        var mergedAllowedHosts = mergeAllowedHosts(localAllowedHosts, remoteSiteControlsArray)

        for (attempt in 0..2) {
            val nowMs = System.currentTimeMillis()
            val mergedBm = SyncMergePolicy.mergeBookmarks(
                localFolders = localFolders,
                remoteFolders = remoteFolders,
                localItems = localItems,
                remoteItems = remoteItems,
                localTombstones = localTombstones,
                remoteTombstones = remoteTombstones,
                nowMs = nowMs
            )

            val scopesPush = JSONObject()
                .put(
                    "bookmarks",
                    JSONObject()
                        .put("baseVersion", scopeVersions["bookmarks"] ?: 0)
                        .put("encryptionMode", "none")
                        .put("payload", encodeBookmarksPayload(mergedBm.folders, mergedBm.items, mergedBm.tombstones, nowMs))
                )
                .put(
                    "settings",
                    JSONObject()
                        .put("baseVersion", scopeVersions["settings"] ?: 0)
                        .put("encryptionMode", "none")
                        .put("payload", encodeSettingsPayload(mergedSettings, nowMs))
                )
                .put(
                    "site_controls",
                    JSONObject()
                        .put("baseVersion", scopeVersions["site_controls"] ?: 0)
                        .put("encryptionMode", "none")
                        .put("payload", encodeSiteControlsPayload(mergedAllowedHosts, nowMs))
                )

            val pushBody = JSONObject()
                .put("deviceId", deviceId)
                .put("deviceName", deviceName)
                .put("platform", "android")
                .put("scopes", scopesPush)
                .put("deviceTabs", encodeDeviceTabs(SyncMergePolicy.sanitizeDeviceTabs(localTabs)))

            val pushRes = requestJson("/api/sync/v3/push", "POST", pushBody, activeToken)
            val pushJson = pushRes.second
            pushJson?.optJSONObject("appliedScopes")?.let { applied ->
                val keys = applied.keys()
                while (keys.hasNext()) {
                    val key = keys.next()
                    val ver = applied.optJSONObject(key)?.optInt("version", 0) ?: 0
                    scopeVersions[key] = ver
                }
            }

            if (pushRes.first == 409 && pushJson != null) {
                val conflicts = pushJson.optJSONArray("conflicts") ?: JSONArray()
                for (i in 0 until conflicts.length()) {
                    val c = conflicts.optJSONObject(i) ?: continue
                    val scope = c.optString("scope")
                    scopeVersions[scope] = c.optInt("currentVersion", 0)
                    val curPayload = c.optJSONObject("currentPayload")
                    when (scope) {
                        "bookmarks" -> {
                            val parsed = parseBookmarksPayload(curPayload)
                            remoteFolders = parsed.folders
                            remoteItems = parsed.items
                            remoteTombstones = parsed.tombstones
                        }
                        "settings" -> {
                            if (curPayload != null) cachedRemoteSettingsJson = curPayload
                            mergedSettings = applySettingsFromRemote(mergedSettings, curPayload)
                        }
                        "site_controls" -> {
                            val arr = curPayload?.optJSONArray("controls")
                            if (arr != null) cachedRemoteSiteControlsArray = arr
                            mergedAllowedHosts = mergeAllowedHosts(mergedAllowedHosts, arr)
                        }
                    }
                }
                continue
            }

            if (pushRes.first != 200) {
                saveScopeVersions()
                return SyncRunOutcome(
                    ok = false,
                    errorMessage = pushJson?.optString("error").orEmpty().ifEmpty { "推送同步失败 (HTTP ${pushRes.first})" }
                )
            }

            saveScopeVersions()
            lastSyncAt = nowMs
            val pro = fetchProEntitlement()
            return SyncRunOutcome(
                ok = true,
                folders = mergedBm.folders,
                items = mergedBm.items,
                tombstones = mergedBm.tombstones,
                settings = mergedSettings,
                allowedHosts = mergedAllowedHosts,
                remoteDeviceTabs = remoteDeviceTabs,
                pro = pro,
                lastSyncAt = nowMs
            )
        }
        return SyncRunOutcome(ok = false, errorMessage = "同步冲突过多，请稍后重试")
    }

    private fun performAuth(path: String, body: JSONObject): AuthActionResult {
        val res = requestJson(path, "POST", body)
        val payload = res.second
        if (res.first !in 200..299 || payload == null) {
            return AuthActionResult(
                ok = false,
                errorMessage = payload?.optString("error").orEmpty().ifEmpty { "认证失败，请重试" }
            )
        }
        val receivedToken = payload.optString("token")
        val userObj = payload.optJSONObject("user") ?: return AuthActionResult(ok = false, errorMessage = "响应缺少用户信息")
        val user = parseUser(userObj)
        val identities = parseIdentities(payload.optJSONArray("identities"))
        token = receivedToken
        saveUser(user, identities)
        runCatching {
            requestJson(
                "/api/pro/bind",
                "POST",
                JSONObject().put("platform", "android").put("installId", installId),
                receivedToken
            )
        }
        val pro = fetchProEntitlement()
        return AuthActionResult(ok = true, user = user, identities = identities, pro = pro)
    }

    private fun requestJson(
        path: String,
        method: String,
        body: JSONObject?,
        bearerToken: String? = null
    ): Pair<Int, JSONObject?> {
        val bases = listOf(PRIMARY_AUTH_BASE_URL, FALLBACK_AUTH_BASE_URL)
        var lastError: Exception? = null
        for (base in bases) {
            var conn: HttpURLConnection? = null
            try {
                val url = URL("$base$path")
                conn = (url.openConnection() as HttpURLConnection).apply {
                    requestMethod = method
                    connectTimeout = 6000
                    readTimeout = 15000
                    setRequestProperty("Content-Type", "application/json")
                    if (!bearerToken.isNullOrEmpty()) {
                        setRequestProperty("Authorization", "Bearer $bearerToken")
                    }
                    if (body != null) {
                        doOutput = true
                        OutputStreamWriter(outputStream, Charsets.UTF_8).use { writer ->
                            writer.write(body.toString())
                        }
                    }
                }
                val code = conn.responseCode
                val stream = if (code >= 400) conn.errorStream else conn.inputStream
                val rawText = if (stream != null) {
                    BufferedReader(InputStreamReader(stream, Charsets.UTF_8)).use { it.readText() }
                } else {
                    ""
                }
                val parsed = if (rawText.isNotBlank()) runCatching { JSONObject(rawText) }.getOrNull() else null
                return code to parsed
            } catch (ex: Exception) {
                lastError = ex
            } finally {
                conn?.disconnect()
            }
        }
        return -1 to JSONObject().put("error", lastError?.message ?: "网络不可用")
    }

    private fun parseUser(obj: JSONObject): AccountUserProfile {
        val email = obj.optString("email")
        return AccountUserProfile(
            id = obj.optString("id"),
            email = email,
            displayName = obj.optString("displayName").ifEmpty { email },
            avatarUrl = obj.optString("avatarUrl"),
            createdAt = SyncMergePolicy.normalizeTimestampDoubleMs(obj.optDouble("createdAt", 0.0), 0L)
        )
    }

    private fun saveUser(user: AccountUserProfile, identities: List<LinkedIdentityItem>) {
        val userJson = JSONObject()
            .put("id", user.id)
            .put("email", user.email)
            .put("displayName", user.displayName)
            .put("avatarUrl", user.avatarUrl)
            .put("createdAt", user.createdAt)
        val idsJson = JSONArray()
        identities.forEach { id ->
            idsJson.put(
                JSONObject()
                    .put("provider", id.provider)
                    .put("email", id.email)
                    .put("emailVerified", id.emailVerified)
            )
        }
        prefs.edit()
            .putString(KEY_PROFILE, userJson.toString())
            .putString(KEY_IDENTITIES, idsJson.toString())
            .apply()
    }

    private fun parseIdentities(arr: JSONArray?): List<LinkedIdentityItem> {
        if (arr == null) return emptyList()
        return buildList {
            for (i in 0 until arr.length()) {
                val obj = arr.optJSONObject(i) ?: continue
                val provider = obj.optString("provider")
                if (provider.isEmpty()) continue
                add(
                    LinkedIdentityItem(
                        provider = provider,
                        email = obj.optString("email"),
                        emailVerified = obj.optBoolean("emailVerified", false)
                    )
                )
            }
        }
    }

    private fun parsePro(obj: JSONObject): ProEntitlementState {
        return ProEntitlementState(
            active = obj.optBoolean("active", false),
            scope = obj.optString("scope", "pro"),
            plan = obj.optString("plan"),
            productId = obj.optString("productId"),
            expiresAt = SyncMergePolicy.normalizeTimestampDoubleMs(obj.optDouble("expiresAt", 0.0), 0L),
            source = obj.optString("source"),
            verifiedAt = SyncMergePolicy.normalizeTimestampDoubleMs(obj.optDouble("verifiedAt", 0.0), 0L)
        )
    }

    private fun encodePro(state: ProEntitlementState): JSONObject {
        return JSONObject()
            .put("active", state.active)
            .put("scope", state.scope)
            .put("plan", state.plan)
            .put("productId", state.productId)
            .put("expiresAt", state.expiresAt)
            .put("source", state.source)
            .put("verifiedAt", state.verifiedAt)
    }

    private fun parseBookmarksPayload(payload: JSONObject?): BookmarkSyncMergeResult {
        if (payload == null) return BookmarkSyncMergeResult(emptyList(), emptyList(), emptyList())
        val now = System.currentTimeMillis()
        val folders = buildList {
            val arr = payload.optJSONArray("folders") ?: JSONArray()
            for (i in 0 until arr.length()) {
                val obj = arr.optJSONObject(i) ?: continue
                val id = obj.optString("id")
                if (id.isEmpty()) continue
                val created = SyncMergePolicy.normalizeTimestampDoubleMs(obj.optDouble("createdAt", now.toDouble()), now)
                add(
                    BookmarkFolder(
                        id = id,
                        name = obj.optString("name").ifEmpty { "文件夹" },
                        iconName = obj.optString("iconName").ifEmpty { "folder.fill" },
                        createdAt = created,
                        updatedAt = SyncMergePolicy.normalizeTimestampDoubleMs(obj.optDouble("updatedAt", created.toDouble()), created),
                        sortOrder = obj.optInt("sortOrder", 0),
                        isPinnedToStartPage = obj.optBoolean("isPinnedToStartPage", true)
                    )
                )
            }
        }
        val items = buildList {
            val arr = payload.optJSONArray("items") ?: JSONArray()
            for (i in 0 until arr.length()) {
                val obj = arr.optJSONObject(i) ?: continue
                val url = obj.optString("url")
                if (url.isEmpty()) continue
                val created = SyncMergePolicy.normalizeTimestampDoubleMs(obj.optDouble("createdAt", now.toDouble()), now)
                val tagsJson = obj.optJSONArray("tags") ?: JSONArray()
                val tags = buildList {
                    for (t in 0 until tagsJson.length()) {
                        val s = tagsJson.optString(t).trim()
                        if (s.isNotEmpty()) add(s)
                    }
                }
                add(
                    SavedItem(
                        id = obj.optString("id").ifEmpty { "saved-$created" },
                        title = obj.optString("title").ifEmpty { url },
                        url = url,
                        createdAt = created,
                        updatedAt = SyncMergePolicy.normalizeTimestampDoubleMs(obj.optDouble("updatedAt", created.toDouble()), created),
                        folderId = obj.optString("folderId").takeIf { it.isNotBlank() && it != "null" },
                        isRead = obj.optBoolean("isRead", false),
                        tags = tags,
                        isPinnedToStartPage = if (obj.has("isPinnedToStartPage")) obj.optBoolean("isPinnedToStartPage", true) else true,
                        sortOrder = obj.optInt("sortOrder", 0)
                    )
                )
            }
        }
        val tombstones = buildList {
            val arr = payload.optJSONArray("tombstones") ?: JSONArray()
            for (i in 0 until arr.length()) {
                val obj = arr.optJSONObject(i) ?: continue
                val id = obj.optString("id")
                val url = obj.optString("url")
                if (id.isEmpty() && url.isEmpty()) continue
                add(
                    BookmarkTombstone(
                        id = id,
                        url = url,
                        isFolder = obj.optBoolean("isFolder", false),
                        deletedAt = SyncMergePolicy.normalizeTimestampDoubleMs(obj.optDouble("deletedAt", now.toDouble()), now)
                    )
                )
            }
        }
        return BookmarkSyncMergeResult(folders = folders, items = items, tombstones = tombstones)
    }

    private fun encodeBookmarksPayload(
        folders: List<BookmarkFolder>,
        items: List<SavedItem>,
        tombstones: List<BookmarkTombstone>,
        nowMs: Long
    ): JSONObject {
        val fArr = JSONArray()
        folders.forEach { f ->
            fArr.put(
                JSONObject()
                    .put("id", f.id)
                    .put("name", f.name)
                    .put("iconName", f.iconName)
                    .put("createdAt", f.createdAt)
                    .put("updatedAt", f.updatedAt)
                    .put("sortOrder", f.sortOrder)
                    .put("isPinnedToStartPage", f.isPinnedToStartPage)
            )
        }
        val iArr = JSONArray()
        items.forEach { item ->
            val tagsArr = JSONArray()
            item.tags.forEach { tagsArr.put(it) }
            iArr.put(
                JSONObject()
                    .put("id", item.id)
                    .put("title", item.title)
                    .put("url", item.url)
                    .put("folderId", item.folderId.orEmpty())
                    .put("createdAt", item.createdAt)
                    .put("updatedAt", item.updatedAt)
                    .put("isRead", item.isRead)
                    .put("tags", tagsArr)
                    .put("isPinnedToStartPage", item.isPinnedToStartPage)
                    .put("sortOrder", item.sortOrder)
            )
        }
        val tArr = JSONArray()
        tombstones.forEach { tb ->
            tArr.put(
                JSONObject()
                    .put("id", tb.id)
                    .put("url", tb.url)
                    .put("isFolder", tb.isFolder)
                    .put("deletedAt", tb.deletedAt)
            )
        }
        return JSONObject()
            .put("version", 3)
            .put("folders", fArr)
            .put("items", iArr)
            .put("tombstones", tArr)
            .put("updatedAt", nowMs)
    }

    private fun applySettingsFromRemote(current: BrowserSettings, remote: JSONObject?): BrowserSettings {
        if (remote == null) return current
        val nextEngine = if (remote.has("searchEngine")) {
            val rawEngine = remote.opt("searchEngine")
            when (rawEngine) {
                is Number -> SearchEngine.fromRaw(rawEngine.toInt())
                is String -> when (rawEngine.lowercase()) {
                    "baidu" -> SearchEngine.Baidu
                    "google" -> SearchEngine.Google
                    "duckduckgo" -> SearchEngine.DuckDuckGo
                    else -> SearchEngine.Bing
                }
                else -> current.searchEngine
            }
        } else current.searchEngine
        return current.copy(
            searchEngine = nextEngine,
            blockAds = if (remote.has("blockAds")) remote.optBoolean("blockAds", current.blockAds) else current.blockAds,
            searchSuggestionsEnabled = if (remote.has("searchSuggestionsEnabled")) {
                remote.optBoolean("searchSuggestionsEnabled", current.searchSuggestionsEnabled)
            } else {
                current.searchSuggestionsEnabled
            }
        )
    }

    private fun encodeSettingsPayload(settings: BrowserSettings, nowMs: Long): JSONObject {
        val base = cachedRemoteSettingsJson?.let { JSONObject(it.toString()) } ?: JSONObject()
        base.put("blockAds", settings.blockAds)
        base.put("searchEngine", settings.searchEngine.raw)
        base.put("searchSuggestionsEnabled", settings.searchSuggestionsEnabled)
        base.put("updatedAt", nowMs)
        return base
    }

    private fun mergeAllowedHosts(localHosts: List<String>, remoteControls: JSONArray?): List<String> {
        val hosts = linkedSetOf<String>()
        localHosts.forEach { h ->
            val clean = h.trim().lowercase()
            if (clean.isNotEmpty()) hosts.add(clean)
        }
        if (remoteControls != null) {
            for (i in 0 until remoteControls.length()) {
                val obj = remoteControls.optJSONObject(i) ?: continue
                val host = obj.optString("host").trim().lowercase()
                if (host.isEmpty()) continue
                if (obj.optInt("networkBlocking", 0) == 2 || obj.optBoolean("allowAds", false)) {
                    hosts.add(host)
                }
            }
        }
        return hosts.toList()
    }

    private fun encodeSiteControlsPayload(allowedHosts: List<String>, nowMs: Long): JSONObject {
        val byHost = linkedMapOf<String, JSONObject>()
        cachedRemoteSiteControlsArray?.let { arr ->
            for (i in 0 until arr.length()) {
                val obj = arr.optJSONObject(i) ?: continue
                val host = obj.optString("host").trim().lowercase()
                if (host.isNotEmpty()) byHost[host] = JSONObject(obj.toString())
            }
        }
        allowedHosts.forEach { raw ->
            val host = raw.trim().lowercase()
            if (host.isEmpty()) return@forEach
            val existing = byHost[host] ?: JSONObject()
                .put("host", host)
                .put("trackerBlocking", 0)
                .put("cosmeticCleanup", 0)
                .put("autoReader", 0)
                .put("darkMode", 0)
                .put("desktopUserAgent", 0)
            existing.put("networkBlocking", 2).put("updatedAt", nowMs)
            byHost[host] = existing
        }
        val controls = JSONArray()
        byHost.values.forEach { controls.put(it) }
        return JSONObject()
            .put("controls", controls)
            .put("tombstones", JSONArray())
            .put("updatedAt", nowMs)
    }

    private fun parseDeviceTabs(arr: JSONArray?): List<RemoteDeviceTabGroup> {
        if (arr == null) return emptyList()
        return buildList {
            for (i in 0 until arr.length()) {
                val group = arr.optJSONObject(i) ?: continue
                val devId = group.optString("deviceId")
                if (devId.isEmpty() || devId == deviceId) continue
                val tabsJson = group.optJSONArray("tabs") ?: JSONArray()
                val tabs = buildList {
                    for (j in 0 until tabsJson.length()) {
                        val t = tabsJson.optJSONObject(j) ?: continue
                        val url = t.optString("url")
                        if (url.isEmpty()) continue
                        add(
                            RemoteDeviceTabEntry(
                                id = t.optString("id").ifEmpty { url },
                                title = t.optString("title").ifEmpty { url },
                                url = url,
                                lastVisitedAt = SyncMergePolicy.normalizeTimestampDoubleMs(t.optDouble("lastVisitedAt", 0.0), 0L)
                            )
                        )
                    }
                }
                if (tabs.isEmpty()) continue
                add(
                    RemoteDeviceTabGroup(
                        deviceId = devId,
                        deviceName = group.optString("deviceName").ifEmpty { group.optString("platform").ifEmpty { "其他设备" } },
                        platform = group.optString("platform"),
                        updatedAt = SyncMergePolicy.normalizeTimestampDoubleMs(group.optDouble("updatedAt", 0.0), 0L),
                        tabs = tabs
                    )
                )
            }
        }
    }

    private fun encodeDeviceTabs(tabs: List<RemoteDeviceTabEntry>): JSONArray {
        val arr = JSONArray()
        tabs.forEach { tab ->
            arr.put(
                JSONObject()
                    .put("id", tab.id)
                    .put("title", tab.title)
                    .put("url", tab.url)
                    .put("lastVisitedAt", tab.lastVisitedAt)
            )
        }
        return arr
    }

    private fun clearLocalSession() {
        scopeVersions.clear()
        cachedRemoteSettingsJson = null
        cachedRemoteSiteControlsArray = null
        prefs.edit()
            .remove(KEY_TOKEN)
            .remove(KEY_PROFILE)
            .remove(KEY_IDENTITIES)
            .remove(KEY_PRO)
            .remove(KEY_SCOPE_VERSIONS)
            .apply()
    }

    private fun restoreScopeVersions() {
        val raw = prefs.getString(KEY_SCOPE_VERSIONS, "").orEmpty()
        if (raw.isEmpty()) return
        runCatching {
            val obj = JSONObject(raw)
            val keys = obj.keys()
            while (keys.hasNext()) {
                val key = keys.next()
                scopeVersions[key] = obj.optInt(key, 0)
            }
        }
    }

    private fun saveScopeVersions() {
        val obj = JSONObject()
        scopeVersions.forEach { (k, v) -> obj.put(k, v) }
        prefs.edit().putString(KEY_SCOPE_VERSIONS, obj.toString()).apply()
    }

    companion object {
        private const val PREFS_NAME = "zhuo_account"
        private const val PRIMARY_AUTH_BASE_URL = "https://auth.zhuobrowser.youdroid.top"
        private const val FALLBACK_AUTH_BASE_URL = "https://zhuobrowser-auth-service.memoryphoto.workers.dev"
        private const val OAUTH_CALLBACK_URI = "zhuobrowser-auth://oauth/callback"

        private const val KEY_TOKEN = "token"
        private const val KEY_PROFILE = "profile"
        private const val KEY_IDENTITIES = "identities"
        private const val KEY_PRO = "pro_entitlement"
        private const val KEY_DEVICE_ID = "device_id"
        private const val KEY_INSTALL_ID = "install_id"
        private const val KEY_LAST_SYNC_AT = "last_sync_at"
        private const val KEY_SCOPE_VERSIONS = "scope_versions"
    }
}
