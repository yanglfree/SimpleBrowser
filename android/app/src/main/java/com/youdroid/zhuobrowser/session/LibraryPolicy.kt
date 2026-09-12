package com.youdroid.zhuobrowser.session

import com.youdroid.zhuobrowser.policy.UrlPolicy

data class HistoryEntry(
    val id: String,
    val title: String,
    val url: String,
    val visitedAt: Long,
    val visitCount: Int
)

data class SavedItem(
    val id: String,
    val title: String,
    val url: String,
    val createdAt: Long,
    val updatedAt: Long
)

enum class SuggestionKind { History, Bookmark, Search }

data class AddressSuggestion(
    val id: String,
    val kind: SuggestionKind,
    val title: String,
    val subtitle: String,
    val url: String
)

object LibraryPolicy {
    const val MAX_HISTORY_COUNT = 300
    const val MAX_BOOKMARK_COUNT = 200
    const val MAX_SUGGESTION_COUNT = 6

    fun recordHistory(history: List<HistoryEntry>, entry: HistoryEntry): List<HistoryEntry> {
        val previous = history.firstOrNull { it.url == entry.url }
        val merged = entry.copy(visitCount = (previous?.visitCount ?: 0) + 1)
        return listOf(merged) + history.filter { it.url != entry.url }.take(MAX_HISTORY_COUNT - 1)
    }

    fun addSavedItem(items: List<SavedItem>, item: SavedItem): List<SavedItem> {
        return listOf(item) + items.filter { it.url != item.url }.take(MAX_BOOKMARK_COUNT - 1)
    }

    fun removeSavedItem(items: List<SavedItem>, id: String): List<SavedItem> =
        items.filter { it.id != id }

    fun isSaved(items: List<SavedItem>, url: String): Boolean =
        !UrlPolicy.isHomeUrl(url) && items.any { it.url == url }

    fun suggestions(
        query: String,
        history: List<HistoryEntry>,
        savedItems: List<SavedItem>,
        searchSuggestionsEnabled: Boolean,
        searchUrl: String
    ): List<AddressSuggestion> {
        val trimmed = query.trim()
        val results = mutableListOf<AddressSuggestion>()
        if (trimmed.isEmpty()) {
            for (entry in history) {
                if (results.size >= MAX_SUGGESTION_COUNT) break
                results.add(historySuggestion(entry))
            }
            for (bookmark in savedItems) {
                if (results.size >= MAX_SUGGESTION_COUNT) break
                if (results.none { it.url == bookmark.url }) results.add(bookmarkSuggestion(bookmark))
            }
            return results
        }
        val needle = trimmed.lowercase()
        fun matches(title: String, url: String) =
            title.lowercase().contains(needle) || url.lowercase().contains(needle)
        for (entry in history) {
            if (results.size >= MAX_SUGGESTION_COUNT) break
            if (matches(entry.title, entry.url)) results.add(historySuggestion(entry))
        }
        for (bookmark in savedItems) {
            if (results.size >= MAX_SUGGESTION_COUNT) break
            if (matches(bookmark.title, bookmark.url) && results.none { it.url == bookmark.url }) {
                results.add(bookmarkSuggestion(bookmark))
            }
        }
        if (searchSuggestionsEnabled && results.size < MAX_SUGGESTION_COUNT && searchUrl.isNotEmpty()) {
            results.add(
                AddressSuggestion(
                    id = "search-$trimmed",
                    kind = SuggestionKind.Search,
                    title = trimmed,
                    subtitle = "",
                    url = searchUrl
                )
            )
        }
        return results
    }

    private fun historySuggestion(entry: HistoryEntry): AddressSuggestion {
        val host = UrlPolicy.displayHost(entry.url)
        return AddressSuggestion(
            id = "history-${entry.id}",
            kind = SuggestionKind.History,
            title = entry.title.ifEmpty { host },
            subtitle = host,
            url = entry.url
        )
    }

    private fun bookmarkSuggestion(item: SavedItem): AddressSuggestion {
        val host = UrlPolicy.displayHost(item.url)
        return AddressSuggestion(
            id = "bookmark-${item.id}",
            kind = SuggestionKind.Bookmark,
            title = item.title.ifEmpty { host },
            subtitle = host,
            url = item.url
        )
    }
}
