package com.youdroid.zhuobrowser.session

import android.Manifest
import android.app.Application
import android.content.Context
import android.content.pm.PackageManager
import android.webkit.WebView
import androidx.core.content.ContextCompat
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.youdroid.zhuobrowser.policy.SearchEngine
import com.youdroid.zhuobrowser.policy.UrlPolicy
import com.youdroid.zhuobrowser.web.NetworkBlocker
import com.youdroid.zhuobrowser.web.ReaderScripts
import com.youdroid.zhuobrowser.web.WebKernel
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
    val readerSettings: ReaderSettings = ReaderSettings(),
    val showsFind: Boolean = false,
    val findQuery: String = "",
    val findCurrent: Int = 0,
    val findTotal: Int = 0,
    val showsDownloads: Boolean = false,
    val sitePermissions: List<SitePermission> = emptyList(),
    val permissionPrompt: PermissionPrompt? = null,
    val osPermissionsToRequest: List<String> = emptyList(),
    val notice: String? = null
) {
    val activeTab: BrowserTab?
        get() = tabs.firstOrNull { it.id == activeTabId } ?: tabs.firstOrNull()
}

class BrowserSession(application: Application) : AndroidViewModel(application) {
    val blocker = NetworkBlocker()
    val downloads = DownloadStore(application)
    private val prefs = application.getSharedPreferences("zhuo", Context.MODE_PRIVATE)
    private val webViews = mutableMapOf<String, WebView>()
    private var permissionReply: ((Boolean) -> Unit)? = null
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

    fun attachWebView(id: String, webView: WebView) {
        webViews[id] = webView
    }

    fun detachWebView(id: String, webView: WebView) {
        if (webViews[id] !== webView) return
        denyPermissionIfPending()
        webViews.remove(id)
        webView.stopLoading()
        webView.destroy()
    }

    fun openInActiveTab(raw: String) {
        val address = UrlPolicy.normalizeAddress(raw, _state.value.settings.searchEngine)
        updateActive { tab ->
            val resolved = if (tab.isDesktop) UrlPolicy.desktopUrl(address) else address
            tab.copy(url = resolved, isReader = false, lastVisitedAt = System.currentTimeMillis())
        }
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
        destroyWebView(id)
        _state.update { current ->
            val remaining = current.tabs.filter { it.id != id }
            val tabs = remaining.ifEmpty { listOf(BrowserTab.home(false)) }
            val active = if (current.activeTabId == id) tabs.first().id else current.activeTabId
            current.copy(tabs = tabs, activeTabId = active)
        }
        persist()
    }

    fun closeAll() {
        webViews.keys.toList().forEach { destroyWebView(it) }
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

    fun setShowsDownloads(visible: Boolean) {
        _state.update { it.copy(showsDownloads = visible) }
    }

    fun openDownloads() {
        _state.update {
            it.copy(
                showsDownloads = true,
                showsSettings = false,
                showsOverview = false,
                showsLibrary = false
            )
        }
    }

    fun requestSitePermission(
        origin: String,
        kinds: List<SitePermissionKind>,
        persist: Boolean,
        completion: (Boolean) -> Unit
    ) {
        if (origin.isEmpty() || kinds.isEmpty()) {
            completion(false)
            return
        }
        if (permissionReply != null) {
            completion(false)
            return
        }
        val stored = if (persist) _state.value.sitePermissions.firstOrNull { it.origin == origin } else null
        when (SitePermissionPolicy.decision(stored, kinds)) {
            SitePermissionDecision.Allow -> deliverPermission(kinds, completion)
            SitePermissionDecision.Deny -> completion(false)
            SitePermissionDecision.Prompt -> {
                permissionReply = completion
                _state.update {
                    it.copy(permissionPrompt = PermissionPrompt(origin = origin, kinds = kinds, persist = persist))
                }
            }
        }
    }

    fun allowPermission() {
        completePermission(true)
    }

    fun denyPermission() {
        completePermission(false)
    }

    fun denyPermissionIfPending() {
        if (permissionReply != null) completePermission(false)
    }

    fun consumeOsPermissionRequest() {
        _state.update { it.copy(osPermissionsToRequest = emptyList()) }
    }

    fun onOsPermissionResult(grants: Map<String, Boolean>) {
        val cameraOk = grants[Manifest.permission.CAMERA] != false
        val micOk = grants[Manifest.permission.RECORD_AUDIO] != false
        val askedLocation = grants.containsKey(Manifest.permission.ACCESS_FINE_LOCATION) ||
            grants.containsKey(Manifest.permission.ACCESS_COARSE_LOCATION)
        val locationOk = if (!askedLocation) {
            true
        } else {
            grants[Manifest.permission.ACCESS_FINE_LOCATION] == true ||
                grants[Manifest.permission.ACCESS_COARSE_LOCATION] == true
        }
        val reply = permissionReply
        permissionReply = null
        _state.update { it.copy(osPermissionsToRequest = emptyList()) }
        reply?.invoke(cameraOk && micOk && locationOk)
    }

    fun removeSitePermission(origin: String) {
        _state.update { it.copy(sitePermissions = SitePermissionPolicy.remove(it.sitePermissions, origin)) }
        persistSitePermissions()
    }

    fun beginDownload(url: String, userAgent: String, contentDisposition: String, mimeType: String) {
        if (downloads.start(url, userAgent, contentDisposition, mimeType)) {
            flash("已开始下载")
        } else {
            flash("无法下载此文件")
        }
    }

    fun openLibrary(tab: LibraryTab) {
        _state.update {
            it.copy(
                libraryTab = tab,
                showsLibrary = true,
                showsSettings = false,
                showsOverview = false,
                showsDownloads = false
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

    fun toggleReader() {
        val tab = _state.value.activeTab ?: return
        if (UrlPolicy.isHomeUrl(tab.url)) return
        val webView = activeWebView() ?: return
        val assets = getApplication<Application>().assets
        if (tab.isReader) {
            webView.evaluateJavascript(ReaderScripts.exit(assets), null)
            updateTab(tab.id, isReader = false)
            persist()
            return
        }
        webView.evaluateJavascript(ReaderScripts.apply(assets, _state.value.readerSettings)) { raw ->
            if (ReaderScripts.isReaderStatus(raw)) {
                updateTab(tab.id, isReader = true)
                persist()
            } else {
                flash("无法提取正文")
            }
        }
    }

    fun refreshReader() {
        val tab = _state.value.activeTab ?: return
        if (!tab.isReader) return
        persistReaderSettings()
        val webView = activeWebView() ?: return
        webView.evaluateJavascript(
            ReaderScripts.apply(getApplication<Application>().assets, _state.value.readerSettings),
            null
        )
    }

    fun updateReaderSettings(mutate: (ReaderSettings) -> ReaderSettings) {
        _state.update { it.copy(readerSettings = mutate(it.readerSettings)) }
        refreshReader()
    }

    fun toggleDesktop() {
        val tab = _state.value.activeTab ?: return
        if (UrlPolicy.isHomeUrl(tab.url)) return
        val next = !tab.isDesktop
        val target = if (next) UrlPolicy.desktopUrl(tab.url) else tab.url
        val urlChanged = target != tab.url
        updateActive { it.copy(isDesktop = next, isReader = false, url = target) }
        val webView = activeWebView()
        if (webView != null) {
            WebKernel.applyUserAgent(webView, next)
            if (!urlChanged) webView.reload()
        }
        persist()
    }

    fun beginFind() {
        val tab = _state.value.activeTab ?: return
        if (UrlPolicy.isHomeUrl(tab.url)) return
        _state.update { it.copy(showsFind = true) }
    }

    fun setFindQuery(query: String) {
        _state.update { it.copy(findQuery = query) }
        val trimmed = query.trim()
        val webView = activeWebView()
        if (trimmed.isEmpty()) {
            webView?.clearMatches()
            _state.update { it.copy(findCurrent = 0, findTotal = 0) }
            return
        }
        webView?.findAllAsync(trimmed)
    }

    fun findNext() {
        if (_state.value.findTotal <= 0) return
        activeWebView()?.findNext(true)
    }

    fun findPrevious() {
        if (_state.value.findTotal <= 0) return
        activeWebView()?.findNext(false)
    }

    fun endFind() {
        activeWebView()?.clearMatches()
        _state.update { it.copy(showsFind = false, findQuery = "", findCurrent = 0, findTotal = 0) }
    }

    fun onFindResult(activeOrdinal: Int, total: Int) {
        _state.update {
            it.copy(
                findTotal = total,
                findCurrent = if (total == 0) 0 else activeOrdinal + 1
            )
        }
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

    fun updateTab(
        id: String,
        title: String? = null,
        url: String? = null,
        loading: Boolean? = null,
        isReader: Boolean? = null,
        isDesktop: Boolean? = null
    ) {
        _state.update { current ->
            current.copy(
                tabs = current.tabs.map { tab ->
                    if (tab.id != id) tab
                    else tab.copy(
                        title = title ?: tab.title,
                        url = url ?: tab.url,
                        isLoading = loading ?: tab.isLoading,
                        isReader = isReader ?: tab.isReader,
                        isDesktop = isDesktop ?: tab.isDesktop,
                        lastVisitedAt = System.currentTimeMillis()
                    )
                }
            )
        }
    }

    fun goBackToHomeIfNeeded(id: String): Boolean {
        val tab = _state.value.tabs.firstOrNull { it.id == id } ?: return false
        if (UrlPolicy.isHomeUrl(tab.url)) return false
        endFind()
        updateTab(
            id,
            url = UrlPolicy.HOME_URL,
            title = if (tab.isPrivate) "无痕" else "新标签页",
            loading = false,
            isReader = false
        )
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

    private fun completePermission(allowed: Boolean) {
        val prompt = _state.value.permissionPrompt ?: return
        if (prompt.persist) {
            _state.update {
                it.copy(
                    sitePermissions = SitePermissionPolicy.apply(
                        it.sitePermissions,
                        prompt.origin,
                        prompt.kinds,
                        if (allowed) SitePermissionDecision.Allow else SitePermissionDecision.Deny
                    ),
                    permissionPrompt = null
                )
            }
            persistSitePermissions()
        } else {
            _state.update { it.copy(permissionPrompt = null) }
        }
        if (allowed) {
            deliverPermission(prompt.kinds, permissionReply ?: return)
        } else {
            val reply = permissionReply
            permissionReply = null
            reply?.invoke(false)
        }
    }

    private fun deliverPermission(kinds: List<SitePermissionKind>, completion: (Boolean) -> Unit) {
        if (hasOsPermissions(kinds)) {
            permissionReply = null
            completion(true)
            return
        }
        permissionReply = completion
        _state.update { it.copy(osPermissionsToRequest = missingOsPermissions(kinds)) }
    }

    private fun hasOsPermissions(kinds: List<SitePermissionKind>): Boolean {
        val app = getApplication<Application>()
        fun granted(permission: String): Boolean =
            ContextCompat.checkSelfPermission(app, permission) == PackageManager.PERMISSION_GRANTED
        for (kind in kinds) {
            val ok = when (kind) {
                SitePermissionKind.Camera -> granted(Manifest.permission.CAMERA)
                SitePermissionKind.Microphone -> granted(Manifest.permission.RECORD_AUDIO)
                SitePermissionKind.Location ->
                    granted(Manifest.permission.ACCESS_FINE_LOCATION) ||
                        granted(Manifest.permission.ACCESS_COARSE_LOCATION)
            }
            if (!ok) return false
        }
        return true
    }

    private fun missingOsPermissions(kinds: List<SitePermissionKind>): List<String> {
        val app = getApplication<Application>()
        fun granted(permission: String): Boolean =
            ContextCompat.checkSelfPermission(app, permission) == PackageManager.PERMISSION_GRANTED
        val needed = mutableListOf<String>()
        if (SitePermissionKind.Camera in kinds && !granted(Manifest.permission.CAMERA)) {
            needed.add(Manifest.permission.CAMERA)
        }
        if (SitePermissionKind.Microphone in kinds && !granted(Manifest.permission.RECORD_AUDIO)) {
            needed.add(Manifest.permission.RECORD_AUDIO)
        }
        if (SitePermissionKind.Location in kinds &&
            !granted(Manifest.permission.ACCESS_FINE_LOCATION) &&
            !granted(Manifest.permission.ACCESS_COARSE_LOCATION)
        ) {
            needed.add(Manifest.permission.ACCESS_FINE_LOCATION)
            needed.add(Manifest.permission.ACCESS_COARSE_LOCATION)
        }
        return needed
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

    private fun activeWebView(): WebView? = webViews[_state.value.activeTabId]

    private fun destroyWebView(id: String) {
        webViews.remove(id)?.let { view ->
            view.stopLoading()
            view.destroy()
        }
    }

    override fun onCleared() {
        denyPermissionIfPending()
        webViews.keys.toList().forEach { destroyWebView(it) }
        downloads.close()
        super.onCleared()
    }

    private fun persist() {
        persistSettings()
        persistAllowList()
        persistLibrary()
        persistReaderSettings()
        persistSitePermissions()
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
                    .put("isReader", tab.isReader)
                    .put("isDesktop", tab.isDesktop)
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

    private fun persistReaderSettings() {
        val settings = _state.value.readerSettings
        prefs.edit()
            .putInt("readerFontSize", settings.fontSize)
            .putInt("readerLineHeightIndex", settings.lineHeightIndex)
            .putInt("readerPaper", settings.paper.raw)
            .apply()
    }

    private fun persistSitePermissions() {
        val array = JSONArray()
        _state.value.sitePermissions.forEach { entry ->
            array.put(
                JSONObject()
                    .put("origin", entry.origin)
                    .put("camera", entry.camera.raw)
                    .put("microphone", entry.microphone.raw)
                    .put("location", entry.location.raw)
            )
        }
        prefs.edit().putString("sitePermissions", array.toString()).apply()
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
        val readerSettings = ReaderSettings(
            fontSize = prefs.getInt("readerFontSize", 17),
            lineHeightIndex = prefs.getInt("readerLineHeightIndex", 1),
            paper = ReaderPaper.fromRaw(prefs.getInt("readerPaper", ReaderPaper.Sepia.raw))
        )
        val sitePermissions = runCatching {
            val array = JSONArray(prefs.getString("sitePermissions", "[]"))
            buildList {
                for (i in 0 until array.length()) {
                    val obj = array.getJSONObject(i)
                    add(
                        SitePermission(
                            origin = obj.getString("origin"),
                            camera = SitePermissionDecision.fromRaw(obj.optInt("camera")),
                            microphone = SitePermissionDecision.fromRaw(obj.optInt("microphone")),
                            location = SitePermissionDecision.fromRaw(obj.optInt("location"))
                        )
                    )
                }
            }
        }.getOrDefault(emptyList())
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
                            lastVisitedAt = obj.optLong("lastVisitedAt"),
                            isReader = obj.optBoolean("isReader"),
                            isDesktop = obj.optBoolean("isDesktop")
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
            sitePermissions = sitePermissions,
            history = history,
            savedItems = savedItems,
            readerSettings = readerSettings
        )
    }
}
