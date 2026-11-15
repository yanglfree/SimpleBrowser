import Foundation
import UIKit
import WebKit

extension BrowserSession {
    func toggleReader() {
        guard let current = activeTab, !URLPolicy.isHomeURL(current.url) else {
            return
        }
        if current.isReader {
            capturePageState(current.id)
            guard let controller = controllers[current.id] else {
                return
            }
            controller.exitReader { [weak self] in
                guard let self else {
                    return
                }
                self.update(tabID: current.id) { tab in
                    tab.isReader = false
                }
                if self.disposableReaderTabIDs.contains(current.id) {
                    self.closeTab(current.id)
                    return
                }
                self.restoreStoredScroll(tabID: current.id, promptIfActive: false)
                self.persist()
            }
            return
        }
        capturePageState(current.id)
        ensureLive(current.id)
        activeController?.applyReader(settings: readerSettings) { [weak self] ok in
            DispatchQueue.main.async {
                guard let self else {
                    return
                }
                if !ok {
                    self.flash("无法提取正文")
                    return
                }
                self.update(tabID: current.id) { tab in
                    tab.isReader = true
                }
                self.restoreStoredScroll(tabID: current.id, promptIfActive: true)
                self.persist()
            }
        }
    }

    func refreshReader() {
        guard activeTab?.isReader == true else {
            return
        }
        persistReaderSettings()
        activeController?.applyReader(settings: readerSettings) { _ in }
    }

    func applyUserAgentOnce(_ preference: UserAgentPreference) {
        guard let current = activeTab, !URLPolicy.isHomeURL(current.url) else {
            return
        }
        let next = preference == .desktop
        update(tabID: current.id) { tab in
            tab.isDesktop = next
            tab.isReader = false
        }
        ensureLive(current.id)
        activeController?.applyUserAgent(isDesktop: next)
        let target = next ? URLPolicy.desktopURL(for: current.url) : current.url
        activeController?.load(target, rewriteDesktop: next)
        persist()
    }

    func setSiteUserAgentPreference(_ preference: UserAgentPreference) {
        guard let current = activeTab else {
            return
        }
        let host = WebAppearancePolicy.host(for: current.url)
        guard !host.isEmpty else {
            return
        }
        settings.siteUserAgentPreferences.removeAll { $0.host == host }
        if preference != .default {
            settings.siteUserAgentPreferences.append(
                SiteUserAgentPreference(host: host, preference: preference)
            )
        }
        settings.siteUserAgentPreferences = WebAppearancePolicy.normalizedUserAgentPreferences(
            settings.siteUserAgentPreferences
        )
        persistSettings()
        applyResolvedUserAgentToActive()
    }

    func setDefaultUserAgentPreference(_ preference: UserAgentPreference) {
        settings.defaultUserAgentPreference = preference
        persistSettings()
        applyResolvedUserAgentToActive()
    }

    func resetUserAgentPreferences() {
        settings.defaultUserAgentPreference = .default
        settings.siteUserAgentPreferences = []
        persistSettings()
        applyResolvedUserAgentToActive()
    }

    func userAgentPreference(for rawURL: String) -> UserAgentPreference {
        WebAppearancePolicy.userAgentPreference(for: rawURL, settings: settings)
    }

    func siteUserAgentPreference(for rawURL: String) -> UserAgentPreference {
        let host = WebAppearancePolicy.host(for: rawURL)
        return settings.siteUserAgentPreferences.first(where: { $0.host == host })?.preference ?? .default
    }

    func setMinimumFontSize(_ size: Int) {
        settings.minimumFontSize = BrowserSettings.clampedMinimumFontSize(size)
        persistSettings()
        controllers.values.forEach { $0.applyWebAppearance() }
        activeController?.reload()
    }

    func setWebDarkMode(_ preference: WebDarkModePreference) {
        settings.webDarkMode = preference
        persistSettings()
        controllers.values.forEach { $0.applyWebAppearance() }
    }

    func isWebDarkModeExcluded(for rawURL: String) -> Bool {
        WebAppearancePolicy.isDarkModeExcluded(for: rawURL, settings: settings)
    }

    func setCurrentSiteDarkModeExcluded(_ excluded: Bool) {
        guard let current = activeTab else {
            return
        }
        let host = WebAppearancePolicy.host(for: current.url)
        guard !host.isEmpty else {
            return
        }
        settings.webDarkModeExcludedHosts.removeAll { $0 == host }
        if excluded {
            settings.webDarkModeExcludedHosts.append(host)
        }
        settings.webDarkModeExcludedHosts = WebAppearancePolicy.normalizedHosts(
            settings.webDarkModeExcludedHosts
        )
        persistSettings()
        activeController?.applyWebAppearance()
    }

    func zoomPercent(for rawURL: String) -> Int {
        WebAppearancePolicy.zoomPercent(for: rawURL, settings: settings)
    }

    func setCurrentSiteZoom(_ percent: Int) {
        guard let current = activeTab else {
            return
        }
        let host = WebAppearancePolicy.host(for: current.url)
        guard !host.isEmpty else {
            return
        }
        settings.siteZoomRatios.removeAll { $0.host == host }
        let clamped = WebAppearancePolicy.clampedZoomPercent(percent)
        if clamped != 100 {
            settings.siteZoomRatios.append(SiteZoomRatio(host: host, percent: clamped))
        }
        settings.siteZoomRatios = WebAppearancePolicy.normalizedZoomRatios(settings.siteZoomRatios)
        persistSettings()
        activeController?.applyWebAppearance()
    }

    private func applyResolvedUserAgentToActive() {
        guard let current = activeTab, !URLPolicy.isHomeURL(current.url) else {
            return
        }
        let usesDesktop = effectiveSiteControl(for: current.url).desktopUserAgentEnabled
        applyUserAgentOnce(usesDesktop ? .desktop : .mobile)
    }

    func beginFind() {
        guard let current = activeTab, !URLPolicy.isHomeURL(current.url) else {
            return
        }
        showsFind = true
    }

    func updateFindQuery(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            findCurrent = 0
            findTotal = 0
            return
        }
        ensureLive(activeTabID)
        activeController?.countMatches(trimmed) { [weak self] total in
            guard let self else {
                return
            }
            self.findTotal = total
            if total == 0 {
                self.findCurrent = 0
                return
            }
            self.activeController?.find(trimmed, backwards: false) { found in
                self.findCurrent = found ? 1 : 0
            }
        }
    }

    func findNext() {
        let trimmed = findQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard findTotal > 0, !trimmed.isEmpty else {
            return
        }
        activeController?.find(trimmed, backwards: false) { [weak self] found in
            guard let self, found else {
                return
            }
            self.findCurrent = self.findCurrent >= self.findTotal ? 1 : self.findCurrent + 1
        }
    }

    func findPrevious() {
        let trimmed = findQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard findTotal > 0, !trimmed.isEmpty else {
            return
        }
        activeController?.find(trimmed, backwards: true) { [weak self] found in
            guard let self, found else {
                return
            }
            self.findCurrent = self.findCurrent <= 1 ? self.findTotal : self.findCurrent - 1
        }
    }

    func endFind() {
        showsFind = false
        findQuery = ""
        findCurrent = 0
        findTotal = 0
    }

    func requestSitePermission(
        origin: String,
        kinds: [SitePermissionKind],
        persist: Bool,
        completion: @escaping (Bool) -> Void
    ) {
        if origin.isEmpty || kinds.isEmpty {
            completion(false)
            return
        }
        if permissionReply != nil {
            completion(false)
            return
        }
        let stored = persist ? sitePermissions.first(where: { $0.origin == origin }) : nil
        switch SitePermissionPolicy.decision(stored: stored, kinds: kinds) {
        case .allow:
            completion(true)
        case .deny:
            completion(false)
        case .prompt:
            permissionReply = completion
            permissionPrompt = PermissionPrompt(origin: origin, kinds: kinds, persist: persist)
        }
    }

    func allowPermission() {
        completePermission(true)
    }

    func denyPermission() {
        completePermission(false)
    }

    func denyPermissionIfPending() {
        if permissionReply != nil {
            completePermission(false)
        }
    }

    private func completePermission(_ allowed: Bool) {
        guard let prompt = permissionPrompt else {
            return
        }
        let reply = permissionReply
        permissionReply = nil
        permissionPrompt = nil
        if prompt.persist {
            sitePermissions = SitePermissionPolicy.apply(
                sitePermissions,
                origin: prompt.origin,
                kinds: prompt.kinds,
                decision: allowed ? .allow : .deny
            )
            persistSitePermissions()
        }
        reply?(allowed)
    }

    func removeSitePermission(_ origin: String) {
        sitePermissions.removeAll { $0.origin == origin }
        persistSitePermissions()
    }

    func toggleSitePermissionDecision(origin: String, kind: SitePermissionKind) {
        guard let stored = sitePermissions.first(where: { $0.origin == origin }) else {
            return
        }
        sitePermissions = SitePermissionPolicy.apply(
            sitePermissions,
            origin: origin,
            kinds: [kind],
            decision: SitePermissionPolicy.toggledDecision(from: stored.decision(for: kind))
        )
        persistSitePermissions()
    }

    func adsBlockEnabled(for url: String) -> Bool {
        let effective = BlockingPolicy.effectiveControl(for: url, settings: settings)
        return effective.networkBlockingEnabled && effective.trackerBlockingEnabled &&
            !AllowListPolicy.isHostAllowed(allowedHosts, URLPolicy.rawHost(url))
    }

    func effectiveSiteControl(for url: String) -> EffectiveSiteControl {
        BlockingPolicy.effectiveControl(for: url, settings: settings)
    }

    func isBlockingAllowListed(for url: String) -> Bool {
        AllowListPolicy.isHostAllowed(allowedHosts, URLPolicy.rawHost(url))
    }

    func currentSiteControl() -> SiteControl {
        BlockingPolicy.siteControl(for: activeTab?.url ?? "", controls: settings.siteControls)
    }

    func setCurrentSiteControl(_ control: SiteControl) {
        let host = URLPolicy.rawHost(activeTab?.url ?? "").lowercased()
        guard !host.isEmpty else { return }
        var normalized = control
        normalized.host = host
        settings.siteControls.removeAll { $0.host == host }
        if normalized.hasOverride {
            settings.siteControls.append(normalized)
        }
        settings.siteControls = BlockingPolicy.normalizedSiteControls(settings.siteControls)
        persistSettings()
        controllers.values.forEach { $0.applyContentBlocker() }
        if let current = activeTab, !URLPolicy.isHomeURL(current.url) {
            activeController?.applyWebAppearance(for: current.url)
            applyResolvedUserAgentToActive()
        } else {
            activeController?.reload()
        }
    }

    func setRuleStrength(_ strength: RuleStrength) {
        guard settings.ruleStrength != strength else { return }
        settings.ruleStrength = strength
        persistSettings()
        activeController?.reload()
    }

    func updateRemoteRules(manual: Bool = true) {
        guard !isRulesUpdating else { return }
        isRulesUpdating = true
        ContentBlocker.shared.updateRemoteRules(
            allowsExpensiveNetworkAccess: manual
        ) { [weak self] success, updatedAt in
            guard let self else { return }
            self.isRulesUpdating = false
            if success, let updatedAt {
                self.settings.rulesLastUpdatedAt = updatedAt.timeIntervalSince1970
                self.persistSettings()
                if manual { self.flash("拦截规则已更新") }
            } else if manual {
                self.flash("规则更新失败，已保留当前规则")
            }
        }
    }

    func recordObservedBlocking(
        tabID: String,
        url: String,
        stats: BlockStats,
        resources: [ObservedBlockResource] = []
    ) {
        guard stats.total > 0, PageStatePolicy.isSamePage(tab(tabID)?.url ?? "", url) else { return }
        var tabStats = tabBlockStats[tabID] ?? BlockStats()
        tabStats.add(stats)
        tabBlockStats[tabID] = tabStats
        let now = Date()
        let newEvents = BlockObservationPolicy.eventDrafts(stats: stats, resources: resources).map { draft in
            BlockEvent(
                id: UUID().uuidString,
                tabID: tabID,
                pageURL: url,
                category: draft.category,
                count: draft.count,
                occurredAt: now,
                resourceHost: draft.resourceHost,
                engine: draft.engine
            )
        }
        blockEvents.insert(contentsOf: newEvents, at: 0)
        blockEvents = Array(blockEvents.prefix(200))
        guard tab(tabID)?.isPrivate == false else { return }
        let host = URLPolicy.rawHost(url).lowercased()
        guard !host.isEmpty else { return }
        var entries = siteBlockStats
        if let index = entries.firstIndex(where: { $0.host == host }) {
            entries[index].stats.add(stats)
        } else {
            entries.append(SiteBlockStats(host: host, stats: stats))
        }
        siteBlockStats = BlockingPolicy.normalizedSiteStats(entries)
        persistSiteBlockStats()
    }

    func observedStatsForActiveTab() -> BlockStats {
        tabBlockStats[activeTabID] ?? BlockStats()
    }

    func observedStatsForCurrentSite() -> BlockStats {
        let host = URLPolicy.rawHost(activeTab?.url ?? "").lowercased()
        return siteBlockStats.first(where: { $0.host == host })?.stats ?? BlockStats()
    }

    func observedCumulativeStats() -> BlockStats {
        BlockingPolicy.cumulativeStats(siteBlockStats)
    }

    func observedEventsForActiveTab() -> [BlockEvent] {
        BlockEventPresentationPolicy.visibleEvents(blockEvents, tabID: activeTabID)
    }

    func resetObservedBlocking(tabID: String) {
        tabBlockStats[tabID] = BlockStats()
        blockEvents.removeAll { $0.tabID == tabID }
    }

    func applyAutomaticReaderIfNeeded(tabID: String) {
        guard let current = tab(tabID), !current.isReader,
              disposableReaderTabIDs.contains(tabID) || effectiveSiteControl(for: current.url).autoReaderEnabled,
              let controller = controllers[tabID] else { return }
        controller.applyReader(settings: readerSettings) { [weak self] success in
            guard let self else { return }
            guard success else {
                if self.disposableReaderTabIDs.contains(tabID) {
                    self.closeTab(tabID)
                }
                return
            }
            self.update(tabID: tabID) { $0.isReader = true }
            self.persist()
        }
    }

    func handleFinishedPageLoad(tabID: String) {
        if pendingArticleCaptureTabIDs.remove(tabID) != nil {
            captureArticle(tabID: tabID)
        }
        applyAutomaticReaderIfNeeded(tabID: tabID)
    }

    func isCurrentHostAllowed() -> Bool {
        guard let tab = activeTab else {
            return false
        }
        return AllowListPolicy.isHostAllowed(allowedHosts, URLPolicy.rawHost(tab.url))
    }

    func toggleCurrentHostAllowed() {
        guard let tab = activeTab, !URLPolicy.isHomeURL(tab.url) else {
            return
        }
        let host = URLPolicy.rawHost(tab.url)
        let allowed = !AllowListPolicy.isHostAllowed(allowedHosts, host)
        allowedHosts = AllowListPolicy.setHostAllowed(allowedHosts, host: host, allowed: allowed)
        persistAllowList()
        controllers.values.forEach { $0.applyContentBlocker() }
        activeController?.reload()
        flash(allowed ? "已允许此站点加载广告" : "已对此站点恢复拦截")
    }

    func removeAllowedHost(_ host: String) {
        allowedHosts = AllowListPolicy.setHostAllowed(allowedHosts, host: host, allowed: false)
        persistAllowList()
        controllers.values.forEach { $0.applyContentBlocker() }
        if let tab = activeTab, URLPolicy.rawHost(tab.url) == host {
            activeController?.reload()
        }
    }

    func setBlockAds(_ enabled: Bool) {
        settings.blockAds = enabled
        persistSettings()
        controllers.values.forEach { $0.applyContentBlocker() }
        activeController?.reload()
    }

    func shareCurrentPage() {
        guard let tab = activeTab, !URLPolicy.isHomeURL(tab.url) else {
            return
        }
        var items: [Any] = []
        if let url = URL(string: tab.url) {
            items.append(url)
        } else {
            items.append(tab.url)
        }
        if !tab.title.isEmpty {
            items.insert(tab.title, at: 0)
        }
        shareItems = items
        showsShare = true
    }

    func shareCurrentScreenshot() async {
        guard !isGeneratingScreenshot,
              let tab = activeTab,
              !URLPolicy.isHomeURL(tab.url),
              let controller = activeController else {
            return
        }
        let expectedTabID = tab.id
        let expectedURL = tab.url
        isGeneratingScreenshot = true
        defer { isGeneratingScreenshot = false }

        do {
            let result = try await controller.captureLongScreenshot()
            guard activeTabID == expectedTabID, activeTab?.url == expectedURL else {
                flash("页面已切换，截图未分享")
                return
            }
            shareItems = [result.image]
            if result.usedViewportFallback {
                flash("长截图生成失败，已改为分享当前画面")
            } else if result.wasTruncated {
                flash("页面过长，已生成前 40 屏")
            }
            showsShare = true
        } catch {
            flash("无法生成页面截图")
        }
    }

    func reportPageIssue() {
        guard let tab = activeTab, !URLPolicy.isHomeURL(tab.url) else { return }
        let bounds = activeController?.webView.window?.bounds ?? activeController?.webView.bounds ?? UIScreen.main.bounds
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        pageIssueDiagnostic = PageIssueDiagnostic.create(
            appVersion: "\(shortVersion) (\(build))",
            width: bounds.width,
            height: bounds.height,
            loadError: tab.loadError,
            events: observedEventsForActiveTab(),
            control: currentSiteControl()
        )
    }

    func copyPageIssueDiagnostic(_ diagnostic: PageIssueDiagnostic) {
        UIPasteboard.general.string = diagnostic.summary
        pageIssueDiagnostic = nil
        flash("诊断信息已复制")
    }

    func copyCurrentLink() {
        guard let tab = activeTab, !URLPolicy.isHomeURL(tab.displayAddressURL),
              let url = URL(string: tab.displayAddressURL) else {
            return
        }
        UIPasteboard.general.url = url
        flash("链接已复制")
    }

    func visitClipboardLink() {
        guard let value = UIPasteboard.general.string,
              let address = ExternalProtocolPolicy.clipboardAddress(from: value, engine: settings.searchEngine) else {
            flash("剪贴板中没有可访问的网页链接")
            return
        }
        openInActiveTab(address)
    }

    func handleExternalNavigation(_ rawURL: String, sourceURL: String) -> Bool {
        switch ExternalProtocolPolicy.decision(for: rawURL, sourceURL: sourceURL) {
        case .allow:
            return false
        case .blocked:
            flash("已阻止不安全的外部协议")
            return true
        case let .confirm(request):
            externalProtocolRequest = request
            return true
        }
    }

    func openExternalProtocol(_ request: ExternalProtocolRequest) {
        guard let url = URL(string: request.url) else {
            externalProtocolRequest = nil
            return
        }
        externalProtocolRequest = nil
        UIApplication.shared.open(url, options: [:]) { [weak self] opened in
            guard !opened else { return }
            DispatchQueue.main.async {
                self?.flash("没有可处理此链接的应用")
            }
        }
    }

    func cancelPendingExternalProtocol() {
        externalProtocolRequest = nil
    }

    func clearBrowsingData(_ selection: BrowsingDataSelection) {
        guard selection.hasSelection else {
            return
        }
        if selection.history {
            let cutoff = BrowsingPrivacyPolicy.cutoff(for: selection.range).timeIntervalSince1970
            history.removeAll { $0.visitedAt >= cutoff }
            persistLibrary()
        }
        if selection.permissions {
            allowedHosts = []
            sitePermissions = []
            settings.siteControls = []
            persistAllowList()
            persistSitePermissions()
            persistSettings()
            controllers.values.forEach { $0.applyContentBlocker() }
        }
        var dataTypes = Set<String>()
        if selection.cookies {
            dataTypes.formUnion(Self.cookieAndStorageDataTypes)
        }
        if selection.cache {
            dataTypes.formUnion(Self.cacheDataTypes)
        }
        guard !dataTypes.isEmpty else {
            flash("已清除所选浏览数据")
            return
        }
        let store = WKWebsiteDataStore.default()
        store.removeData(ofTypes: dataTypes, modifiedSince: .distantPast) {
            DispatchQueue.main.async {
                self.flash("已清除所选浏览数据")
            }
        }
    }

    func clearCurrentSiteData() {
        guard let tab = activeTab else { return }
        let host = URLPolicy.rawHost(tab.url)
        guard !host.isEmpty else { return }
        history = LibraryPolicy.removeHistoryForHost(history, host: host)
        allowedHosts.removeAll { $0.caseInsensitiveCompare(host) == .orderedSame }
        sitePermissions.removeAll { permission in
            guard let permissionHost = URL(string: permission.origin)?.host else { return false }
            return permissionHost.caseInsensitiveCompare(host) == .orderedSame
        }
        settings.siteControls.removeAll { $0.host == host.lowercased() }
        siteBlockStats.removeAll { $0.host == host.lowercased() }
        persistLibrary()
        persistAllowList()
        persistSitePermissions()
        persistSettings()
        persistSiteBlockStats()
        controllers.values.forEach { $0.applyContentBlocker() }

        let store = WKWebsiteDataStore.default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        store.fetchDataRecords(ofTypes: types) { records in
            let matching = records.filter {
                BrowsingPrivacyPolicy.recordDisplayName($0.displayName, matches: host)
            }
            store.removeData(ofTypes: types, for: matching) {
                DispatchQueue.main.async {
                    self.activeController?.reload()
                    self.showsSecurityPanel = false
                    self.flash("已清除 \(host) 的站点数据")
                }
            }
        }
    }

    func openSecurityPanel() {
        guard let tab = activeTab, !URLPolicy.isHomeURL(tab.url) else { return }
        showsSecurityPanel = true
    }

    func handlePasswordFocus(tabID: String, url: String) {
        guard tabID == activeTabID,
              PageStatePolicy.isSamePage(tab(tabID)?.url ?? "", url),
              SiteSecurityPolicy.shouldWarnForPasswordFocus(on: url) else {
            return
        }
        securityWarning = SiteSecurityWarning(host: URLPolicy.displayHost(url))
    }

    func clearCookies() {
        WKWebsiteDataStore.default().removeData(
            ofTypes: [WKWebsiteDataTypeCookies],
            modifiedSince: .distantPast
        ) {}
    }
}
