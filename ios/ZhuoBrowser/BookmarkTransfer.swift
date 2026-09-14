import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum BookmarkTransferError: LocalizedError {
    case fileTooLarge
    case invalidEncoding

    var errorDescription: String? {
        switch self {
        case .fileTooLarge:
            return "书签文件超过 5 MB，无法导入。"
        case .invalidEncoding:
            return "书签文件不是有效的 UTF-8 HTML。"
        }
    }
}

enum BookmarkTransfer {
    static let maximumImportBytes = 5 * 1024 * 1024

    static func readImportData(from url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximumImportBytes + 1) ?? Data()
        guard data.count <= maximumImportBytes else {
            throw BookmarkTransferError.fileTooLarge
        }
        return data
    }

    static func parse(
        _ data: Data,
        now: TimeInterval = Date().timeIntervalSince1970
    ) throws -> [SavedItem] {
        guard data.count <= maximumImportBytes else {
            throw BookmarkTransferError.fileTooLarge
        }
        guard let html = String(data: data, encoding: .utf8) else {
            throw BookmarkTransferError.invalidEncoding
        }
        let pattern = #"<a\b([^>]*)>([\s\S]*?)</a>"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let range = NSRange(html.startIndex..., in: html)
        var seenURLs = Set<String>()
        var items: [SavedItem] = []
        for match in expression.matches(in: html, range: range) {
            guard let attributesRange = Range(match.range(at: 1), in: html),
                  let titleRange = Range(match.range(at: 2), in: html),
                  let rawURL = attribute("href", in: String(html[attributesRange])) else {
                continue
            }
            let url = decodeEntities(rawURL.trimmingCharacters(in: .whitespacesAndNewlines))
            guard let scheme = URL(string: url)?.scheme?.lowercased(),
                  ["http", "https"].contains(scheme),
                  seenURLs.insert(url).inserted else {
                continue
            }
            let rawTitle = String(html[titleRange])
                .replacingOccurrences(of: #"<[^>]*>"#, with: " ", options: .regularExpression)
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let attributes = String(html[attributesRange])
            let tags = attribute("tags", in: attributes)
                .map { normalizedTags(decodeEntities($0).split(separator: ",").map(String.init)) } ?? []
            let timestamp = now + TimeInterval(items.count) / 1_000
            items.append(
                SavedItem(
                    id: "saved-import-\(Int(now * 1000))-\(items.count)",
                    title: decodeEntities(rawTitle),
                    url: url,
                    createdAt: timestamp,
                    updatedAt: timestamp,
                    isRead: true,
                    tags: tags
                )
            )
        }
        return items
    }

    static func export(_ items: [SavedItem]) -> String {
        var lines = [
            "<!DOCTYPE NETSCAPE-Bookmark-file-1>",
            "<META HTTP-EQUIV=\"Content-Type\" CONTENT=\"text/html; charset=UTF-8\">",
            "<TITLE>Bookmarks</TITLE>",
            "<H1>Bookmarks</H1>",
            "<DL><p>"
        ]
        for item in items {
            let tags = normalizedTags(item.tags).joined(separator: ",")
            let tagAttribute = tags.isEmpty ? "" : " TAGS=\"\(escape(tags))\""
            lines.append("    <DT><A HREF=\"\(escape(item.url))\"\(tagAttribute)>\(escape(item.title))</A>")
        }
        lines.append("</DL><p>")
        return lines.joined(separator: "\n")
    }

    private static func attribute(_ name: String, in attributes: String) -> String? {
        let escapedName = NSRegularExpression.escapedPattern(for: name)
        let pattern = #"\b"# + escapedName + #"\s*=\s*[\"']([^\"']*)[\"']"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = expression.firstMatch(
                in: attributes,
                range: NSRange(attributes.startIndex..., in: attributes)
              ),
              let valueRange = Range(match.range(at: 1), in: attributes) else {
            return nil
        }
        return String(attributes[valueRange])
    }

    private static func normalizedTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        return tags.compactMap { raw in
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, seen.insert(value).inserted else {
                return nil
            }
            return value
        }
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func decodeEntities(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }
}

struct BookmarkHTMLDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.html] }

    let html: String

    init(html: String) {
        self.html = html
    }

    init(configuration: ReadConfiguration) throws {
        let data = configuration.file.regularFileContents ?? Data()
        guard let html = String(data: data, encoding: .utf8) else {
            throw BookmarkTransferError.invalidEncoding
        }
        self.html = html
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(html.utf8))
    }
}
