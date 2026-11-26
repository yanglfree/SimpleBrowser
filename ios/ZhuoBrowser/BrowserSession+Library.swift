import Foundation
import UIKit
import UserNotifications
import WebKit

extension BrowserSession {
    func recordVisit(of tab: BrowserTab) {
        guard SessionPolicy.shouldRecordHistory(tab.isPrivate), !URLPolicy.isHomeURL(tab.url) else {
            return
        }
        let title = tab.title.isEmpty ? URLPolicy.displayHost(tab.url) : tab.title
        history = LibraryPolicy.recordHistory(
            history,
            entry: HistoryEntry(
                id: "history-\(Int(Date().timeIntervalSince1970 * 1000))",
                title: title,
                url: tab.url,
                visitedAt: Date().timeIntervalSince1970,
                visitCount: 0
            ),
            retentionDays: settings.historyRetention.rawValue
        )
        savedItems = LibraryPolicy.markSavedItemRead(savedItems, url: tab.url)
        persistLibrary()
    }

    func isCurrentPageSaved() -> Bool {
        guard let tab = activeTab else {
            return false
        }
        return LibraryPolicy.isSaved(savedItems, url: tab.url)
    }

    func toggleSaved() {
        guard let tab = activeTab, !URLPolicy.isHomeURL(tab.url) else {
            return
        }
        if let existing = savedItems.first(where: { $0.url == tab.url }) {
            savedItems = LibraryPolicy.removeSavedItem(savedItems, id: existing.id)
            recordBookmarkTombstone(id: existing.id, url: existing.url, isFolder: false)
            flash("已取消书签")
        } else {
            let now = Date().timeIntervalSince1970
            let title = tab.title.isEmpty ? URLPolicy.displayHost(tab.url) : tab.title
            savedItems = LibraryPolicy.addSavedItem(
                savedItems,
                item: SavedItem(
                    id: "saved-\(Int(now * 1000))",
                    title: title,
                    url: tab.url,
                    createdAt: now,
                    updatedAt: now
                )
            )
            flash("已加入书签")
        }
        persistLibrary()
    }

    func removeSavedItem(_ id: String) {
        if let removed = savedItems.first(where: { $0.id == id }) {
            recordBookmarkTombstone(id: removed.id, url: removed.url, isFolder: false)
        }
        savedItems = LibraryPolicy.removeSavedItem(savedItems, id: id)
        persistLibrary()
    }

    func recordBookmarkTombstone(id: String, url: String?, isFolder: Bool) {
        let now = Date().timeIntervalSince1970
        let cutoff = now - CloudSyncEngine.tombstoneRetentionSeconds
        bookmarkTombstones = bookmarkTombstones.filter {
            $0.deletedAt >= cutoff && $0.id != id
        } + [BookmarkTombstone(id: id, url: url, isFolder: isFolder, deletedAt: now)]
    }

    func applyCloudBookmarkMerge(folders: [BookmarkFolder], items: [SavedItem], tombstones: [BookmarkTombstone]) {
        bookmarkFolders = folders
        savedItems = items
        bookmarkTombstones = tombstones
        persistLibrary()
    }

    func renameSavedItem(_ id: String, title: String) {
        savedItems = LibraryPolicy.renameSavedItem(savedItems, id: id, title: title)
        persistLibrary()
    }

    func saveCurrentPageForLater() {
        guard let tab = activeTab, !tab.isPrivate, !URLPolicy.isHomeURL(tab.url) else {
            return
        }
        savedItems = LibraryPolicy.saveForLater(
            savedItems,
            url: tab.url,
            title: tab.displayTitle
        )
        persistLibrary()
        flash("已加入稍后读")
    }

    func saveLinkForLater(_ url: URL, sourceTabID: String) {
        guard let source = tab(sourceTabID),
              WebLinkActionPolicy.canSaveForLater(isPrivate: source.isPrivate),
              let targetURL = WebLinkActionPolicy.webURL(url) else {
            return
        }
        let rawURL = targetURL.absoluteString
        savedItems = LibraryPolicy.saveForLater(
            savedItems,
            url: rawURL,
            title: URLPolicy.displayHost(rawURL)
        )
        persistLibrary()
        flash("已加入稍后读")
    }

    func isCurrentPageSavedForLater() -> Bool {
        guard let tab = activeTab else {
            return false
        }
        return LibraryPolicy.isSavedForLater(savedItems, url: tab.url)
    }

    func removeHistoryEntry(_ id: String) {
        history.removeAll { $0.id == id }
        persistLibrary()
    }

    func removeHistory(forHost host: String) {
        history = LibraryPolicy.removeHistoryForHost(history, host: host)
        persistLibrary()
    }

    @discardableResult
    func importBookmarks(_ data: Data) throws -> Int {
        let imported = try BookmarkTransfer.parse(data)
        let result = LibraryPolicy.mergeSavedItems(savedItems, imported: imported)
        savedItems = result.items
        persistLibrary()
        return result.importedCount
    }

    func bookmarkExportHTML() -> String {
        BookmarkTransfer.export(savedItems)
    }

    func suggestions(for query: String) -> [AddressSuggestion] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let search = URLPolicy.looksLikeURL(trimmed)
            ? ""
            : URLPolicy.searchURL(
                trimmed,
                engine: settings.searchEngine,
                customTemplate: settings.customSearchTemplate
            )
        return LibraryPolicy.suggestions(
            query: query,
            history: history,
            savedItems: savedItems,
            searchSuggestionsEnabled: settings.searchSuggestionsEnabled && !URLPolicy.looksLikeURL(trimmed),
            searchURL: search
        )
    }

    func openLibrary(_ tab: LibraryTab) {
        libraryTab = tab
        showsLibrary = true
    }

    func openArticleLibrary(selecting articleID: String? = nil) {
        pendingArticleSelectionID = articleID
        showsArticles = true
    }

    func openSettings(_ section: SettingsSection? = nil) {
        settingsInitialSection = section
        showsSettings = true
    }

    func setSearchEngine(_ engine: SearchEngine) {
        settings.searchEngine = engine
        persistSettings()
    }

    func setCustomSearchTemplate(_ template: String) {
        settings.customSearchTemplate = BrowserSettings.normalizedSearchTemplate(template)
        persistSettings()
    }

    func setGesturesEnabled(_ enabled: Bool) {
        settings.gesturesEnabled = enabled
        persistSettings()
    }

    func setGestureActionsEnabled(_ enabled: Bool) {
        settings.gestureActionsEnabled = enabled
        persistSettings()
    }

    func setGestureTabSwitchEnabled(_ enabled: Bool) {
        settings.gestureTabSwitchEnabled = enabled
        persistSettings()
    }

    func setGestureBlockingEnabled(_ enabled: Bool) {
        settings.gestureBlockingEnabled = enabled
        persistSettings()
    }

    func setAutoHideToolbarEnabled(_ enabled: Bool) {
        settings.autoHideToolbarEnabled = enabled
        persistSettings()
    }

    func setTelemetryEnabled(_ enabled: Bool) {
        settings.telemetryEnabled = enabled
        persistSettings()
        TelemetryService.shared.syncConsent(
            consentAccepted: settings.privacyConsentAccepted,
            enabled: settings.telemetryEnabled
        )
    }

    func setSearchSuggestionsEnabled(_ enabled: Bool) {
        settings.searchSuggestionsEnabled = enabled
        persistSettings()
    }

    func acceptPrivacyConsent() {
        settings.privacyConsentAccepted = true
        persistSettings()
        TelemetryService.shared.syncConsent(
            consentAccepted: settings.privacyConsentAccepted,
            enabled: settings.telemetryEnabled
        )
        refreshSiteIcons()
    }

    func finishOnboarding() {
        settings.onboardingCompleted = true
        persistSettings()
        refreshHomeBackground()
    }

    func setAppearance(_ appearance: AppearanceMode) {
        settings.appearance = appearance
        persistSettings()
    }

    func setQuickSitesEnabled(_ enabled: Bool) {
        settings.quickSitesEnabled = enabled
        persistSettings()
    }

    func setQuickSiteLimit(_ limit: Int) {
        settings.quickSiteLimit = BrowserSettings.clampedQuickSiteLimit(limit)
        persistSettings()
        refreshSiteIcons()
    }

    func setHomeBackgroundStyle(_ style: HomeBackgroundStyle) {
        if style == .plain {
            settings.homeBackgroundEnabled = false
        } else {
            settings.homeBackgroundEnabled = true
            settings.homeBackgroundStyle = style.isBuiltIn ? .forest : style
        }
        persistSettings()
        refreshHomeBackground()
    }

    func setHomeBackgroundEnabled(_ enabled: Bool) {
        settings.homeBackgroundEnabled = enabled
        persistSettings()
        refreshHomeBackground()
    }

    func setHomePortraitPreset(_ preset: HomePortraitBackgroundPreset) {
        settings.homePortraitPreset = preset
        settings.homeBackgroundEnabled = true
        settings.homeBackgroundStyle = .forest
        persistSettings()
        refreshHomeBackground()
    }

    func setHomeLandscapePreset(_ preset: HomeLandscapeBackgroundPreset) {
        settings.homeLandscapePreset = preset
        settings.homeBackgroundEnabled = true
        settings.homeBackgroundStyle = .forest
        persistSettings()
        refreshHomeBackground()
    }

    func importCustomHomeBackground(_ data: Data) async {
        do {
            let normalized = try await Task.detached(priority: .userInitiated) {
                try HomeBackgroundService.importCustomImage(data)
            }.value
            homeBackgroundImage = UIImage(data: normalized)
            settings.homeBackgroundEnabled = true
            settings.homeBackgroundStyle = .custom
            persistSettings()
        } catch {
            flash("无法使用这张图片")
        }
    }

    func refreshHomeBackground() {
        guard settings.homeBackgroundEnabled else {
            homeBackgroundImage = nil
            isHomeBackgroundLoading = false
            return
        }
        let style = settings.homeBackgroundStyle
        if style != .daily && style != .custom {
            homeBackgroundImage = nil
            isHomeBackgroundLoading = false
            return
        }
        if let cached = HomeBackgroundService.cachedImageData(for: style) {
            homeBackgroundImage = UIImage(data: cached)
        } else {
            homeBackgroundImage = nil
        }
        guard BingDailyWallpaperPolicy.shouldRefresh(
            backgroundEnabled: settings.homeBackgroundEnabled,
            dailySelected: style == .daily,
            privacyConsentAccepted: settings.privacyConsentAccepted,
            onboardingCompleted: settings.onboardingCompleted
        ) else { return }
        isHomeBackgroundLoading = true
        Task { [weak self] in
            let data = await HomeBackgroundService.dailyImageData()
            guard let self,
                  self.settings.homeBackgroundEnabled,
                  self.settings.homeBackgroundStyle == .daily else { return }
            self.homeBackgroundImage = data.flatMap(UIImage.init(data:))
            self.isHomeBackgroundLoading = false
        }
    }

    func setTabExpiry(_ expiry: TabExpiry) {
        settings.tabExpiry = expiry
        persistSettings()
    }

    func setHistoryRetention(_ retention: HistoryRetention) {
        settings.historyRetention = retention
        history = LibraryPolicy.applyingHistoryRetention(
            history,
            retentionDays: retention.rawValue
        )
        persistSettings()
        persistLibrary()
    }

    func setLiveWebViewLimit(_ limit: Int) {
        settings.liveWebViewLimit = BrowserSettings.clampedLiveWebViewLimit(limit)
        trimLive()
        persistSettings()
    }

    func setTabSoftLimit(_ limit: Int) {
        settings.tabSoftLimit = BrowserSettings.clampedTabSoftLimit(limit)
        persistSettings()
    }

    func setDownloadConcurrency(_ limit: Int) {
        settings.downloadConcurrency = BrowserSettings.clampedDownloadConcurrency(limit)
        persistDownloadSettings()
    }

    func setLargeDownloadThresholdMB(_ threshold: Int) {
        settings.largeDownloadThresholdMB = BrowserSettings.clampedLargeDownloadThresholdMB(threshold)
        persistDownloadSettings()
    }

    func setWifiOnlyDownloads(_ enabled: Bool) {
        settings.wifiOnlyDownloads = enabled
        persistDownloadSettings()
    }

    func setDownloadNotificationsEnabled(_ enabled: Bool) {
        guard enabled else {
            settings.downloadNotificationsEnabled = false
            persistDownloadSettings()
            return
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.settings.downloadNotificationsEnabled = granted
                self.persistDownloadSettings()
                if !granted {
                    self.flash("未获得通知权限")
                }
            }
        }
    }

    func setClearCookiesOnTabClose(_ enabled: Bool) {
        settings.clearCookiesOnTabClose = enabled
        persistSettings()
    }

    func retryDownload(_ id: String) {
        downloads.retry(id, using: activeController?.webView)
    }

    func persistDownloadSettings() {
        downloads.configure(settings: settings)
        persistSettings()
    }

    @discardableResult
    func saveQuickSite(title: String, url: String, replacing: QuickSite? = nil) -> Bool {
        guard let site = QuickSitePolicy.normalized(title: title, url: url, replacing: replacing, in: quickSites) else {
            return false
        }
        quickSites = QuickSitePolicy.upsert(quickSites, site: site)
        persistQuickSites()
        refreshSiteIcons()
        return true
    }

    func removeQuickSite(_ id: String) {
        quickSites.removeAll { $0.id == id }
        persistQuickSites()
    }

    func moveQuickSites(from offsets: IndexSet, to destination: Int) {
        quickSites = QuickSitePolicy.move(quickSites, from: offsets, to: destination)
        persistQuickSites()
    }

    func moveVisibleQuickSite(_ id: String, to targetID: String) {
        let reordered = QuickSitePolicy.moveVisible(
            quickSites,
            fromID: id,
            toID: targetID,
            visibleLimit: settings.quickSiteLimit
        )
        guard reordered != quickSites else { return }
        quickSites = reordered
        persistQuickSites()
    }

    func siteIcon(for url: String) -> UIImage? {
        siteIcons[URLPolicy.rawHost(url)]
    }

    func siteIcon(for tab: BrowserTab) -> UIImage? {
        tab.isPrivate ? nil : siteIcon(for: tab.url)
    }

    func refreshSiteIcons() {
        guard settings.privacyConsentAccepted else { return }
        var requests = quickSites.prefix(settings.quickSiteLimit).map {
            SiteIconRequest(url: $0.url, isPrivate: false)
        }
        requests.append(contentsOf: tabs.map { SiteIconRequest(url: $0.url, isPrivate: $0.isPrivate) })
        for request in SiteIconPolicy.targets(requests) {
            requestSiteIcon(pageURL: request.url)
        }
    }

    func refreshSiteIcon(tabID: String, declaredURL: String) {
        guard settings.privacyConsentAccepted,
              let tab = tab(tabID),
              !tab.isPrivate,
              !URLPolicy.isHomeURL(tab.url) else {
            return
        }
        requestSiteIcon(pageURL: tab.url, declaredURL: declaredURL)
    }

    func requestSiteIcon(pageURL: String, declaredURL: String = "") {
        let host = URLPolicy.rawHost(pageURL)
        guard !host.isEmpty, siteIcons[host] == nil else { return }
        if siteIconLoadingHosts.contains(host) {
            if !declaredURL.isEmpty {
                deferredSiteIconRequests[host] = (pageURL, declaredURL)
            }
            return
        }
        siteIconLoadingHosts.insert(host)
        Task { [weak self] in
            let data = await SiteIconStore.shared.iconData(
                for: pageURL,
                declaredURL: declaredURL.isEmpty ? nil : declaredURL
            )
            guard let self else { return }
            self.siteIconLoadingHosts.remove(host)
            if let data, let image = SiteIconImage.decode(data) {
                self.setSiteIcon(image, forHost: host)
                self.deferredSiteIconRequests.removeValue(forKey: host)
                return
            }
            if let deferred = self.deferredSiteIconRequests.removeValue(forKey: host) {
                self.requestSiteIcon(pageURL: deferred.pageURL, declaredURL: deferred.declaredURL)
            }
        }
    }

    func consumeInboundShares() {
        guard isPrimaryWindow, settings.privacyConsentAccepted, settings.onboardingCompleted else { return }
        do {
            let pending = try InboundShareQueue.pending()
            var consumed = 0
            for request in pending {
                guard applyInboundShare(request) else { break }
                try InboundShareQueue.remove(request)
                consumed += 1
            }
            if consumed > 0 {
                flash("已处理 \(consumed) 个分享链接")
            }
        } catch {
            #if DEBUG
            print("Inbound share inbox unavailable: \(error)")
            #endif
        }
    }

    private func applyInboundShare(_ request: InboundShareRequest) -> Bool {
        if request.action.requiresPro, !pro.isPro {
            showsProPaywall = true
            flash("保存离线文章需要卓阅 Pro")
            return true
        }
        guard let tabID = createTab(isPrivate: request.action.usesPrivateTab) else {
            flash("标签页已达上限，分享链接仍保留在收件箱")
            return false
        }
        if request.action.opensDisposableReader {
            disposableReaderTabIDs.insert(tabID)
        }
        if request.action.shouldCaptureArticle {
            pendingArticleCaptureTabIDs.insert(tabID)
        }
        let target = request.action.targetURL(in: request)
        openInActiveTab(target)
        if !request.title.isEmpty {
            update(tabID: tabID) { tab in tab.title = request.title }
        }
        return true
    }

    func captureCurrentArticle() {
        captureArticle(tabID: activeTabID)
    }

    func importArticleURL(_ rawURL: String) {
        guard pro.isPro else {
            showsProPaywall = true
            flash("导入离线文章需要卓阅 Pro")
            return
        }
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard URLPolicy.looksLikeURL(trimmed) else {
            flash("请输入有效的网址")
            return
        }
        let normalized = URLPolicy.normalizeAddress(trimmed, engine: settings.searchEngine)
        guard let url = URL(string: normalized), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            flash("仅支持导入 http 或 https 网页")
            return
        }
        if let existing = articles.articles.first(where: { $0.canonicalUrl == normalized || $0.sourceUrl == normalized }),
           existing.quality != .failed, articles.hasContent(for: existing) {
            pendingArticleSelectionID = existing.id
            flash("文章已在离线库中")
            return
        }
        captureFromURL(normalized)
    }

    func retryArticleCapture(_ article: SavedArticle) {
        guard pro.isPro else {
            showsProPaywall = true
            flash("保存离线文章需要卓阅 Pro")
            return
        }
        captureFromURL(article.sourceUrl, existingArticleID: article.id)
    }

    func openArticleSource(_ article: SavedArticle) {
        showsArticles = false
        openInActiveTab(article.sourceUrl)
    }

    private func captureFromURL(_ urlString: String, existingArticleID: String? = nil) {
        guard let url = URL(string: urlString) else { return }
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: config)
        let token = UUID().uuidString
        importWebViews[token] = webView

        flash("正在载入并保存文章…")

        Task { @MainActor [weak self, weak webView] in
            guard let self, let webView else { return }
            defer {
                self.importWebViews.removeValue(forKey: token)
            }

            let request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 20)
            _ = webView.load(request)

            do {
                try? await Task.sleep(nanoseconds: 800_000_000)
                let snapshot = try await ArticleCapture.captureWithRetries(from: webView, timeoutSeconds: 15)
                let saved = try await self.articles.save(snapshot)
                self.pendingArticleSelectionID = saved.id
                let suffix = saved.quality == .partial ? "，部分图片未保存" : ""
                self.flash("已保存离线文章\(suffix)")
            } catch {
                if let existingID = existingArticleID,
                   let existing = self.articles.articles.first(where: { $0.id == existingID }),
                   existing.quality != .failed, self.articles.hasContent(for: existing) {
                    self.flash("重试失败，已保留原文章")
                } else {
                    let failureKind: ArticleSaveFailure = (error as? ArticleCaptureError)?.failureKind ?? .extractionUnavailable
                    _ = try? await self.articles.saveFailure(
                        id: existingArticleID,
                        url: urlString,
                        title: nil,
                        failure: failureKind,
                        message: error.localizedDescription
                    )
                    self.flash("保存失败: \(error.localizedDescription)")
                }
            }
        }
    }

    func captureArticle(tabID: String) {
        guard pro.isPro else {
            showsProPaywall = true
            flash("保存离线文章需要卓阅 Pro")
            return
        }
        guard let tab = tab(tabID) else { return }
        if tab.isPrivate {
            flash("无痕标签页无法保存离线文章")
            return
        }
        if URLPolicy.isHomeURL(tab.url) {
            return
        }
        guard let webView = controllers[tabID]?.webView else {
            return
        }
        let expectedURL = tab.url
        Task { [weak self, weak webView] in
            guard let self, let webView else { return }
            do {
                let snapshot = try await ArticleCapture.captureWithRetries(from: webView, timeoutSeconds: 8)
                guard PageStatePolicy.isSamePage(expectedURL, snapshot.sourceUrl) else {
                    _ = try? await self.articles.saveFailure(
                        url: expectedURL,
                        title: tab.title,
                        failure: .pageChanged,
                        message: "页面已变化，请重新保存"
                    )
                    self.flash("页面已变化，请重新保存")
                    return
                }
                let article = try await self.articles.save(snapshot)
                let suffix = article.quality == .partial ? "，部分图片未保存" : ""
                self.flash("已保存离线文章\(suffix)")
            } catch {
                let failureKind: ArticleSaveFailure = (error as? ArticleCaptureError)?.failureKind ?? .extractionUnavailable
                _ = try? await self.articles.saveFailure(
                    url: expectedURL,
                    title: tab.title,
                    failure: failureKind,
                    message: error.localizedDescription
                )
                self.flash(error.localizedDescription)
            }
        }
    }
}
