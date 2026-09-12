package com.youdroid.zhuobrowser.ui

import android.content.Intent
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.youdroid.zhuobrowser.policy.SearchEngine
import com.youdroid.zhuobrowser.policy.UrlPolicy
import com.youdroid.zhuobrowser.session.AddressSuggestion
import com.youdroid.zhuobrowser.session.AllowListPolicy
import com.youdroid.zhuobrowser.session.BrowserSession
import com.youdroid.zhuobrowser.session.BrowserTab
import com.youdroid.zhuobrowser.session.HistoryEntry
import com.youdroid.zhuobrowser.session.LibraryTab
import com.youdroid.zhuobrowser.session.SavedItem
import com.youdroid.zhuobrowser.session.SuggestionKind
import com.youdroid.zhuobrowser.web.BrowserWebView
import kotlinx.coroutines.delay

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun BrowserScreen(session: BrowserSession) {
    val state by session.state.collectAsStateWithLifecycle()
    val tab = state.activeTab
    val context = LocalContext.current
    val focusManager = LocalFocusManager.current
    var address by remember { mutableStateOf("") }
    var menuOpen by remember { mutableStateOf(false) }
    var addressFocused by remember { mutableStateOf(false) }

    LaunchedEffect(tab?.id, tab?.url) {
        if (tab != null && !addressFocused) {
            address = if (UrlPolicy.isHomeUrl(tab.url)) "" else tab.url
        }
    }
    LaunchedEffect(state.notice) {
        if (state.notice != null) {
            delay(2000)
            session.clearNotice()
        }
    }

    val overlayOpen = state.showsSettings || state.showsLibrary || state.showsOverview
    BackHandler(enabled = overlayOpen || (tab != null && !UrlPolicy.isHomeUrl(tab.url))) {
        when {
            state.showsLibrary -> session.setShowsLibrary(false)
            state.showsSettings -> session.setShowsSettings(false)
            state.showsOverview -> session.toggleOverview()
            else -> tab?.let { session.goBackToHomeIfNeeded(it.id) }
        }
    }

    fun dismissKeyboard() {
        addressFocused = false
        focusManager.clearFocus()
    }

    fun shareCurrentPage() {
        val payload = session.sharePayload() ?: return
        val send = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_SUBJECT, payload.first)
            putExtra(Intent.EXTRA_TEXT, payload.second)
        }
        context.startActivity(Intent.createChooser(send, "分享"))
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Tokens.pageBackground)
    ) {
        AddressBar(
            address = address,
            onAddressChange = { address = it },
            onAddressFocusChange = { addressFocused = it },
            tabCount = state.tabs.size,
            isPrivate = tab?.isPrivate == true,
            canGoBack = tab != null && !UrlPolicy.isHomeUrl(tab.url),
            browsing = tab != null && !UrlPolicy.isHomeUrl(tab.url),
            menuOpen = menuOpen,
            onMenuChange = { menuOpen = it },
            onSubmit = {
                dismissKeyboard()
                session.openInActiveTab(address)
            },
            onBack = { tab?.let { session.goBackToHomeIfNeeded(it.id) } },
            onOverview = {
                dismissKeyboard()
                session.toggleOverview()
            },
            onNewPrivate = { session.createTab(true) },
            onAllowSite = { session.toggleCurrentHostAllowed() },
            onBookmark = { session.toggleSaved() },
            onLibrary = {
                dismissKeyboard()
                session.openLibrary(LibraryTab.Bookmarks)
            },
            onShare = { shareCurrentPage() },
            onSettings = {
                dismissKeyboard()
                session.setShowsSettings(true)
            },
            siteAllowed = tab != null && AllowListPolicy.isHostAllowed(state.allowedHosts, UrlPolicy.rawHost(tab.url)),
            pageSaved = session.isCurrentPageSaved()
        )
        Box(modifier = Modifier.weight(1f)) {
            when {
                state.showsSettings -> SettingsPane(session)
                state.showsLibrary -> LibraryPane(session)
                state.showsOverview -> TabOverview(session)
                tab == null || UrlPolicy.isHomeUrl(tab.url) -> NativeHome(
                    onOpen = { session.openInActiveTab(it) },
                    onSettings = { session.setShowsSettings(true) },
                    onBookmarks = { session.openLibrary(LibraryTab.Bookmarks) },
                    onHistory = { session.openLibrary(LibraryTab.History) }
                )
                else -> BrowserWebView(tab = tab, session = session, modifier = Modifier.fillMaxSize())
            }
            val suggestions = if (addressFocused && !overlayOpen) session.suggestions(address) else emptyList()
            if (suggestions.isNotEmpty()) {
                SuggestionList(
                    suggestions = suggestions,
                    onSelect = { item ->
                        dismissKeyboard()
                        address = if (UrlPolicy.isHomeUrl(item.url)) "" else item.url
                        session.openInActiveTab(item.url)
                    }
                )
            }
            state.notice?.let { notice ->
                Text(
                    text = notice,
                    color = Tokens.textPrimary,
                    modifier = Modifier
                        .align(Alignment.TopCenter)
                        .padding(top = 16.dp)
                        .clip(RoundedCornerShape(20.dp))
                        .background(Tokens.surfacePanel)
                        .padding(horizontal = 16.dp, vertical = 10.dp)
                )
            }
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun AddressBar(
    address: String,
    onAddressChange: (String) -> Unit,
    onAddressFocusChange: (Boolean) -> Unit,
    tabCount: Int,
    isPrivate: Boolean,
    canGoBack: Boolean,
    browsing: Boolean,
    menuOpen: Boolean,
    onMenuChange: (Boolean) -> Unit,
    onSubmit: () -> Unit,
    onBack: () -> Unit,
    onOverview: () -> Unit,
    onNewPrivate: () -> Unit,
    onAllowSite: () -> Unit,
    onBookmark: () -> Unit,
    onLibrary: () -> Unit,
    onShare: () -> Unit,
    onSettings: () -> Unit,
    siteAllowed: Boolean,
    pageSaved: Boolean
) {
    Column(modifier = Modifier.background(if (isPrivate) Tokens.surfaceSubtle else Tokens.surfacePanel)) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = "‹",
                fontSize = 22.sp,
                color = if (canGoBack) Tokens.textPrimary else Tokens.textSecondary,
                modifier = Modifier
                    .clickable(enabled = canGoBack, onClick = onBack)
                    .padding(8.dp)
            )
            OutlinedTextField(
                value = address,
                onValueChange = onAddressChange,
                modifier = Modifier
                    .weight(1f)
                    .onFocusChanged { onAddressFocusChange(it.isFocused) },
                singleLine = true,
                placeholder = { Text(if (isPrivate) "无痕搜索或输入网址" else "搜索或输入网址") },
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Go),
                keyboardActions = KeyboardActions(onGo = { onSubmit() }),
                shape = RoundedCornerShape(20.dp),
                colors = TextFieldDefaults.colors(
                    focusedContainerColor = Tokens.surfaceSubtle,
                    unfocusedContainerColor = Tokens.surfaceSubtle,
                    focusedIndicatorColor = Tokens.border,
                    unfocusedIndicatorColor = Tokens.border
                )
            )
            Box {
                Text(
                    text = "⋯",
                    fontSize = 20.sp,
                    modifier = Modifier
                        .clickable { onMenuChange(true) }
                        .padding(8.dp)
                )
                DropdownMenu(expanded = menuOpen, onDismissRequest = { onMenuChange(false) }) {
                    DropdownMenuItem(
                        text = { Text(if (siteAllowed) "对此站点恢复拦截" else "允许此站点加载广告") },
                        enabled = browsing,
                        onClick = { onMenuChange(false); onAllowSite() }
                    )
                    DropdownMenuItem(
                        text = { Text(if (pageSaved) "取消书签" else "加入书签") },
                        enabled = browsing,
                        onClick = { onMenuChange(false); onBookmark() }
                    )
                    DropdownMenuItem(
                        text = { Text("书签与历史") },
                        onClick = { onMenuChange(false); onLibrary() }
                    )
                    DropdownMenuItem(
                        text = { Text("分享") },
                        enabled = browsing,
                        onClick = { onMenuChange(false); onShare() }
                    )
                    DropdownMenuItem(
                        text = { Text("设置") },
                        onClick = { onMenuChange(false); onSettings() }
                    )
                }
            }
            Text(
                text = "$tabCount",
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier
                    .clip(RoundedCornerShape(16.dp))
                    .background(Tokens.surfaceSubtle)
                    .combinedClickable(onClick = onOverview, onLongClick = onNewPrivate)
                    .padding(horizontal = 10.dp, vertical = 8.dp)
            )
        }
        HorizontalDivider(color = Tokens.border)
    }
}

@Composable
private fun SuggestionList(
    suggestions: List<AddressSuggestion>,
    onSelect: (AddressSuggestion) -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(Tokens.surfacePanel)
            .padding(vertical = 4.dp)
    ) {
        suggestions.forEach { item ->
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { onSelect(item) }
                    .padding(horizontal = 16.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = when (item.kind) {
                        SuggestionKind.History -> "历史"
                        SuggestionKind.Bookmark -> "书签"
                        SuggestionKind.Search -> "搜索"
                    },
                    fontSize = 12.sp,
                    color = Tokens.accent,
                    modifier = Modifier.padding(end = 12.dp)
                )
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = item.title,
                        color = Tokens.textPrimary,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                    if (item.subtitle.isNotEmpty()) {
                        Text(
                            text = item.subtitle,
                            fontSize = 12.sp,
                            color = Tokens.textSecondary,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun NativeHome(
    onOpen: (String) -> Unit,
    onSettings: () -> Unit,
    onBookmarks: () -> Unit,
    onHistory: () -> Unit
) {
    data class Site(val id: String, val title: String, val url: String, val badge: String, val color: androidx.compose.ui.graphics.Color)
    val sites = listOf(
        Site("zhihu", "知乎", "https://www.zhihu.com", "知", androidx.compose.ui.graphics.Color(0xFF2563EB)),
        Site("bilibili", "哔哩哔哩", "https://www.bilibili.com", "哔", androidx.compose.ui.graphics.Color(0xFFE11D48)),
        Site("sspai", "少数派", "https://sspai.com", "派", androidx.compose.ui.graphics.Color(0xFF059669)),
        Site("weibo", "微博", "https://weibo.com", "微", androidx.compose.ui.graphics.Color(0xFFD97706)),
        Site("douban", "豆瓣", "https://www.douban.com", "豆", androidx.compose.ui.graphics.Color(0xFF7C3AED)),
        Site("kr", "36氪", "https://36kr.com", "氪", androidx.compose.ui.graphics.Color(0xFF0891B2))
    )
    Column(modifier = Modifier.fillMaxSize().padding(24.dp)) {
        Row(verticalAlignment = Alignment.Top) {
            Column(modifier = Modifier.weight(1f)) {
                Text("卓阅", fontSize = 30.sp, fontWeight = FontWeight.SemiBold, color = Tokens.textPrimary)
                Text("干净、克制的阅读浏览器", fontSize = 15.sp, color = Tokens.textSecondary)
            }
            Text("书签", color = Tokens.textPrimary, modifier = Modifier.clickable(onClick = onBookmarks).padding(8.dp))
            Text("历史", color = Tokens.textPrimary, modifier = Modifier.clickable(onClick = onHistory).padding(8.dp))
            Text("设置", color = Tokens.textPrimary, modifier = Modifier.clickable(onClick = onSettings).padding(8.dp))
        }
        Spacer(Modifier.height(24.dp))
        LazyVerticalGrid(columns = GridCells.Fixed(3), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            items(sites, key = { it.id }) { site ->
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    modifier = Modifier.clickable { onOpen(site.url) }
                ) {
                    Box(
                        contentAlignment = Alignment.Center,
                        modifier = Modifier
                            .size(48.dp)
                            .clip(RoundedCornerShape(14.dp))
                            .background(site.color)
                    ) {
                        Text(site.badge, color = androidx.compose.ui.graphics.Color.White, fontWeight = FontWeight.SemiBold)
                    }
                    Spacer(Modifier.height(8.dp))
                    Text(site.title, fontSize = 13.sp, color = Tokens.textPrimary)
                }
            }
        }
    }
}

@Composable
private fun TabOverview(session: BrowserSession) {
    val state by session.state.collectAsStateWithLifecycle()
    Column(modifier = Modifier.fillMaxSize().background(Tokens.pageBackground)) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(20.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text("${state.tabs.size} 个标签页", fontSize = 20.sp, fontWeight = FontWeight.SemiBold, color = Tokens.textPrimary)
            Spacer(Modifier.weight(1f))
            TextButton(onClick = { session.closeAll() }) { Text("全部关闭", color = Tokens.accent) }
        }
        LazyVerticalGrid(
            columns = GridCells.Fixed(2),
            modifier = Modifier.weight(1f),
            contentPadding = PaddingValues(horizontal = 20.dp, vertical = 8.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            items(state.tabs, key = { it.id }) { tab ->
                TabCard(tab = tab, selected = tab.id == state.activeTabId, onOpen = { session.selectTab(tab.id) }, onClose = { session.closeTab(tab.id) })
            }
        }
        Row(modifier = Modifier.padding(20.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Button(
                onClick = { session.createTab(false) },
                modifier = Modifier.weight(1f),
                colors = ButtonDefaults.buttonColors(containerColor = Tokens.surfaceSubtle, contentColor = Tokens.textPrimary)
            ) { Text("新建标签页") }
            Button(
                onClick = { session.createTab(true) },
                modifier = Modifier.weight(1f),
                colors = ButtonDefaults.buttonColors(containerColor = Tokens.surfaceSubtle, contentColor = Tokens.textPrimary)
            ) { Text("无痕标签页") }
        }
    }
}

@Composable
private fun TabCard(tab: BrowserTab, selected: Boolean, onOpen: () -> Unit, onClose: () -> Unit) {
    Column(
        modifier = Modifier
            .clip(RoundedCornerShape(16.dp))
            .background(if (tab.isPrivate) Tokens.surfaceSubtle else Tokens.surfacePanel)
            .border(if (selected) 2.dp else 1.dp, if (selected) Tokens.accent else Tokens.border, RoundedCornerShape(16.dp))
            .clickable(onClick = onOpen)
            .padding(12.dp)
            .height(96.dp)
    ) {
        Row {
            Text(
                text = if (tab.isPrivate) "无痕" else tab.displayTitle,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f),
                color = Tokens.textPrimary,
                fontSize = 14.sp,
                fontWeight = FontWeight.Medium
            )
            Text("×", modifier = Modifier.clickable(onClick = onClose).padding(4.dp), color = Tokens.textSecondary)
        }
        Text(
            text = if (UrlPolicy.isHomeUrl(tab.url)) "起始页" else tab.url,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
            fontSize = 11.sp,
            color = Tokens.textSecondary
        )
    }
}

@Composable
private fun LibraryPane(session: BrowserSession) {
    val state by session.state.collectAsStateWithLifecycle()
    Column(modifier = Modifier.fillMaxSize().background(Tokens.pageBackground).padding(20.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("书签与历史", fontSize = 24.sp, fontWeight = FontWeight.Medium, color = Tokens.textPrimary, modifier = Modifier.weight(1f))
            TextButton(onClick = { session.setShowsLibrary(false) }) { Text("完成", color = Tokens.accent) }
        }
        Row(modifier = Modifier.padding(vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
            Text(
                text = "书签",
                fontWeight = if (state.libraryTab == LibraryTab.Bookmarks) FontWeight.SemiBold else FontWeight.Normal,
                color = if (state.libraryTab == LibraryTab.Bookmarks) Tokens.accent else Tokens.textSecondary,
                modifier = Modifier.clickable { session.setLibraryTab(LibraryTab.Bookmarks) }.padding(vertical = 8.dp)
            )
            Text(
                text = "历史",
                fontWeight = if (state.libraryTab == LibraryTab.History) FontWeight.SemiBold else FontWeight.Normal,
                color = if (state.libraryTab == LibraryTab.History) Tokens.accent else Tokens.textSecondary,
                modifier = Modifier.clickable { session.setLibraryTab(LibraryTab.History) }.padding(vertical = 8.dp)
            )
        }
        Box(modifier = Modifier.weight(1f)) {
            if (state.libraryTab == LibraryTab.Bookmarks) {
                BookmarkList(
                    items = state.savedItems,
                    onOpen = { url ->
                        session.setShowsLibrary(false)
                        session.openInActiveTab(url)
                    },
                    onRemove = { session.removeSavedItem(it) }
                )
            } else {
                HistoryList(
                    items = state.history,
                    onOpen = { url ->
                        session.setShowsLibrary(false)
                        session.openInActiveTab(url)
                    },
                    onRemove = { session.removeHistory(it) }
                )
            }
        }
    }
}

@Composable
private fun BookmarkList(
    items: List<SavedItem>,
    onOpen: (String) -> Unit,
    onRemove: (String) -> Unit
) {
    if (items.isEmpty()) {
        Text("还没有书签", color = Tokens.textSecondary, modifier = Modifier.padding(top = 24.dp))
        return
    }
    LazyColumn(modifier = Modifier.fillMaxSize()) {
        items(items, key = { it.id }) { item ->
            LibraryRow(
                title = item.title,
                url = item.url,
                onOpen = { onOpen(item.url) },
                onRemove = { onRemove(item.id) }
            )
        }
    }
}

@Composable
private fun HistoryList(
    items: List<HistoryEntry>,
    onOpen: (String) -> Unit,
    onRemove: (String) -> Unit
) {
    if (items.isEmpty()) {
        Text("还没有历史记录", color = Tokens.textSecondary, modifier = Modifier.padding(top = 24.dp))
        return
    }
    LazyColumn(modifier = Modifier.fillMaxSize()) {
        items(items, key = { it.id }) { entry ->
            LibraryRow(
                title = entry.title,
                url = entry.url,
                onOpen = { onOpen(entry.url) },
                onRemove = { onRemove(entry.id) }
            )
        }
    }
}

@Composable
private fun LibraryRow(
    title: String,
    url: String,
    onOpen: () -> Unit,
    onRemove: () -> Unit
) {
    val host = UrlPolicy.displayHost(url)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onOpen)
            .padding(vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = title.ifEmpty { host },
                color = Tokens.textPrimary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            Text(
                text = host,
                fontSize = 12.sp,
                color = Tokens.textSecondary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
        Text("×", color = Tokens.textSecondary, modifier = Modifier.clickable(onClick = onRemove).padding(8.dp))
    }
}

@Composable
private fun SettingsPane(session: BrowserSession) {
    val state by session.state.collectAsStateWithLifecycle()
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(20.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("设置", fontSize = 24.sp, fontWeight = FontWeight.Medium, color = Tokens.textPrimary, modifier = Modifier.weight(1f))
            TextButton(onClick = { session.setShowsSettings(false) }) { Text("完成", color = Tokens.accent) }
        }
        Spacer(Modifier.height(16.dp))
        Text("搜索引擎", color = Tokens.textSecondary, fontSize = 13.sp)
        SearchEngine.entries.forEach { engine ->
            Text(
                text = if (state.settings.searchEngine == engine) "✓  ${engine.label}" else engine.label,
                modifier = Modifier.fillMaxWidth().clickable { session.setSearchEngine(engine) }.padding(vertical = 12.dp),
                color = Tokens.textPrimary
            )
        }
        HorizontalDivider(color = Tokens.border)
        Row(modifier = Modifier.fillMaxWidth().padding(vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            Text("拦截广告与跟踪器", modifier = Modifier.weight(1f), color = Tokens.textPrimary)
            Switch(
                checked = state.settings.blockAds,
                onCheckedChange = { session.setBlockAds(it) },
                colors = SwitchDefaults.colors(checkedTrackColor = Tokens.accent)
            )
        }
        Row(modifier = Modifier.fillMaxWidth().padding(vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            Text("显示搜索建议", modifier = Modifier.weight(1f), color = Tokens.textPrimary)
            Switch(
                checked = state.settings.searchSuggestionsEnabled,
                onCheckedChange = { session.setSearchSuggestionsEnabled(it) },
                colors = SwitchDefaults.colors(checkedTrackColor = Tokens.accent)
            )
        }
        HorizontalDivider(color = Tokens.border)
        Text(
            text = "书签与历史",
            color = Tokens.textPrimary,
            modifier = Modifier
                .fillMaxWidth()
                .clickable { session.openLibrary(LibraryTab.Bookmarks) }
                .padding(vertical = 12.dp)
        )
        if (state.allowedHosts.isNotEmpty()) {
            HorizontalDivider(color = Tokens.border)
            Text("已允许的站点", color = Tokens.textSecondary, fontSize = 13.sp, modifier = Modifier.padding(top = 12.dp))
            state.allowedHosts.forEach { host ->
                Text(host, color = Tokens.textPrimary, modifier = Modifier.padding(vertical = 8.dp))
            }
        }
    }
}
