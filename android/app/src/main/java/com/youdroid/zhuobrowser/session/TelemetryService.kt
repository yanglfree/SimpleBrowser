package com.youdroid.zhuobrowser.session

import android.content.Context
import android.content.SharedPreferences
import android.os.Build
import com.youdroid.zhuobrowser.BuildConfig
import top.youdroid.shuyishu.ConsentState
import top.youdroid.shuyishu.ShuYiShuAnalytics
import top.youdroid.shuyishu.ShuYiShuStorage
import java.util.UUID
import java.util.concurrent.Executors

private class SharedPreferencesShuYiShuStorage(
    private val prefs: SharedPreferences
) : ShuYiShuStorage {
    override fun readString(key: String): String? = prefs.getString(key, null)

    override fun writeString(key: String, value: String) {
        prefs.edit().putString(key, value).apply()
    }
}

object TelemetryService {
    const val DEFAULT_BASE_URL = "https://trending.youdroid.top"
    const val PRODUCT_ID = "product-zhuobrowser"
    private const val PREF_NAME = "zhuo_shuyishu"
    private const val KEY_INSTALL_ID = "shuyishu_installation_id"
    private const val KEY_ENABLED = "shuyishu_enabled"
    private val ALLOWED_ACTION_REGEX = Regex("^[A-Za-z0-9_-]{1,40}$")

    private val flushExecutor = Executors.newSingleThreadExecutor()

    @Volatile
    private var analytics: ShuYiShuAnalytics? = null

    @Volatile
    private var enabled: Boolean = true

    fun defaultAppKey(): String =
        if (BuildConfig.DEBUG) "dev_zhuobrowser_android" else "prod_zhuobrowser_android"

    fun allowsWrite(isPrivate: Boolean): Boolean = enabled && !isPrivate

    fun initialize(context: Context) {
        if (analytics != null) return
        synchronized(this) {
            if (analytics != null) return
            val appContext = context.applicationContext
            val prefs = appContext.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
            enabled = prefs.getBoolean(KEY_ENABLED, true)

            val existingId = prefs.getString(KEY_INSTALL_ID, null)?.trim().orEmpty()
            val installationId = if (existingId.isNotEmpty()) {
                existingId
            } else {
                UUID.randomUUID().toString().lowercase().also { created ->
                    prefs.edit().putString(KEY_INSTALL_ID, created).apply()
                }
            }

            val buildMode = if (BuildConfig.DEBUG) "debug" else "release"
            analytics = ShuYiShuAnalytics(
                baseUrl = DEFAULT_BASE_URL,
                appKey = defaultAppKey(),
                productId = PRODUCT_ID,
                platform = "android",
                appVersion = BuildConfig.VERSION_NAME,
                buildNumber = BuildConfig.VERSION_CODE.toString(),
                installationId = installationId,
                device = mapOf(
                    "kind" to "phone",
                    "os" to "Android",
                    "os_version" to Build.VERSION.RELEASE
                ),
                app = mapOf(
                    "build_mode" to buildMode
                ),
                debug = mapOf(
                    "build_mode" to buildMode
                ),
                storage = SharedPreferencesShuYiShuStorage(prefs),
                consentState = if (enabled) ConsentState.GRANTED else ConsentState.DENIED
            )
        }
    }

    fun setEnabled(enabled: Boolean) {
        this.enabled = enabled
        analytics?.setConsent(if (enabled) ConsentState.GRANTED else ConsentState.DENIED)
    }

    fun sanitizedAction(raw: String): String? {
        val trimmed = raw.trim()
        if (trimmed.isEmpty()) return null
        val bounded = if (trimmed.length > 40) trimmed.substring(0, 40) else trimmed
        return if (ALLOWED_ACTION_REGEX.matches(bounded)) bounded else null
    }

    fun handleAppForegrounded(isPrivate: Boolean = false) {
        if (!allowsWrite(isPrivate)) return
        val client = analytics ?: return
        client.setConsent(ConsentState.GRANTED)
        client.handleAppForegrounded()
    }

    fun handleAppBackgrounded(isPrivate: Boolean = false) {
        if (!allowsWrite(isPrivate)) return
        val client = analytics ?: return
        client.handleAppBackgrounded()
        flushExecutor.execute {
            runCatching { client.flush() }
        }
    }

    fun recordActionUsage(action: String, isPrivate: Boolean) {
        if (!allowsWrite(isPrivate)) return
        val clean = sanitizedAction(action) ?: return
        val client = analytics ?: return
        client.setConsent(ConsentState.GRANTED)
        client.track("action_usage", mapOf("action" to clean))
    }
}
