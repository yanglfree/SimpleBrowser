package com.youdroid.zhuobrowser.session

import com.youdroid.zhuobrowser.policy.SearchEngine
import com.youdroid.zhuobrowser.policy.UrlPolicy
import java.util.UUID

data class BrowserTab(
    val id: String = UUID.randomUUID().toString(),
    val url: String = UrlPolicy.HOME_URL,
    val title: String = "新标签页",
    val isPrivate: Boolean = false,
    val isLoading: Boolean = false,
    val lastVisitedAt: Long = System.currentTimeMillis()
) {
    val displayTitle: String
        get() {
            if (title.isNotEmpty() && title != url) return title
            val host = UrlPolicy.displayHost(url)
            return host.ifEmpty { if (isPrivate) "无痕" else "新标签页" }
        }

    companion object {
        fun home(isPrivate: Boolean): BrowserTab = BrowserTab(
            url = UrlPolicy.HOME_URL,
            title = if (isPrivate) "无痕" else "新标签页",
            isPrivate = isPrivate
        )
    }
}

data class BrowserSettings(
    val searchEngine: SearchEngine = SearchEngine.Bing,
    val blockAds: Boolean = true
)

object SessionPolicy {
    const val MAX_TAB_COUNT = 100
    const val LIVE_WEBVIEW_LIMIT = 4

    fun persistableTabs(tabs: List<BrowserTab>): List<BrowserTab> = tabs.filter { !it.isPrivate }

    fun liveTabIds(tabs: List<BrowserTab>, activeTabId: String, limit: Int): List<String> {
        val bounded = limit.coerceAtLeast(1)
        val ids = mutableListOf<String>()
        if (activeTabId.isNotEmpty()) ids.add(activeTabId)
        for (tab in tabs) {
            if (ids.size >= bounded) break
            if (tab.id !in ids) ids.add(tab.id)
        }
        return ids
    }
}

object AllowListPolicy {
    fun isHostAllowed(hosts: List<String>, host: String): Boolean =
        host.isNotEmpty() && hosts.contains(host)

    fun setHostAllowed(hosts: List<String>, host: String, allowed: Boolean): List<String> {
        if (host.isEmpty()) return hosts
        val without = hosts.filter { it != host }
        return if (allowed) without + host else without
    }

    fun adsBlockEnabled(url: String, hosts: List<String>, blockAds: Boolean): Boolean {
        if (!blockAds || UrlPolicy.isHomeUrl(url)) return false
        return !isHostAllowed(hosts, UrlPolicy.rawHost(url))
    }
}
