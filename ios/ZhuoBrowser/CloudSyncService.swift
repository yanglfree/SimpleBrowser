import Foundation

enum CloudSyncEngine {
    static let tombstoneRetentionSeconds: TimeInterval = 60 * 24 * 3600

    static func normalizeComparableURL(_ url: String) -> String {
        var trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") && trimmed.count > 1 {
            trimmed.removeLast()
        }
        return trimmed.lowercased()
    }

    static func normalizeSeconds(_ raw: Double?, fallback: TimeInterval) -> TimeInterval {
        guard let raw, raw.isFinite, raw > 0 else { return fallback }
        return raw >= 10_000_000_000 ? raw / 1000.0 : raw
    }

    static func mergeBookmarks(
        localFolders: [BookmarkFolder],
        localItems: [SavedItem],
        localTombstones: [BookmarkTombstone],
        remoteFolders: [BookmarkFolder],
        remoteItems: [SavedItem],
        remoteTombstones: [BookmarkTombstone],
        now: TimeInterval = Date().timeIntervalSince1970
    ) -> (folders: [BookmarkFolder], items: [SavedItem], tombstones: [BookmarkTombstone]) {
        let cutoff = now - tombstoneRetentionSeconds
        var tbMap: [String: BookmarkTombstone] = [:]
        for tb in (localTombstones + remoteTombstones) where tb.deletedAt >= cutoff {
            let key = tb.isFolder
                ? "f:\(tb.id)"
                : (tb.url.map { "u:\(normalizeComparableURL($0))" } ?? "b:\(tb.id)")
            if let existing = tbMap[key] {
                if tb.deletedAt > existing.deletedAt { tbMap[key] = tb }
            } else {
                tbMap[key] = tb
            }
        }

        var deletedFolders: [String: TimeInterval] = [:]
        var deletedUrls: [String: TimeInterval] = [:]
        var deletedIds: [String: TimeInterval] = [:]
        for tb in tbMap.values {
            if tb.isFolder {
                deletedFolders[tb.id] = max(deletedFolders[tb.id] ?? 0, tb.deletedAt)
            } else {
                deletedIds[tb.id] = max(deletedIds[tb.id] ?? 0, tb.deletedAt)
                if let url = tb.url, !url.isEmpty {
                    let norm = normalizeComparableURL(url)
                    deletedUrls[norm] = max(deletedUrls[norm] ?? 0, tb.deletedAt)
                }
            }
        }

        var folderMap: [String: BookmarkFolder] = [:]
        for folder in localFolders + remoteFolders {
            if let del = deletedFolders[folder.id], del >= folder.updatedAt { continue }
            if let existing = folderMap[folder.id] {
                if folder.updatedAt > existing.updatedAt { folderMap[folder.id] = folder }
            } else {
                folderMap[folder.id] = folder
            }
        }
        let mergedFolders = folderMap.values.sorted {
            $0.sortOrder != $1.sortOrder ? $0.sortOrder < $1.sortOrder : $0.createdAt < $1.createdAt
        }
        let validFolderIDs = Set(mergedFolders.map(\.id))

        var itemMap: [String: SavedItem] = [:]
        for rawItem in localItems + remoteItems {
            let norm = normalizeComparableURL(rawItem.url)
            guard !norm.isEmpty else { continue }
            if let del = deletedUrls[norm], del >= rawItem.updatedAt { continue }
            if let del = deletedIds[rawItem.id], del >= rawItem.updatedAt { continue }
            var item = rawItem
            if let fid = item.folderID, !validFolderIDs.contains(fid) {
                item.folderID = nil
                item.isPinnedToStartPage = true
            }
            if let existing = itemMap[norm] {
                if item.updatedAt > existing.updatedAt { itemMap[norm] = item }
            } else {
                itemMap[norm] = item
            }
        }
        let mergedItems = Array(itemMap.values).sorted { $0.updatedAt > $1.updatedAt }

        let activeTombstones = tbMap.values.filter { tb in
            if tb.isFolder {
                if let f = folderMap[tb.id], f.updatedAt > tb.deletedAt { return false }
                return true
            }
            if let url = tb.url, let i = itemMap[normalizeComparableURL(url)], i.updatedAt > tb.deletedAt {
                return false
            }
            if let i = mergedItems.first(where: { $0.id == tb.id }), i.updatedAt > tb.deletedAt {
                return false
            }
            return true
        }

        return (mergedFolders, mergedItems, Array(activeTombstones))
    }

    static func encodeBookmarksPayload(
        folders: [BookmarkFolder],
        items: [SavedItem],
        tombstones: [BookmarkTombstone],
        now: TimeInterval = Date().timeIntervalSince1970
    ) -> [String: Any] {
        [
            "version": 3,
            "folders": folders.map { f in
                [
                    "id": f.id,
                    "name": f.name,
                    "iconName": f.iconName,
                    "createdAt": Int64((f.createdAt * 1000).rounded()),
                    "updatedAt": Int64((f.updatedAt * 1000).rounded()),
                    "sortOrder": f.sortOrder,
                    "isPinnedToStartPage": f.isPinnedToStartPage
                ]
            },
            "items": items.map { item -> [String: Any] in
                var dict: [String: Any] = [
                    "id": item.id,
                    "title": item.title,
                    "url": item.url,
                    "createdAt": Int64((item.createdAt * 1000).rounded()),
                    "updatedAt": Int64((item.updatedAt * 1000).rounded()),
                    "isRead": item.isRead,
                    "tags": item.tags,
                    "isPinnedToStartPage": item.isPinnedToStartPage,
                    "sortOrder": item.sortOrder
                ]
                if let folderID = item.folderID {
                    dict["folderId"] = folderID
                    dict["folderID"] = folderID
                }
                return dict
            },
            "tombstones": tombstones.map { tb -> [String: Any] in
                var dict: [String: Any] = [
                    "id": tb.id,
                    "isFolder": tb.isFolder,
                    "deletedAt": Int64((tb.deletedAt * 1000).rounded())
                ]
                if let url = tb.url { dict["url"] = url }
                return dict
            },
            "updatedAt": Int64((now * 1000).rounded())
        ]
    }

    static func parseBookmarksPayload(
        _ raw: Any?
    ) -> (folders: [BookmarkFolder], items: [SavedItem], tombstones: [BookmarkTombstone]) {
        guard let dict = raw as? [String: Any] else { return ([], [], []) }
        let fallback = Date().timeIntervalSince1970

        let folders: [BookmarkFolder] = (dict["folders"] as? [[String: Any]] ?? []).compactMap { fd in
            guard let id = fd["id"] as? String, let name = fd["name"] as? String else { return nil }
            let created = normalizeSeconds((fd["createdAt"] as? NSNumber)?.doubleValue, fallback: fallback)
            let updated = normalizeSeconds((fd["updatedAt"] as? NSNumber)?.doubleValue, fallback: created)
            return BookmarkFolder(
                id: id,
                name: name,
                iconName: fd["iconName"] as? String ?? "folder.fill",
                createdAt: created,
                updatedAt: updated,
                sortOrder: (fd["sortOrder"] as? NSNumber)?.intValue ?? 0,
                isPinnedToStartPage: fd["isPinnedToStartPage"] as? Bool ?? true
            )
        }

        let rawItems = (dict["items"] as? [[String: Any]]) ?? (dict["entries"] as? [[String: Any]]) ?? []
        let items: [SavedItem] = rawItems.compactMap { bd in
            guard let url = bd["url"] as? String, !url.isEmpty else { return nil }
            let created = normalizeSeconds((bd["createdAt"] as? NSNumber)?.doubleValue, fallback: fallback)
            let updated = normalizeSeconds((bd["updatedAt"] as? NSNumber)?.doubleValue, fallback: created)
            return SavedItem(
                id: bd["id"] as? String ?? UUID().uuidString,
                title: bd["title"] as? String ?? url,
                url: url,
                folderID: (bd["folderId"] as? String) ?? (bd["folderID"] as? String),
                createdAt: created,
                updatedAt: updated,
                isRead: bd["isRead"] as? Bool ?? true,
                tags: bd["tags"] as? [String] ?? [],
                isPinnedToStartPage: bd["isPinnedToStartPage"] as? Bool ?? false,
                sortOrder: (bd["sortOrder"] as? NSNumber)?.intValue ?? 0
            )
        }

        let tombstones: [BookmarkTombstone] = (dict["tombstones"] as? [[String: Any]] ?? []).compactMap { td in
            guard let id = td["id"] as? String else { return nil }
            return BookmarkTombstone(
                id: id,
                url: td["url"] as? String,
                isFolder: td["isFolder"] as? Bool ?? false,
                deletedAt: normalizeSeconds((td["deletedAt"] as? NSNumber)?.doubleValue, fallback: fallback)
            )
        }

        return (folders, items, tombstones)
    }

    static func mergeSiteControls(
        local: [SiteControl],
        remote: [SiteControl]
    ) -> [SiteControl] {
        var map: [String: SiteControl] = [:]
        for item in local {
            map[item.host.lowercased()] = item
        }
        for item in remote {
            let key = item.host.lowercased()
            if map[key] == nil || item.hasOverride {
                map[key] = item
            }
        }
        return BlockingPolicy.normalizedSiteControls(Array(map.values))
    }

    static func mergeArticlesMetadata(
        local: [SavedArticle],
        remoteDicts: [[String: Any]],
        tombstones: [ArticleTombstone]
    ) -> [SavedArticle] {
        let deletedIDs = Set(tombstones.map(\.id))
        var map: [String: SavedArticle] = [:]
        for art in local where !deletedIDs.contains(art.id) {
            map[normalizeComparableURL(art.canonicalUrl.isEmpty ? art.sourceUrl : art.canonicalUrl)] = art
        }
        for rd in remoteDicts {
            guard let id = rd["id"] as? String, !deletedIDs.contains(id),
                  let sourceUrl = rd["sourceUrl"] as? String else { continue }
            let canonicalUrl = (rd["canonicalUrl"] as? String) ?? sourceUrl
            let key = normalizeComparableURL(canonicalUrl)
            let created = normalizeSeconds((rd["createdAt"] as? NSNumber)?.doubleValue, fallback: Date().timeIntervalSince1970)
            let updated = normalizeSeconds((rd["updatedAt"] as? NSNumber)?.doubleValue, fallback: created)
            let readingPosition = (rd["readingPosition"] as? NSNumber)?.doubleValue ?? 0

            let highlights: [ArticleHighlight] = (rd["highlights"] as? [[String: Any]] ?? []).compactMap { hd in
                guard let hid = hd["id"] as? String, let quote = hd["quote"] as? String else { return nil }
                return ArticleHighlight(
                    id: hid,
                    quote: quote,
                    prefix: hd["prefixContext"] as? String ?? "",
                    suffix: hd["suffixContext"] as? String ?? "",
                    createdAt: normalizeSeconds((hd["createdAt"] as? NSNumber)?.doubleValue, fallback: created)
                )
            }

            let notes: [ArticleNote] = (rd["notes"] as? [[String: Any]] ?? []).compactMap { nd in
                guard let nid = nd["id"] as? String, let text = nd["content"] as? String else { return nil }
                let nc = normalizeSeconds((nd["createdAt"] as? NSNumber)?.doubleValue, fallback: created)
                let nu = normalizeSeconds((nd["updatedAt"] as? NSNumber)?.doubleValue, fallback: nc)
                return ArticleNote(id: nid, text: text, createdAt: nc, updatedAt: nu)
            }

            if var existing = map[key] {
                if updated > existing.updatedAt {
                    existing.readingPosition = max(existing.readingPosition, readingPosition)
                    existing.updatedAt = updated
                    existing.archived = (rd["isArchived"] as? Bool) ?? existing.archived
                }
                let existingH = Set(existing.highlights.map(\.id))
                existing.highlights.append(contentsOf: highlights.filter { !existingH.contains($0.id) })
                let existingN = Set(existing.notes.map(\.id))
                existing.notes.append(contentsOf: notes.filter { !existingN.contains($0.id) })
                map[key] = existing
            } else {
                map[key] = SavedArticle(
                    id: id,
                    sourceUrl: sourceUrl,
                    canonicalUrl: canonicalUrl,
                    title: rd["title"] as? String ?? sourceUrl,
                    author: rd["author"] as? String ?? "",
                    excerpt: rd["excerpt"] as? String ?? "",
                    searchText: rd["excerpt"] as? String ?? "",
                    createdAt: created,
                    updatedAt: updated,
                    readingPosition: readingPosition,
                    tags: rd["tags"] as? [String] ?? [],
                    topics: rd["topics"] as? [String] ?? [],
                    notes: notes,
                    highlights: highlights,
                    archived: rd["isArchived"] as? Bool ?? false,
                    quality: ArticleQuality(rawValue: rd["quality"] as? String ?? "") ?? .partial
                )
            }
        }
        return Array(map.values).sorted { $0.updatedAt > $1.updatedAt }
    }
}

@MainActor
final class CloudSyncService {
    static let shared = CloudSyncService()

    private init() {}

    func sync(session: BrowserSession) async {
        let account = AccountService.shared
        guard account.isLoggedIn, let token = account.token else { return }

        account.updateSyncState(syncing: true, error: nil)
        defer { account.updateSyncState(syncing: false, error: account.syncErrorMessage) }

        let encodedDevice = account.deviceId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? account.deviceId
        let includeArticles = session.pro.isPro
        let scopesQuery = includeArticles
            ? "bookmarks,settings,site_controls,device_tabs,articles_meta"
            : "bookmarks,settings,site_controls,device_tabs"

        var remoteFolders: [BookmarkFolder] = []
        var remoteItems: [SavedItem] = []
        var remoteTombstones: [BookmarkTombstone] = []
        var remoteSiteControls: [SiteControl] = []
        var remoteArticleDicts: [[String: Any]] = []
        var remoteSettings: [String: Any]?
        var remoteDevices: [RemoteDeviceTabGroup] = []

        var baseVersions = account.scopeVersions

        do {
            let (data, http) = try await account.dataWithFallback { base in
                guard let url = URL(string: "\(base)/api/sync/v3/pull?scopes=\(scopesQuery)&excludeDeviceId=\(encodedDevice)") else { return nil }
                var req = URLRequest(url: url, timeoutInterval: 20)
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                return req
            }
            if http.statusCode == 401 || http.statusCode == 403 {
                account.logout()
                account.updateSyncState(error: "登录已过期，请重新登录")
                return
            }
            guard http.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                account.updateSyncState(error: "拉取云端数据失败 (HTTP \(http.statusCode))")
                return
            }

            if let scopes = json["scopes"] as? [String: Any] {
                if let bm = scopes["bookmarks"] as? [String: Any] {
                    baseVersions["bookmarks"] = (bm["version"] as? NSNumber)?.intValue ?? 0
                    let parsed = CloudSyncEngine.parseBookmarksPayload(bm["payload"])
                    remoteFolders = parsed.folders
                    remoteItems = parsed.items
                    remoteTombstones = parsed.tombstones
                }
                if let st = scopes["settings"] as? [String: Any] {
                    baseVersions["settings"] = (st["version"] as? NSNumber)?.intValue ?? 0
                    remoteSettings = st["payload"] as? [String: Any]
                }
                if let sc = scopes["site_controls"] as? [String: Any] {
                    baseVersions["site_controls"] = (sc["version"] as? NSNumber)?.intValue ?? 0
                    if let payload = sc["payload"] as? [String: Any],
                       let list = payload["controls"] as? [[String: Any]] {
                        remoteSiteControls = list.compactMap { row in
                            guard let host = row["host"] as? String else { return nil }
                            return SiteControl(
                                host: host,
                                networkBlocking: SiteControlMode(rawValue: (row["networkBlocking"] as? NSNumber)?.intValue ?? 0) ?? .inherit,
                                trackerBlocking: SiteControlMode(rawValue: (row["trackerBlocking"] as? NSNumber)?.intValue ?? 0) ?? .inherit,
                                cosmeticCleanup: SiteControlMode(rawValue: (row["cosmeticCleanup"] as? NSNumber)?.intValue ?? 0) ?? .inherit,
                                autoReader: SiteControlMode(rawValue: (row["autoReader"] as? NSNumber)?.intValue ?? 0) ?? .inherit,
                                darkMode: SiteControlMode(rawValue: (row["darkMode"] as? NSNumber)?.intValue ?? 0) ?? .inherit,
                                desktopUserAgent: SiteControlMode(rawValue: (row["desktopUserAgent"] as? NSNumber)?.intValue ?? 0) ?? .inherit
                            )
                        }
                    }
                }
                if includeArticles, let am = scopes["articles_meta"] as? [String: Any] {
                    baseVersions["articles_meta"] = (am["version"] as? NSNumber)?.intValue ?? 0
                    if let payload = am["payload"] as? [String: Any] {
                        remoteArticleDicts = payload["articles"] as? [[String: Any]] ?? []
                    }
                }
            }

            if let rawDevices = json["remoteDevices"] as? [[String: Any]],
               let devData = try? JSONSerialization.data(withJSONObject: rawDevices),
               let decoded = try? JSONDecoder().decode([RemoteDeviceTabGroup].self, from: devData) {
                remoteDevices = decoded
            }
        } catch {
            account.updateSyncState(error: "同步拉取失败：\(error.localizedDescription)")
            return
        }

        // Merge locally and push with CAS retry
        for _ in 0..<3 {
            let mergedBookmarks = CloudSyncEngine.mergeBookmarks(
                localFolders: session.bookmarkFolders,
                localItems: session.savedItems,
                localTombstones: session.bookmarkTombstones,
                remoteFolders: remoteFolders,
                remoteItems: remoteItems,
                remoteTombstones: remoteTombstones
            )
            session.applyCloudBookmarkMerge(
                folders: mergedBookmarks.folders,
                items: mergedBookmarks.items,
                tombstones: mergedBookmarks.tombstones
            )

            if !remoteSiteControls.isEmpty {
                session.settings.siteControls = CloudSyncEngine.mergeSiteControls(
                    local: session.settings.siteControls,
                    remote: remoteSiteControls
                )
                session.persistSettings()
            }

            if let remoteSettings {
                applyCrossPlatformSettings(remoteSettings, session: session)
            }

            let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
            var pushScopes: [String: Any] = [
                "bookmarks": [
                    "baseVersion": baseVersions["bookmarks"] ?? 0,
                    "encryptionMode": "none",
                    "payload": CloudSyncEngine.encodeBookmarksPayload(
                        folders: session.bookmarkFolders,
                        items: session.savedItems,
                        tombstones: session.bookmarkTombstones
                    )
                ],
                "settings": [
                    "baseVersion": baseVersions["settings"] ?? 0,
                    "encryptionMode": "none",
                    "payload": encodeCrossPlatformSettings(session: session, nowMs: nowMs)
                ],
                "site_controls": [
                    "baseVersion": baseVersions["site_controls"] ?? 0,
                    "encryptionMode": "none",
                    "payload": [
                        "controls": session.settings.siteControls.map { c -> [String: Any] in
                            [
                                "host": c.host,
                                "networkBlocking": c.networkBlocking.rawValue,
                                "trackerBlocking": c.trackerBlocking.rawValue,
                                "cosmeticCleanup": c.cosmeticCleanup.rawValue,
                                "autoReader": c.autoReader.rawValue,
                                "darkMode": c.darkMode.rawValue,
                                "desktopUserAgent": c.desktopUserAgent.rawValue,
                                "updatedAt": nowMs
                            ]
                        },
                        "tombstones": [],
                        "updatedAt": nowMs
                    ]
                ]
            ]

            if includeArticles {
                let mergedArticles = CloudSyncEngine.mergeArticlesMetadata(
                    local: session.articles.articles,
                    remoteDicts: remoteArticleDicts,
                    tombstones: session.articleTombstones
                )
                session.articles.replaceArticlesFromSync(mergedArticles)
                pushScopes["articles_meta"] = [
                    "baseVersion": baseVersions["articles_meta"] ?? 0,
                    "encryptionMode": "none",
                    "payload": encodeArticlesMeta(mergedArticles, tombstones: session.articleTombstones, nowMs: nowMs)
                ]
            }

            let pushBody: [String: Any] = [
                "deviceId": account.deviceId,
                "deviceName": account.deviceName,
                "platform": "ios",
                "scopes": pushScopes,
                "deviceTabs": RegionAuthPolicy.sanitizeDeviceTabs(session.tabs)
            ]

            guard let bodyData = try? JSONSerialization.data(withJSONObject: pushBody) else { return }
            do {
                let (data, http) = try await account.dataWithFallback { base in
                    guard let url = URL(string: "\(base)/api/sync/v3/push") else { return nil }
                    var req = URLRequest(url: url, timeoutInterval: 20)
                    req.httpMethod = "POST"
                    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.httpBody = bodyData
                    return req
                }
                let respJson = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
                if let applied = respJson["appliedScopes"] as? [String: [String: Any]] {
                    for (scope, info) in applied {
                        if let v = (info["version"] as? NSNumber)?.intValue {
                            baseVersions[scope] = v
                        }
                    }
                }
                if http.statusCode == 409, let conflicts = respJson["conflicts"] as? [[String: Any]] {
                    for c in conflicts {
                        guard let scope = c["scope"] as? String else { continue }
                        baseVersions[scope] = (c["currentVersion"] as? NSNumber)?.intValue ?? 0
                        if scope == "bookmarks" {
                            let parsed = CloudSyncEngine.parseBookmarksPayload(c["currentPayload"])
                            remoteFolders = parsed.folders
                            remoteItems = parsed.items
                            remoteTombstones = parsed.tombstones
                        } else if scope == "settings" {
                            remoteSettings = c["currentPayload"] as? [String: Any]
                        } else if scope == "articles_meta",
                                  let payload = c["currentPayload"] as? [String: Any] {
                            remoteArticleDicts = payload["articles"] as? [[String: Any]] ?? []
                        }
                    }
                    continue
                }
                guard http.statusCode == 200 else {
                    account.updateSyncState(error: "云端推送失败 (HTTP \(http.statusCode))")
                    return
                }
                account.scopeVersions = baseVersions
                if includeArticles {
                    await syncArticleBundles(session: session, account: account, token: token)
                }
                account.updateSyncState(remoteTabs: remoteDevices, error: nil, syncedNow: true)
                return
            } catch {
                account.updateSyncState(error: "同步推送失败：\(error.localizedDescription)")
                return
            }
        }
    }

    private func syncArticleBundles(session: BrowserSession, account: AccountService, token: String) async {
        var uploaded = 0
        for article in session.articles.articles where !article.isFailed {
            if session.articles.hasContent(for: article) {
                guard uploaded < 5, let bundle = session.articles.readLocalBundle(for: article) else { continue }
                let safeId = article.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? article.id
                guard let payload = try? JSONSerialization.data(withJSONObject: [
                    "html": bundle.html,
                    "markdown": bundle.markdown,
                    "text": bundle.text
                ]) else { continue }
                _ = try? await account.dataWithFallback { base in
                    guard let url = URL(string: "\(base)/api/sync/v3/articles/\(safeId)/bundle") else { return nil }
                    var req = URLRequest(url: url, timeoutInterval: 20)
                    req.httpMethod = "PUT"
                    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.httpBody = payload
                    return req
                }
                uploaded += 1
            } else {
                let safeId = article.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? article.id
                guard let (data, http) = try? await account.dataWithFallback(buildRequest: { base in
                    guard let url = URL(string: "\(base)/api/sync/v3/articles/\(safeId)/bundle") else { return nil }
                    var req = URLRequest(url: url, timeoutInterval: 20)
                    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    return req
                }), http.statusCode == 200,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let html = json["html"] as? String, !html.isEmpty else { continue }
                let markdown = json["markdown"] as? String ?? ""
                let text = json["text"] as? String ?? article.searchText
                session.articles.writeSyncedBundle(for: article.id, html: html, markdown: markdown, text: text)
            }
        }
    }

    private func applyCrossPlatformSettings(_ dict: [String: Any], session: BrowserSession) {
        if let blockAds = dict["blockAds"] as? Bool {
            session.settings.blockAds = blockAds
        }
        if let strengthInt = dict["ruleStrength"] as? Int,
           let strength = RuleStrength(rawValue: strengthInt) {
            session.settings.ruleStrength = strength
        }
        if let engineRaw = dict["searchEngine"] as? String {
            switch engineRaw.lowercased() {
            case "bing": session.settings.searchEngine = .bing
            case "baidu": session.settings.searchEngine = .baidu
            case "google": session.settings.searchEngine = .google
            case "duckduckgo": session.settings.searchEngine = .duckDuckGo
            default: break
            }
        } else if let engineInt = dict["searchEngine"] as? Int,
                  let engine = SearchEngine(rawValue: engineInt) {
            session.settings.searchEngine = engine
        }
        if let customTemplate = dict["customSearchTemplate"] as? String {
            session.settings.customSearchTemplate = customTemplate
        }
        if let suggestions = dict["searchSuggestionsEnabled"] as? Bool {
            session.settings.searchSuggestionsEnabled = suggestions
        }
        if let appearanceInt = dict["appearance"] as? Int,
           let appearance = AppearanceMode(rawValue: appearanceInt) {
            session.settings.appearance = appearance
        }
        if let webDarkInt = dict["webDarkMode"] as? Int,
           let webDark = WebDarkModePreference(rawValue: webDarkInt) {
            session.settings.webDarkMode = webDark
        }
        if let excluded = dict["webDarkModeExcludedHosts"] as? [String] {
            session.settings.webDarkModeExcludedHosts = excluded
        }
        if let minFont = dict["minimumFontSize"] as? Int {
            session.settings.minimumFontSize = minFont
        }
        if let readerFont = dict["readerFontSize"] as? Int {
            session.readerSettings.fontSize = readerFont
        }
        if let readerLine = dict["readerLineHeight"] as? Int {
            session.readerSettings.lineHeightIndex = readerLine
        }
        if let paperInt = dict["readerPaper"] as? Int,
           let paper = ReaderPaper(rawValue: paperInt) {
            session.readerSettings.paper = paper
        }
        session.persistSettings()
        session.persistReaderSettings()
    }

    private func encodeCrossPlatformSettings(session: BrowserSession, nowMs: Int64) -> [String: Any] {
        [
            "blockAds": session.settings.blockAds,
            "ruleStrength": session.settings.ruleStrength.rawValue,
            "searchEngine": session.settings.searchEngine.rawValue,
            "customSearchTemplate": session.settings.customSearchTemplate,
            "searchSuggestionsEnabled": session.settings.searchSuggestionsEnabled,
            "appearance": session.settings.appearance.rawValue,
            "webDarkMode": session.settings.webDarkMode.rawValue,
            "webDarkModeExcludedHosts": session.settings.webDarkModeExcludedHosts,
            "minimumFontSize": session.settings.minimumFontSize,
            "readerFontSize": session.readerSettings.fontSize,
            "readerLineHeight": session.readerSettings.lineHeightIndex,
            "readerPaper": session.readerSettings.paper.rawValue,
            "updatedAt": nowMs
        ]
    }

    private func encodeArticlesMeta(_ articles: [SavedArticle], tombstones: [ArticleTombstone], nowMs: Int64) -> [String: Any] {
        [
            "articles": articles.filter { !$0.isFailed }.map { art -> [String: Any] in
                [
                    "id": art.id,
                    "sourceUrl": art.sourceUrl,
                    "canonicalUrl": art.canonicalUrl,
                    "title": art.title,
                    "author": art.author,
                    "excerpt": art.excerpt,
                    "createdAt": Int64((art.createdAt * 1000).rounded()),
                    "updatedAt": Int64((art.updatedAt * 1000).rounded()),
                    "readingPosition": art.readingPosition,
                    "tags": art.tags,
                    "topics": art.topics,
                    "isArchived": art.archived,
                    "quality": art.quality.rawValue,
                    "highlights": art.highlights.map { h in
                        [
                            "id": h.id,
                            "quote": h.quote,
                            "prefixContext": h.prefix,
                            "suffixContext": h.suffix,
                            "color": "yellow",
                            "createdAt": Int64((h.createdAt * 1000).rounded()),
                            "updatedAt": Int64((h.createdAt * 1000).rounded())
                        ]
                    },
                    "notes": art.notes.map { n in
                        [
                            "id": n.id,
                            "content": n.text,
                            "createdAt": Int64((n.createdAt * 1000).rounded()),
                            "updatedAt": Int64((n.updatedAt * 1000).rounded())
                        ]
                    }
                ]
            },
            "tombstones": tombstones.map { tb -> [String: Any] in
                var dict: [String: Any] = [
                    "id": tb.id,
                    "deletedAt": Int64((tb.deletedAt * 1000).rounded())
                ]
                if let url = tb.canonicalUrl { dict["canonicalUrl"] = url }
                return dict
            },
            "updatedAt": nowMs
        ]
    }
}
