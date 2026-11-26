package com.youdroid.zhuobrowser.account

import com.youdroid.zhuobrowser.policy.UrlPolicy
import com.youdroid.zhuobrowser.session.BrowserTab
import com.youdroid.zhuobrowser.session.SavedItem
import kotlin.math.roundToLong

data class AccountUserProfile(
    val id: String,
    val email: String,
    val displayName: String,
    val avatarUrl: String = "",
    val createdAt: Long = 0L
)

data class LinkedIdentityItem(
    val provider: String,
    val email: String,
    val emailVerified: Boolean
)

data class BookmarkFolder(
    val id: String,
    val name: String,
    val iconName: String = "folder.fill",
    val createdAt: Long,
    val updatedAt: Long,
    val sortOrder: Int = 0,
    val isPinnedToStartPage: Boolean = true
)

data class BookmarkTombstone(
    val id: String,
    val url: String = "",
    val isFolder: Boolean = false,
    val deletedAt: Long
)

data class RemoteDeviceTabEntry(
    val id: String,
    val title: String,
    val url: String,
    val lastVisitedAt: Long
)

data class RemoteDeviceTabGroup(
    val deviceId: String,
    val deviceName: String,
    val platform: String,
    val updatedAt: Long,
    val tabs: List<RemoteDeviceTabEntry>
)

data class ProEntitlementState(
    val active: Boolean = false,
    val scope: String = "pro",
    val plan: String = "",
    val productId: String = "",
    val expiresAt: Long = 0L,
    val source: String = "",
    val verifiedAt: Long = 0L
)

data class BookmarkSyncMergeResult(
    val folders: List<BookmarkFolder>,
    val items: List<SavedItem>,
    val tombstones: List<BookmarkTombstone>
)

/**
 * Pure Kotlin cross-platform LWW + tombstone merge policy aligned with core/src/sync-policy.mjs.
 */
object SyncMergePolicy {
    const val TOMBSTONE_RETENTION_MS: Long = 60L * 24L * 60L * 60L * 1000L

    fun normalizeTimestampMs(raw: Long, fallbackMs: Long): Long {
        if (raw <= 0L) return fallbackMs
        return if (raw < 10_000_000_000L) raw * 1000L else raw
    }

    fun normalizeTimestampDoubleMs(raw: Double, fallbackMs: Long): Long {
        if (!raw.isFinite() || raw <= 0.0) return fallbackMs
        val rounded = raw.roundToLong()
        return if (rounded < 10_000_000_000L) (raw * 1000.0).roundToLong() else rounded
    }

    fun normalizeComparableUrl(url: String): String {
        var trimmed = url.trim()
        while (trimmed.endsWith("/") && trimmed.length > 1) {
            trimmed = trimmed.dropLast(1)
        }
        return trimmed
    }

    fun mergeBookmarks(
        localFolders: List<BookmarkFolder>,
        remoteFolders: List<BookmarkFolder>,
        localItems: List<SavedItem>,
        remoteItems: List<SavedItem>,
        localTombstones: List<BookmarkTombstone>,
        remoteTombstones: List<BookmarkTombstone>,
        nowMs: Long
    ): BookmarkSyncMergeResult {
        val cutoff = nowMs - TOMBSTONE_RETENTION_MS
        val tombstoneByKey = linkedMapOf<String, BookmarkTombstone>()
        for (tb in localTombstones + remoteTombstones) {
            val deletedAt = normalizeTimestampMs(tb.deletedAt, nowMs)
            if (deletedAt < cutoff) continue
            val cleanUrl = normalizeComparableUrl(tb.url)
            val key = "${if (tb.isFolder) "folder" else "item"}:${tb.id.ifEmpty { cleanUrl }}"
            val existing = tombstoneByKey[key]
            if (existing == null || deletedAt > existing.deletedAt) {
                tombstoneByKey[key] = tb.copy(url = cleanUrl, deletedAt = deletedAt)
            }
        }
        val activeTombstones = tombstoneByKey.values.sortedByDescending { it.deletedAt }

        val folderTombstones = mutableMapOf<String, Long>()
        val itemTombstoneById = mutableMapOf<String, Long>()
        val itemTombstoneByUrl = mutableMapOf<String, Long>()
        for (tb in activeTombstones) {
            if (tb.isFolder) {
                folderTombstones[tb.id] = maxOf(folderTombstones[tb.id] ?: 0L, tb.deletedAt)
            } else {
                if (tb.id.isNotEmpty()) {
                    itemTombstoneById[tb.id] = maxOf(itemTombstoneById[tb.id] ?: 0L, tb.deletedAt)
                }
                if (tb.url.isNotEmpty()) {
                    itemTombstoneByUrl[tb.url] = maxOf(itemTombstoneByUrl[tb.url] ?: 0L, tb.deletedAt)
                }
            }
        }

        val folderMap = linkedMapOf<String, BookmarkFolder>()
        for (raw in localFolders + remoteFolders) {
            val createdAt = normalizeTimestampMs(raw.createdAt, nowMs)
            val updatedAt = normalizeTimestampMs(raw.updatedAt, createdAt)
            val deletedAt = folderTombstones[raw.id] ?: 0L
            if (deletedAt > updatedAt) continue
            val normalized = raw.copy(createdAt = createdAt, updatedAt = updatedAt)
            val existing = folderMap[normalized.id]
            if (existing == null || normalized.updatedAt > existing.updatedAt) {
                folderMap[normalized.id] = normalized
            }
        }

        val itemMap = linkedMapOf<String, SavedItem>()
        for (raw in localItems + remoteItems) {
            val cleanUrl = normalizeComparableUrl(raw.url)
            if (cleanUrl.isEmpty() || UrlPolicy.isHomeUrl(cleanUrl)) continue
            val createdAt = normalizeTimestampMs(raw.createdAt, nowMs)
            val updatedAt = normalizeTimestampMs(raw.updatedAt, createdAt)
            val deletedAt = maxOf(
                itemTombstoneById[raw.id] ?: 0L,
                itemTombstoneByUrl[cleanUrl] ?: 0L
            )
            if (deletedAt > updatedAt) continue
            val normalized = raw.copy(
                url = cleanUrl,
                createdAt = createdAt,
                updatedAt = updatedAt,
                folderId = raw.folderId?.takeIf { it.isNotBlank() },
                tags = raw.tags.map { it.trim() }.filter { it.isNotEmpty() }.distinct()
            )
            val existing = itemMap[cleanUrl]
            if (existing == null) {
                itemMap[cleanUrl] = normalized
            } else if (normalized.updatedAt > existing.updatedAt) {
                itemMap[cleanUrl] = normalized.copy(
                    tags = (existing.tags + normalized.tags).distinct(),
                    isRead = existing.isRead || normalized.isRead
                )
            } else {
                itemMap[cleanUrl] = existing.copy(
                    tags = (existing.tags + normalized.tags).distinct(),
                    isRead = existing.isRead || normalized.isRead
                )
            }
        }

        val mergedFolders = folderMap.values.sortedWith(
            compareBy<BookmarkFolder> { it.sortOrder }.thenBy { it.createdAt }
        )
        val mergedItems = itemMap.values.sortedWith(
            compareBy<SavedItem> { it.sortOrder }.thenByDescending { it.updatedAt }
        )
        return BookmarkSyncMergeResult(
            folders = mergedFolders,
            items = mergedItems,
            tombstones = activeTombstones
        )
    }

    fun sanitizeDeviceTabs(tabs: List<BrowserTab>, maxCount: Int = 50): List<RemoteDeviceTabEntry> {
        val clean = mutableListOf<RemoteDeviceTabEntry>()
        val seenUrls = hashSetOf<String>()
        for (tab in tabs) {
            if (tab.isPrivate) continue
            val url = tab.url.trim()
            if (url.isEmpty() || UrlPolicy.isHomeUrl(url)) continue
            if (!url.startsWith("http://", ignoreCase = true) && !url.startsWith("https://", ignoreCase = true)) {
                continue
            }
            if (!seenUrls.add(url)) continue
            clean.add(
                RemoteDeviceTabEntry(
                    id = tab.id,
                    title = tab.displayTitle.ifBlank { url },
                    url = url,
                    lastVisitedAt = tab.lastVisitedAt
                )
            )
            if (clean.size >= maxCount) break
        }
        return clean
    }
}
