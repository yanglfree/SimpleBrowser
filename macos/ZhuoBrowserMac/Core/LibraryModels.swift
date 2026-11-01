import Foundation

public struct HistoryEntry: Identifiable, Equatable, Codable {
    public let id: String
    public var title: String
    public var url: String
    public var visitedAt: TimeInterval
    public var visitCount: Int

    public init(
        id: String = UUID().uuidString,
        title: String,
        url: String,
        visitedAt: TimeInterval = Date().timeIntervalSince1970,
        visitCount: Int = 1
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.visitedAt = visitedAt
        self.visitCount = visitCount
    }

    public var displayTitle: String {
        if !title.isEmpty && title != url {
            return title
        }
        if let host = URL(string: url)?.host {
            return host
        }
        return url
    }
}

/// Represents a user or preset bookmark folder (group).
public struct BookmarkFolder: Identifiable, Equatable, Hashable, Codable {
    public let id: String
    public var name: String
    public var iconName: String
    public var createdAt: TimeInterval
    public var sortOrder: Int
    public var isPinnedToStartPage: Bool

    public init(
        id: String = UUID().uuidString,
        name: String,
        iconName: String = "folder.fill",
        createdAt: TimeInterval = Date().timeIntervalSince1970,
        sortOrder: Int = 0,
        isPinnedToStartPage: Bool = true
    ) {
        self.id = id
        self.name = name
        self.iconName = iconName
        self.createdAt = createdAt
        self.sortOrder = sortOrder
        self.isPinnedToStartPage = isPinnedToStartPage
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case iconName
        case createdAt
        case sortOrder
        case isPinnedToStartPage
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.iconName = try container.decodeIfPresent(String.self, forKey: .iconName) ?? "folder.fill"
        self.createdAt = try container.decodeIfPresent(TimeInterval.self, forKey: .createdAt) ?? Date().timeIntervalSince1970
        self.sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        self.isPinnedToStartPage = try container.decodeIfPresent(Bool.self, forKey: .isPinnedToStartPage) ?? true
    }
}

/// Represents a single saved bookmark entry, optionally belonging to a `BookmarkFolder`.
public struct BookmarkEntry: Identifiable, Equatable, Hashable, Codable {
    public let id: String
    public var title: String
    public var shortTitle: String?
    public var url: String
    public var folderID: String?
    public var createdAt: TimeInterval
    public var updatedAt: TimeInterval
    public var isPinnedToStartPage: Bool
    public var iconName: String
    public var iconLetter: String
    public var colorHex: String
    public var sortOrder: Int

    public init(
        id: String = UUID().uuidString,
        title: String,
        shortTitle: String? = nil,
        url: String,
        folderID: String? = nil,
        createdAt: TimeInterval = Date().timeIntervalSince1970,
        updatedAt: TimeInterval? = nil,
        isPinnedToStartPage: Bool = false,
        iconName: String = "",
        iconLetter: String = "",
        colorHex: String = "",
        sortOrder: Int = 0
    ) {
        self.id = id
        self.title = title
        self.shortTitle = shortTitle
        self.url = url
        self.folderID = folderID
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.isPinnedToStartPage = isPinnedToStartPage
        self.iconName = iconName
        let fallbackLetter = String((!title.isEmpty ? title : url).prefix(1)).uppercased()
        self.iconLetter = iconLetter.isEmpty ? fallbackLetter : iconLetter
        self.colorHex = colorHex.isEmpty ? LibraryPolicy.colorHex(for: title.isEmpty ? url : title) : colorHex
        self.sortOrder = sortOrder
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case shortTitle
        case url
        case folderID
        case createdAt
        case updatedAt
        case isPinnedToStartPage
        case iconName
        case iconLetter
        case colorHex
        case sortOrder
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id)
        let title = try container.decode(String.self, forKey: .title)
        let shortTitle = try container.decodeIfPresent(String.self, forKey: .shortTitle)
        let url = try container.decode(String.self, forKey: .url)
        let folderID = try container.decodeIfPresent(String.self, forKey: .folderID)
        let createdAt = try container.decodeIfPresent(TimeInterval.self, forKey: .createdAt) ?? Date().timeIntervalSince1970
        let updatedAt = try container.decodeIfPresent(TimeInterval.self, forKey: .updatedAt) ?? createdAt
        let isPinnedToStartPage = try container.decodeIfPresent(Bool.self, forKey: .isPinnedToStartPage) ?? false
        let iconName = try container.decodeIfPresent(String.self, forKey: .iconName) ?? ""
        let iconLetter = try container.decodeIfPresent(String.self, forKey: .iconLetter) ?? ""
        let colorHex = try container.decodeIfPresent(String.self, forKey: .colorHex) ?? ""
        let sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0

        self.init(
            id: id,
            title: title,
            shortTitle: shortTitle,
            url: url,
            folderID: folderID,
            createdAt: createdAt,
            updatedAt: updatedAt,
            isPinnedToStartPage: isPinnedToStartPage,
            iconName: iconName,
            iconLetter: iconLetter,
            colorHex: colorHex,
            sortOrder: sortOrder
        )
    }

    public var displayTitle: String {
        if !title.isEmpty && title != url {
            return title
        }
        if let host = URL(string: url)?.host {
            return host
        }
        return url
    }

    public var startPageTileTitle: String {
        if let shortTitle, !shortTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return shortTitle
        }
        return displayTitle
    }

    public var hostDisplay: String {
        if let host = URL(string: url)?.host, !host.isEmpty {
            return host
        }
        return url
    }

    public var resolvedIconLetter: String {
        let trimmed = iconLetter.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        return String(displayTitle.prefix(1)).uppercased()
    }
}

/// Sort strategies available in the Bookmark Manager.
public enum BookmarkSortOrder: String, CaseIterable, Identifiable, Codable {
    case manual = "默认排序"
    case newestFirst = "最新添加"
    case oldestFirst = "最早添加"
    case titleAscending = "按名称 (A-Z)"
    case domainAscending = "按网站域名"

    public var id: String { rawValue }
}

public enum LibraryPolicy {
    public static let maxHistoryCount = 500
    public static let maxBookmarkCount = 300

    public static let defaultColorPalette: [String] = [
        "#2563EB", "#7C3AED", "#059669", "#EA580C",
        "#DB2777", "#0284C7", "#4F46E5", "#0D9488"
    ]

    public static func colorHex(for seed: String) -> String {
        let scalarSum = seed.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return defaultColorPalette[abs(scalarSum) % defaultColorPalette.count]
    }

    public static func normalizeComparableURL(_ url: String) -> String {
        var trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        return trimmed.lowercased()
    }

    public static func normalizeBookmarkURLInput(_ rawURL: String) -> String {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.contains("://") {
            return trimmed
        }
        return "https://\(trimmed)"
    }

    /// Records a new visit into history, deduplicating by URL and bumping visitCount.
    public static func recordHistory(
        _ history: [HistoryEntry],
        url: String,
        title: String,
        now: TimeInterval = Date().timeIntervalSince1970
    ) -> [HistoryEntry] {
        guard !url.isEmpty, url != "zhuo://home" else { return history }

        let target = normalizeComparableURL(url)
        let previous = history.first { normalizeComparableURL($0.url) == target }
        let entryTitle = !title.isEmpty ? title : (previous?.title ?? url)
        let merged = HistoryEntry(
            id: previous?.id ?? UUID().uuidString,
            title: entryTitle,
            url: url,
            visitedAt: now,
            visitCount: (previous?.visitCount ?? 0) + 1
        )

        let filtered = history.filter { normalizeComparableURL($0.url) != target }
        return [merged] + Array(filtered.prefix(maxHistoryCount - 1))
    }

    /// Adds or updates a bookmark entry by URL, optionally assigning a folder and start-page visibility.
    public static func addBookmark(
        _ bookmarks: [BookmarkEntry],
        url: String,
        title: String,
        folderID: String? = nil,
        isPinnedToStartPage: Bool? = nil,
        iconName: String? = nil,
        iconLetter: String? = nil,
        colorHex: String? = nil,
        now: TimeInterval = Date().timeIntervalSince1970
    ) -> [BookmarkEntry] {
        let normalizedInput = normalizeBookmarkURLInput(url)
        guard !normalizedInput.isEmpty, normalizedInput != "zhuo://home" else { return bookmarks }

        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = !cleanTitle.isEmpty ? cleanTitle : (URL(string: normalizedInput)?.host ?? normalizedInput)
        let target = normalizeComparableURL(normalizedInput)

        // Match existing bookmark in the same target folder, or fall back to any matching URL if folderID is nil
        let existing = bookmarks.first(where: {
            normalizeComparableURL($0.url) == target && (folderID == nil || $0.folderID == folderID)
        }) ?? bookmarks.first(where: {
            normalizeComparableURL($0.url) == target
        })

        let resolvedFolderID = folderID ?? existing?.folderID
        let resolvedPinned = isPinnedToStartPage ?? existing?.isPinnedToStartPage ?? (resolvedFolderID == nil)

        let newBookmark = BookmarkEntry(
            id: existing?.id ?? UUID().uuidString,
            title: displayTitle,
            shortTitle: existing?.shortTitle,
            url: normalizedInput,
            folderID: resolvedFolderID,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now,
            isPinnedToStartPage: resolvedPinned,
            iconName: iconName ?? existing?.iconName ?? "",
            iconLetter: iconLetter ?? existing?.iconLetter ?? String(displayTitle.prefix(1)).uppercased(),
            colorHex: colorHex ?? existing?.colorHex ?? Self.colorHex(for: displayTitle),
            sortOrder: existing?.sortOrder ?? 0
        )

        let filtered: [BookmarkEntry]
        if let existing {
            filtered = bookmarks.filter { $0.id != existing.id }
        } else {
            filtered = bookmarks.filter { normalizeComparableURL($0.url) != target }
        }
        return [newBookmark] + Array(filtered.prefix(maxBookmarkCount - 1))
    }

    /// Removes a bookmark by its ID.
    public static func removeBookmark(_ bookmarks: [BookmarkEntry], id: String) -> [BookmarkEntry] {
        bookmarks.filter { $0.id != id }
    }

    /// Removes multiple bookmarks by their IDs.
    public static func removeBookmarks(_ bookmarks: [BookmarkEntry], ids: Set<String>) -> [BookmarkEntry] {
        guard !ids.isEmpty else { return bookmarks }
        return bookmarks.filter { !ids.contains($0.id) }
    }

    /// Removes a bookmark by its exact URL.
    public static func removeBookmarkByUrl(_ bookmarks: [BookmarkEntry], url: String) -> [BookmarkEntry] {
        let target = normalizeComparableURL(url)
        return bookmarks.filter { normalizeComparableURL($0.url) != target }
    }

    /// Updates title and URL of an existing bookmark while preserving its folder and metadata.
    public static func updateBookmark(
        _ bookmarks: [BookmarkEntry],
        id: String,
        title: String,
        url: String
    ) -> [BookmarkEntry] {
        bookmarks.map { item in
            guard item.id == id else { return item }
            var updated = item
            let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanTitle.isEmpty {
                updated.title = cleanTitle
                if updated.shortTitle != nil {
                    updated.shortTitle = nil
                }
            }
            let cleanURL = normalizeBookmarkURLInput(url)
            if !cleanURL.isEmpty {
                updated.url = cleanURL
            }
            updated.updatedAt = Date().timeIntervalSince1970
            return updated
        }
    }

    /// Updates title, URL, target folder, and start-page pin status of an existing bookmark.
    public static func updateBookmark(
        _ bookmarks: [BookmarkEntry],
        id: String,
        title: String,
        url: String,
        folderID: String?,
        isPinnedToStartPage: Bool? = nil
    ) -> [BookmarkEntry] {
        bookmarks.map { item in
            guard item.id == id else { return item }
            var updated = item
            let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanTitle.isEmpty {
                updated.title = cleanTitle
                if updated.shortTitle != nil && cleanTitle != item.title {
                    updated.shortTitle = nil
                }
            }
            let cleanURL = normalizeBookmarkURLInput(url)
            if !cleanURL.isEmpty {
                updated.url = cleanURL
            }
            updated.folderID = folderID
            if let isPinnedToStartPage {
                updated.isPinnedToStartPage = isPinnedToStartPage
            } else if folderID == nil && item.folderID != nil {
                // Moving out of a folder to root defaults to visible on start page
                updated.isPinnedToStartPage = true
            }
            updated.updatedAt = Date().timeIntervalSince1970
            return updated
        }
    }

    /// Moves a single bookmark to the specified folder (`nil` moves to Ungrouped / Root).
    public static func moveBookmark(
        _ bookmarks: [BookmarkEntry],
        id: String,
        toFolderID folderID: String?
    ) -> [BookmarkEntry] {
        bookmarks.map { item in
            guard item.id == id else { return item }
            var updated = item
            updated.folderID = folderID
            if folderID == nil {
                updated.isPinnedToStartPage = true
            }
            updated.updatedAt = Date().timeIntervalSince1970
            return updated
        }
    }

    /// Moves a batch of bookmarks to the specified folder (`nil` moves to Ungrouped / Root).
    public static func moveBookmarks(
        _ bookmarks: [BookmarkEntry],
        ids: Set<String>,
        toFolderID folderID: String?
    ) -> [BookmarkEntry] {
        guard !ids.isEmpty else { return bookmarks }
        let now = Date().timeIntervalSince1970
        return bookmarks.map { item in
            guard ids.contains(item.id) else { return item }
            var updated = item
            updated.folderID = folderID
            if folderID == nil {
                updated.isPinnedToStartPage = true
            }
            updated.updatedAt = now
            return updated
        }
    }

    /// Toggles whether a bookmark is pinned to the Start Page Favorites grid.
    public static func togglePinToStartPage(
        _ bookmarks: [BookmarkEntry],
        id: String
    ) -> [BookmarkEntry] {
        bookmarks.map { item in
            guard item.id == id else { return item }
            var updated = item
            updated.isPinnedToStartPage.toggle()
            updated.updatedAt = Date().timeIntervalSince1970
            return updated
        }
    }

    /// Checks whether the specified URL is bookmarked.
    public static func isBookmarked(_ bookmarks: [BookmarkEntry], url: String) -> Bool {
        guard !url.isEmpty, url != "zhuo://home" else { return false }
        let target = normalizeComparableURL(url)
        return bookmarks.contains { normalizeComparableURL($0.url) == target }
    }

    /// Returns bookmarks belonging to a specific folder (`nil` returns ungrouped bookmarks).
    public static func bookmarks(inFolderID folderID: String?, from bookmarks: [BookmarkEntry]) -> [BookmarkEntry] {
        bookmarks.filter { $0.folderID == folderID }
    }

    // MARK: - Folder Management

    /// Creates a new bookmark folder if the name is non-empty and not already present.
    public static func createFolder(
        _ folders: [BookmarkFolder],
        name: String,
        iconName: String = "folder.fill",
        isPinnedToStartPage: Bool = true,
        now: TimeInterval = Date().timeIntervalSince1970
    ) -> [BookmarkFolder] {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return folders }
        if folders.contains(where: { $0.name.lowercased() == trimmed.lowercased() }) {
            return folders
        }
        let nextOrder = (folders.map(\.sortOrder).max() ?? -1) + 1
        let newFolder = BookmarkFolder(
            name: trimmed,
            iconName: iconName,
            createdAt: now,
            sortOrder: nextOrder,
            isPinnedToStartPage: isPinnedToStartPage
        )
        return folders + [newFolder]
    }

    /// Renames an existing bookmark folder.
    public static func renameFolder(
        _ folders: [BookmarkFolder],
        id: String,
        newName: String
    ) -> [BookmarkFolder] {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return folders }
        return folders.map { folder in
            guard folder.id == id else { return folder }
            var updated = folder
            updated.name = trimmed
            return updated
        }
    }

    /// Deletes a bookmark folder. Contained bookmarks are either deleted or moved to Ungrouped (`folderID = nil`).
    public static func removeFolder(
        _ folders: [BookmarkFolder],
        bookmarks: [BookmarkEntry],
        folderID: String,
        deleteContainedBookmarks: Bool = false
    ) -> (folders: [BookmarkFolder], bookmarks: [BookmarkEntry]) {
        let remainingFolders = folders.filter { $0.id != folderID }
        let updatedBookmarks: [BookmarkEntry]
        if deleteContainedBookmarks {
            updatedBookmarks = bookmarks.filter { $0.folderID != folderID }
        } else {
            updatedBookmarks = bookmarks.map { item in
                guard item.folderID == folderID else { return item }
                var moved = item
                moved.folderID = nil
                moved.isPinnedToStartPage = true
                return moved
            }
        }
        return (remainingFolders, updatedBookmarks)
    }

    /// Moves a folder up (`direction < 0`) or down (`direction > 0`).
    public static func moveFolder(
        _ folders: [BookmarkFolder],
        id: String,
        direction: Int
    ) -> [BookmarkFolder] {
        guard direction != 0,
              let index = folders.firstIndex(where: { $0.id == id }) else {
            return folders
        }
        let targetIndex = index + (direction < 0 ? -1 : 1)
        guard targetIndex >= 0 && targetIndex < folders.count else { return folders }

        var reordered = folders
        reordered.swapAt(index, targetIndex)
        for idx in reordered.indices {
            reordered[idx].sortOrder = idx
        }
        return reordered
    }

    /// Sorts a bookmark array according to the chosen `BookmarkSortOrder`.
    public static func sortBookmarks(
        _ bookmarks: [BookmarkEntry],
        by order: BookmarkSortOrder
    ) -> [BookmarkEntry] {
        switch order {
        case .manual:
            return bookmarks
        case .newestFirst:
            return bookmarks.sorted { $0.createdAt > $1.createdAt }
        case .oldestFirst:
            return bookmarks.sorted { $0.createdAt < $1.createdAt }
        case .titleAscending:
            return bookmarks.sorted {
                $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending
            }
        case .domainAscending:
            return bookmarks.sorted {
                let cmp = $0.hostDisplay.localizedCaseInsensitiveCompare($1.hostDisplay)
                if cmp != .orderedSame { return cmp == .orderedAscending }
                return $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending
            }
        }
    }

    /// Removes a single history item by ID.
    public static func removeHistoryItem(_ history: [HistoryEntry], id: String) -> [HistoryEntry] {
        history.filter { $0.id != id }
    }
}

/// Netscape Bookmark HTML parser and exporter supporting folders (`<H3>`) and links (`<A HREF>`).
public enum BookmarkHTMLTransfer {
    public static func exportHTML(folders: [BookmarkFolder], bookmarks: [BookmarkEntry]) -> String {
        var lines: [String] = [
            "<!DOCTYPE NETSCAPE-Bookmark-file-1>",
            "<META HTTP-EQUIV=\"Content-Type\" CONTENT=\"text/html; charset=UTF-8\">",
            "<TITLE>Bookmarks</TITLE>",
            "<H1>Bookmarks</H1>",
            "<DL><p>"
        ]

        // 1. Export each folder and its bookmarks
        for folder in folders {
            let folderItems = bookmarks.filter { $0.folderID == folder.id }
            let addDate = Int(folder.createdAt)
            lines.append("    <DT><H3 ADD_DATE=\"\(addDate)\">\(escapeHTML(folder.name))</H3>")
            lines.append("    <DL><p>")
            for item in folderItems {
                let itemDate = Int(item.createdAt)
                lines.append("        <DT><A HREF=\"\(escapeHTML(item.url))\" ADD_DATE=\"\(itemDate)\">\(escapeHTML(item.displayTitle))</A>")
            }
            lines.append("    </DL><p>")
        }

        // 2. Export ungrouped bookmarks
        let validFolderIDs = Set(folders.map(\.id))
        let ungrouped = bookmarks.filter {
            guard let fid = $0.folderID else { return true }
            return !validFolderIDs.contains(fid)
        }
        for item in ungrouped {
            let itemDate = Int(item.createdAt)
            lines.append("    <DT><A HREF=\"\(escapeHTML(item.url))\" ADD_DATE=\"\(itemDate)\">\(escapeHTML(item.displayTitle))</A>")
        }

        lines.append("</DL><p>")
        return lines.joined(separator: "\n")
    }

    public static func importHTML(
        _ html: String,
        existingFolders: [BookmarkFolder],
        existingBookmarks: [BookmarkEntry],
        now: TimeInterval = Date().timeIntervalSince1970
    ) -> (folders: [BookmarkFolder], bookmarks: [BookmarkEntry], importedCount: Int) {
        var folders = existingFolders
        var bookmarks = existingBookmarks
        var importedCount = 0

        var folderStack: [String?] = [nil]
        var pendingFolderID: String?

        let rawLines = html.components(separatedBy: .newlines)
        for line in rawLines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            // Check for folder header <H3 ...>Folder Name</H3>
            if let folderName = extractTagContent(from: trimmed, tag: "h3") {
                let cleanName = decodeHTML(folderName).trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleanName.isEmpty && cleanName.lowercased() != "bookmarks" && cleanName != "书签栏" {
                    if let existing = folders.first(where: { $0.name.lowercased() == cleanName.lowercased() }) {
                        pendingFolderID = existing.id
                    } else {
                        folders = LibraryPolicy.createFolder(folders, name: cleanName, now: now)
                        pendingFolderID = folders.last?.id
                    }
                }
            }

            if trimmed.range(of: "<dl", options: .caseInsensitive) != nil {
                if let pending = pendingFolderID {
                    folderStack.append(pending)
                    pendingFolderID = nil
                } else if folderStack.count == 1 && folderStack.last == nil {
                    // Root <DL>, keep nil on top
                } else {
                    folderStack.append(folderStack.last ?? nil)
                }
            }

            if let href = extractHref(from: trimmed),
               let rawTitle = extractTagContent(from: trimmed, tag: "a") {
                let url = decodeHTML(href).trimmingCharacters(in: .whitespacesAndNewlines)
                let title = decodeHTML(rawTitle.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if url.lowercased().hasPrefix("http://") || url.lowercased().hasPrefix("https://") {
                    let currentFolderID = folderStack.last ?? nil
                    let beforeCount = bookmarks.count
                    let alreadyExistsInFolder = bookmarks.contains {
                        LibraryPolicy.normalizeComparableURL($0.url) == LibraryPolicy.normalizeComparableURL(url)
                            && $0.folderID == currentFolderID
                    }
                    if !alreadyExistsInFolder {
                        bookmarks = LibraryPolicy.addBookmark(
                            bookmarks,
                            url: url,
                            title: title.isEmpty ? url : title,
                            folderID: currentFolderID,
                            isPinnedToStartPage: currentFolderID == nil,
                            now: now + Double(importedCount) * 0.001
                        )
                        if bookmarks.count >= beforeCount {
                            importedCount += 1
                        }
                    }
                }
            }

            if trimmed.range(of: "</dl>", options: .caseInsensitive) != nil {
                if folderStack.count > 1 {
                    folderStack.removeLast()
                }
                pendingFolderID = nil
            }
        }

        return (folders, bookmarks, importedCount)
    }

    private static func extractTagContent(from text: String, tag: String) -> String? {
        let pattern = "<\(tag)\\b[^>]*>([\\s\\S]*?)</\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range])
    }

    private static func extractHref(from text: String) -> String? {
        let pattern = "<a\\b[^>]*\\bhref\\s*=\\s*[\"']([^\"']+)[\"']"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range])
    }

    private static func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func decodeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}
