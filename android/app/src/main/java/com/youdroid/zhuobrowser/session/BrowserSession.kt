package com.youdroid.zhuobrowser.session

import android.app.Application
import android.content.Context
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.youdroid.zhuobrowser.policy.SearchEngine
import com.youdroid.zhuobrowser.policy.UrlPolicy
import com.youdroid.zhuobrowser.web.NetworkBlocker
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject

data class BrowserUiState(
    val tabs: List<BrowserTab> = listOf(BrowserTab.home(false)),
    val activeTabId: String = "",
    val showsOverview: Boolean = false,
    val showsSettings: Boolean = false,
    val settings: BrowserSettings = BrowserSettings(),
    val allowedHosts: List<String> = emptyList(),
    val notice: String? = null
) {
    val activeTab: BrowserTab?
        get() = tabs.firstOrNull { it.id == activeTabId } ?: tabs.firstOrNull()
}

class BrowserSession(application: Application) : AndroidViewModel(application) {
    val blocker = NetworkBlocker()
    private val prefs = application.getSharedPreferences("zhuo", Context.MODE_PRIVATE)
    private val _state = MutableStateFlow(BrowserUiState())
    val state: StateFlow<BrowserUiState> = _state

    init {
        val restored = restore()
        _state.value = restored.copy(
            activeTabId = restored.activeTabId.ifEmpty { restored.tabs.first().id }
        )
        viewModelScope.launch(Dispatchers.IO) {
            runCatching { blocker.load(getApplication<Application>().assets) }
        }
    }

    fun adsBlockEnabled(url: String): Boolean {
        val current = _state.value
        return AllowListPolicy.adsBlockEnabled(url, current.allowedHosts, current.settings.blockAds)
    }

    fun openInActiveTab(raw: String) {
        val address = UrlPolicy.normalizeAddress(raw, _state.value.settings.searchEngine)
        updateActive { it.copy(url = address, lastVisitedAt = System.currentTimeMillis()) }
        persist()
    }

    fun createTab(isPrivate: Boolean) {
        _state.update { current ->
            if (current.tabs.size >= SessionPolicy.MAX_TAB_COUNT) return@update current
            val tab = BrowserTab.home(isPrivate)
            current.copy(tabs = current.tabs + tab, activeTabId = tab.id, showsOverview = false)
        }
        persist()
    }

    fun selectTab(id: String) {
        _state.update { current ->
            if (current.tabs.none { it.id == id }) current
            else current.copy(activeTabId = id, showsOverview = false)
        }
        persist()
    }

    fun closeTab(id: String) {
        _state.update { current ->
            val remaining = current.tabs.filter { it.id != id }
            val tabs = remaining.ifEmpty { listOf(BrowserTab.home(false)) }
            val active = if (current.activeTabId == id) tabs.first().id else current.activeTabId
            current.copy(tabs = tabs, activeTabId = active)
        }
        persist()
    }

    fun closeAll() {
        val home = BrowserTab.home(false)
        _state.update { it.copy(tabs = listOf(home), activeTabId = home.id, showsOverview = false) }
        persist()
    }

    fun toggleOverview() {
        _state.update { it.copy(showsOverview = !it.showsOverview) }
    }

    fun setShowsSettings(visible: Boolean) {
        _state.update { it.copy(showsSettings = visible) }
    }

    fun setSearchEngine(engine: SearchEngine) {
        _state.update { it.copy(settings = it.settings.copy(searchEngine = engine)) }
        persistSettings()
    }

    fun setBlockAds(enabled: Boolean) {
        _state.update { it.copy(settings = it.settings.copy(blockAds = enabled)) }
        persistSettings()
    }

    fun toggleCurrentHostAllowed() {
        val tab = _state.value.activeTab ?: return
        if (UrlPolicy.isHomeUrl(tab.url)) return
        val host = UrlPolicy.rawHost(tab.url)
        val allowed = !AllowListPolicy.isHostAllowed(_state.value.allowedHosts, host)
        _state.update {
            it.copy(allowedHosts = AllowListPolicy.setHostAllowed(it.allowedHosts, host, allowed))
        }
        persistAllowList()
    }

    fun updateTab(id: String, title: String? = null, url: String? = null, loading: Boolean? = null) {
        _state.update { current ->
            current.copy(
                tabs = current.tabs.map { tab ->
                    if (tab.id != id) tab
                    else tab.copy(
                        title = title ?: tab.title,
                        url = url ?: tab.url,
                        isLoading = loading ?: tab.isLoading,
                        lastVisitedAt = System.currentTimeMillis()
                    )
                }
            )
        }
    }

    fun goBackToHomeIfNeeded(id: String): Boolean {
        val tab = _state.value.tabs.firstOrNull { it.id == id } ?: return false
        if (UrlPolicy.isHomeUrl(tab.url)) return false
        updateTab(id, url = UrlPolicy.HOME_URL, title = if (tab.isPrivate) "无痕" else "新标签页", loading = false)
        persist()
        return true
    }

    fun liveTabIds(): List<String> {
        val current = _state.value
        return SessionPolicy.liveTabIds(current.tabs, current.activeTabId, SessionPolicy.LIVE_WEBVIEW_LIMIT)
    }

    fun flash(message: String) {
        _state.update { it.copy(notice = message) }
    }

    fun clearNotice() {
        _state.update { it.copy(notice = null) }
    }

    private fun updateActive(mutate: (BrowserTab) -> BrowserTab) {
        _state.update { current ->
            current.copy(
                tabs = current.tabs.map { tab ->
                    if (tab.id == current.activeTabId) mutate(tab) else tab
                }
            )
        }
    }

    private fun persist() {
        persistSettings()
        persistAllowList()
        val persistable = SessionPolicy.persistableTabs(_state.value.tabs)
        val active = if (persistable.any { it.id == _state.value.activeTabId }) {
            _state.value.activeTabId
        } else persistable.firstOrNull()?.id.orEmpty()
        val array = JSONArray()
        persistable.forEach { tab ->
            array.put(
                JSONObject()
                    .put("id", tab.id)
                    .put("url", tab.url)
                    .put("title", tab.title)
                    .put("lastVisitedAt", tab.lastVisitedAt)
            )
        }
        prefs.edit()
            .putString("tabs", array.toString())
            .putString("activeTabId", active)
            .apply()
    }

    private fun persistSettings() {
        val settings = _state.value.settings
        prefs.edit()
            .putInt("searchEngine", settings.searchEngine.raw)
            .putBoolean("blockAds", settings.blockAds)
            .apply()
    }

    private fun persistAllowList() {
        val array = JSONArray()
        _state.value.allowedHosts.forEach { array.put(it) }
        prefs.edit().putString("allowedHosts", array.toString()).apply()
    }

    private fun restore(): BrowserUiState {
        val settings = BrowserSettings(
            searchEngine = SearchEngine.fromRaw(prefs.getInt("searchEngine", 0)),
            blockAds = prefs.getBoolean("blockAds", true)
        )
        val allowed = runCatching {
            val array = JSONArray(prefs.getString("allowedHosts", "[]"))
            buildList {
                for (i in 0 until array.length()) add(array.getString(i))
            }
        }.getOrDefault(emptyList())
        val tabs = runCatching {
            val array = JSONArray(prefs.getString("tabs", "[]"))
            buildList {
                for (i in 0 until array.length()) {
                    val obj = array.getJSONObject(i)
                    add(
                        BrowserTab(
                            id = obj.getString("id"),
                            url = obj.getString("url"),
                            title = obj.optString("title"),
                            lastVisitedAt = obj.optLong("lastVisitedAt")
                        )
                    )
                }
            }
        }.getOrDefault(emptyList())
        val resolved = tabs.ifEmpty { listOf(BrowserTab.home(false)) }
        return BrowserUiState(
            tabs = resolved,
            activeTabId = prefs.getString("activeTabId", resolved.first().id) ?: resolved.first().id,
            settings = settings,
            allowedHosts = allowed
        )
    }
}
