package com.youdroid.zhuobrowser

import com.youdroid.zhuobrowser.account.AuthProviderKind
import com.youdroid.zhuobrowser.account.BookmarkFolder
import com.youdroid.zhuobrowser.account.BookmarkTombstone
import com.youdroid.zhuobrowser.account.RegionAuthPolicy
import com.youdroid.zhuobrowser.account.SyncMergePolicy
import com.youdroid.zhuobrowser.session.BrowserTab
import com.youdroid.zhuobrowser.session.SavedItem
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AccountSyncPolicyTest {
    @Test
    fun hidesGoogleSignInInMainlandChinaAndAllowsNonCn() {
        assertFalse(RegionAuthPolicy.isGoogleSignInAvailable("CN"))
        assertFalse(RegionAuthPolicy.isGoogleSignInAvailable("cn"))
        assertFalse(RegionAuthPolicy.isGoogleSignInAvailable(""))
        assertFalse(RegionAuthPolicy.isGoogleSignInAvailable(null))

        assertTrue(RegionAuthPolicy.isGoogleSignInAvailable("US"))
        assertTrue(RegionAuthPolicy.isGoogleSignInAvailable("HK"))
        assertTrue(RegionAuthPolicy.isGoogleSignInAvailable("JP"))

        assertEquals(
            listOf(AuthProviderKind.EMAIL_OTP, AuthProviderKind.EMAIL_PASSWORD),
            RegionAuthPolicy.availableProviders("CN")
        )
        assertEquals(
            listOf(AuthProviderKind.EMAIL_OTP, AuthProviderKind.EMAIL_PASSWORD, AuthProviderKind.GOOGLE),
            RegionAuthPolicy.availableProviders("US")
        )
    }

    @Test
    fun normalizesSecondsToUtcMilliseconds() {
        val fallback = 1_760_000_000_000L
        assertEquals(1_700_000_000_000L, SyncMergePolicy.normalizeTimestampMs(1_700_000_000L, fallback))
        assertEquals(1_750_000_000_123L, SyncMergePolicy.normalizeTimestampMs(1_750_000_000_123L, fallback))
        assertEquals(fallback, SyncMergePolicy.normalizeTimestampMs(0L, fallback))
    }

    @Test
    fun mergesSupersetBookmarksAndHonorsTombstonesAndRetention() {
        val now = 1_760_000_000_000L
        val folder = BookmarkFolder(
            id = "f-1",
            name = "Reading",
            createdAt = now - 5_000,
            updatedAt = now - 2_000,
            sortOrder = 1
        )
        val localItem = SavedItem(
            id = "b-1",
            title = "Old Title",
            url = "https://example.com/post/",
            createdAt = now - 10_000,
            updatedAt = now - 4_000,
            folderId = "f-1",
            isRead = false,
            tags = listOf("tech")
        )
        val remoteItem = SavedItem(
            id = "b-1",
            title = "New Title",
            url = "https://example.com/post",
            createdAt = now - 10_000,
            updatedAt = now - 1_000,
            folderId = "f-1",
            isRead = true,
            tags = listOf("mobile"),
            sortOrder = 2
        )
        val deletedItem = SavedItem(
            id = "b-deleted",
            title = "Gone",
            url = "https://example.com/deleted",
            createdAt = now - 20_000,
            updatedAt = now - 5_000
        )
        val freshTombstone = BookmarkTombstone(
            id = "b-deleted",
            url = "https://example.com/deleted",
            deletedAt = now - 1_000
        )
        val expiredTombstone = BookmarkTombstone(
            id = "b-expired",
            url = "https://example.com/expired",
            deletedAt = now - SyncMergePolicy.TOMBSTONE_RETENTION_MS - 1_000
        )

        val result = SyncMergePolicy.mergeBookmarks(
            localFolders = listOf(folder),
            remoteFolders = emptyList(),
            localItems = listOf(localItem, deletedItem),
            remoteItems = listOf(remoteItem),
            localTombstones = listOf(expiredTombstone),
            remoteTombstones = listOf(freshTombstone),
            nowMs = now
        )

        assertEquals(1, result.folders.size)
        assertEquals(1, result.items.size)
        assertEquals("New Title", result.items.first().title)
        assertEquals("https://example.com/post", result.items.first().url)
        assertEquals("f-1", result.items.first().folderId)
        assertTrue(result.items.first().isRead)
        assertEquals(listOf("tech", "mobile"), result.items.first().tags)
        assertEquals(1, result.tombstones.size)
        assertEquals("b-deleted", result.tombstones.first().id)
    }

    @Test
    fun sanitizesDeviceTabsExcludingPrivateAndHome() {
        val tabs = listOf(
            BrowserTab(id = "t1", url = "browser://home", title = "Home"),
            BrowserTab(id = "t2", url = "https://secret.example", title = "Secret", isPrivate = true),
            BrowserTab(id = "t3", url = "https://news.ycombinator.com", title = "HN", lastVisitedAt = 100L),
            BrowserTab(id = "t4", url = "https://news.ycombinator.com", title = "HN Duplicate", lastVisitedAt = 200L)
        )
        val clean = SyncMergePolicy.sanitizeDeviceTabs(tabs)
        assertEquals(1, clean.size)
        assertEquals("https://news.ycombinator.com", clean.first().url)
    }
}
