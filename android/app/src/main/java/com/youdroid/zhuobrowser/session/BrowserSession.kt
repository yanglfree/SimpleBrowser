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
    val showsLibrary: Boolean = false,
    val libraryTab: LibraryTab = LibraryTab.Bookmarks,
    val settings: BrowserSettings = BrowserSettings(),
    val allowedHosts: List<String> = emptyList(),
    val history: List<HistoryEntry> = emptyList(),
    val savedItems: List<SavedItem> = emptyList(),
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

    fun setShowsLibrary(visible: Boolean) {
        _state.update { it.copy(showsLibrary = visible) }
    }

    fun openLibrary(tab: LibraryTab) {
        _state.update {
            it.copy(
                libraryTab = tab,
                showsLibrary = true,
                showsSettings = false,
                showsOverview = false
            )
        }
    }

    fun setLibraryTab(tab: LibraryTab) {
        _state.update { it.copy(libraryTab = tab) }
    }

    fun setSearchEngine(engine: SearchEngine) {
        _state.update { it.copy(settings = it.settings.copy(searchEngine = engine)) }
        persistSettings()
    }

    fun setBlockAds(enabled: Boolean) {
        _state.update { it.copy(settings = it.settings.copy(blockAds = enabled)) }
        persistSettings()
    }

    fun setSearchSuggestionsEnabled(enabled: Boolean) {
        _state.update { it.copy(settings = it.settings.copy(searchSuggestionsEnabled = enabled)) }
        persistSettings()
    }

    fun recordVisit(tabId: String) {
        val tab = _state.value.tabs.firstOrNull { it.id == tabId } ?: return
        if (!SessionPolicy.shouldRecordHistory(tab.isPrivate) || UrlPolicy.isHomeUrl(tab.url)) return
        val title = tab.title.ifEmpty { UrlPolicy.displayHost(tab.url) }
        _state.update { current ->
            current.copy(
                history = LibraryPolicy.recordHistory(
                    current.history,
                    HistoryEntry(
                        id = "history-${System.currentTimeMillis()}",
                        title = title,
                        url = tab.url,
                        visitedAt = System.currentTimeMillis(),
                        visitCount = 0
                    )
                )
            )
        }
        persistLibrary()
    }

    fun isCurrentPageSaved(): Boolean {
        val tab = _state.value.activeTab ?: return false
        return LibraryPolicy.isSaved(_state.value.savedItems, tab.url)
    }

    fun toggleSaved() {
        val tab = _state.value.activeTab ?: return
        if (UrlPolicy.isHomeUrl(tab.url)) return
        val existing = _state.value.savedItems.firstOrNull { it.url == tab.url }
        if (existing != null) {
            _state.update { it.copy(savedItems = LibraryPolicy.removeSavedItem(it.savedItems, existing.id)) }
            flash("已取消书签")
        } else {
            val now = System.currentTimeMillis()
            val title = tab.title.ifEmpty { UrlPolicy.displayHost(tab.url) }
            _state.update { current ->
                current.copy(
                    savedItems = LibraryPolicy.addSavedItem(
                        current.savedItems,
                        SavedItem(
                            id = "saved-$now",
                            title = title,
                            url = tab.url,
                            createdAt = now,
                            updatedAt = now
                        )
                    )
                )
            }
            flash("已加入书签")
        }
        persistLibrary()
    }

    fun removeSavedItem(id: String) {
        _state.update { it.copy(savedItems = LibraryPolicy.removeSavedItem(it.savedItems, id)) }
        persistLibrary()
    }

    fun removeHistory(id: String) {
        _state.update { current -> current.copy(history = current.history.filter { it.id != id }) }
        persistLibrary()
    }

    fun suggestions(query: String): List<AddressSuggestion> {
        val current = _state.value
        val trimmed = query.trim()
        val search = if (UrlPolicy.looksLikeUrl(trimmed)) {
            ""
        } else {
            UrlPolicy.searchUrl(trimmed, current.settings.searchEngine)
        }
        return LibraryPolicy.suggestions(
            query = query,
            history = current.history,
            savedItems = current.savedItems,
            searchSuggestionsEnabled = current.settings.searchSuggestionsEnabled && !UrlPolicy.looksLikeUrl(trimmed),
            searchUrl = search
        )
    }

    fun sharePayload(): Pair<String, String>? {
        val tab = _state.value.activeTab ?: return null
        if (UrlPolicy.isHomeUrl(tab.url)) return null
        val text = if (tab.title.isEmpty()) tab.url else "${tab.title}\n${tab.url}"
        return tab.title to text
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
        persistLibrary()
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
            .putBoolean("searchSuggestionsEnabled", settings.searchSuggestionsEnabled)
            .apply()
    }

    private fun persistAllowList() {
        val array = JSONArray()
        _state.value.allowedHosts.forEach { array.put(it) }
        prefs.edit().putString("allowedHosts", array.toString()).apply()
    }

    private fun persistLibrary() {
        val history = JSONArray()
        _state.value.history.forEach { entry ->
            history.put(
                JSONObject()
                    .put("id", entry.id)
                    .put("title", entry.title)
                    .put("url", entry.url)
                    .put("visitedAt", entry.visitedAt)
                    .put("visitCount", entry.visitCount)
            )
        }
        val saved = JSONArray()
        _state.value.savedItems.forEach { item ->
            saved.put(
                JSONObject()
                    .put("id", item.id)
                    .put("title", item.title)
                    .put("url", item.url)
                    .put("createdAt", item.createdAt)
                    .put("updatedAt", item.updatedAt)
            )
        }
        prefs.edit()
            .putString("history", history.toString())
            .putString("savedItems", saved.toString())
            .apply()
    }

    private fun restore(): BrowserUiState {
        val settings = BrowserSettings(
            searchEngine = SearchEngine.fromRaw(prefs.getInt("searchEngine", 0)),
            blockAds = prefs.getBoolean("blockAds", true),
            searchSuggestionsEnabled = prefs.getBoolean("searchSuggestionsEnabled", true)
        )
        val allowed = runCatching {
            val array = JSONArray(prefs.getString("allowedHosts", "[]"))
            buildList {
                for (i in 0 until array.length()) add(array.getString(i))
            }
        }.getOrDefault(emptyList())
        val history = runCatching {
            val array = JSONArray(prefs.getString("history", "[]"))
            buildList {
                for (i in 0 until array.length()) {
                    val obj = array.getJSONObject(i)
                    add(
                        HistoryEntry(
                            id = obj.getString("id"),
                            title = obj.optString("title"),
                            url = obj.getString("url"),
                            visitedAt = obj.optLong("visitedAt"),
                            visitCount = obj.optInt("visitCount")
                        )
                    )
                }
            }
        }.getOrDefault(emptyList())
        val savedItems = runCatching {
            val array = JSONArray(prefs.getString("savedItems", "[]"))
            buildList {
                for (i in 0 until array.length()) {
                    val obj = array.getJSONObject(i)
                    add(
                        SavedItem(
                            id = obj.getString("id"),
                            title = obj.optString("title"),
                            url = obj.getString("url"),
                            createdAt = obj.optLong("createdAt"),
                            updatedAt = obj.optLong("updatedAt")
                        )
                    )
                }
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
            allowedHosts = allowed,
            history = history,
            savedItems = savedItems
        )
    }
}
