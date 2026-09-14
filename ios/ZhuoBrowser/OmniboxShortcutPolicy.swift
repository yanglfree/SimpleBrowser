import Foundation

struct OmniboxSelection: Equatable {
    var start: Int
    var end: Int

    static let zero = OmniboxSelection(start: 0, end: 0)
}

struct OmniboxEditResult: Equatable {
    var text: String
    var selection: OmniboxSelection
}

enum OmniboxShortcutKind {
    case currentHost
    case prefix
    case suffix
    case path
}

struct OmniboxShortcut: Identifiable, Equatable {
    var label: String
    var value: String
    var kind: OmniboxShortcutKind

    var id: String { "\(kind)-\(label)" }

    var accessibilityIdentifier: String {
        switch kind {
        case .currentHost: return "omni-shortcut-current-host"
        case .prefix: return "omni-shortcut-prefix"
        case .suffix: return label == ".cn" ? "omni-shortcut-cn" : "omni-shortcut-com"
        case .path: return "omni-shortcut-path"
        }
    }
}

enum OmniboxShortcutPolicy {
    static func shortcuts(currentHost: String) -> [OmniboxShortcut] {
        var result: [OmniboxShortcut] = []
        let host = currentHost.trimmingCharacters(in: .whitespacesAndNewlines)
        if !host.isEmpty {
            result.append(OmniboxShortcut(label: host, value: host, kind: .currentHost))
        }
        result.append(contentsOf: [
            OmniboxShortcut(label: ".com", value: ".com", kind: .suffix),
            OmniboxShortcut(label: ".cn", value: ".cn", kind: .suffix),
            OmniboxShortcut(label: "www.", value: "www.", kind: .prefix),
            OmniboxShortcut(label: "/", value: "/", kind: .path)
        ])
        return result
    }

    static func apply(
        text: String,
        selection: OmniboxSelection,
        shortcut: OmniboxShortcut
    ) -> OmniboxEditResult {
        let selection = normalized(selection, length: (text as NSString).length)
        switch shortcut.kind {
        case .currentHost:
            let replacement = shortcut.value.trimmingCharacters(in: .whitespacesAndNewlines)
            let caret = (replacement as NSString).length
            return OmniboxEditResult(
                text: replacement,
                selection: OmniboxSelection(start: caret, end: caret)
            )
        case .prefix:
            return insertPrefix(shortcut.value, into: text, selection: selection)
        case .suffix:
            return insertSuffix(shortcut.value, into: text, selection: selection)
        case .path:
            return insertPathSeparator(into: text, selection: selection)
        }
    }

    private static func normalized(_ selection: OmniboxSelection, length: Int) -> OmniboxSelection {
        OmniboxSelection(
            start: min(length, max(0, min(selection.start, selection.end))),
            end: min(length, max(0, max(selection.start, selection.end)))
        )
    }

    private static func replacing(
        _ text: String,
        selection: OmniboxSelection,
        with replacement: String
    ) -> OmniboxEditResult {
        let range = NSRange(location: selection.start, length: selection.end - selection.start)
        let nextText = (text as NSString).replacingCharacters(in: range, with: replacement)
        let caret = selection.start + (replacement as NSString).length
        return OmniboxEditResult(
            text: nextText,
            selection: OmniboxSelection(start: caret, end: caret)
        )
    }

    private static func insertPrefix(
        _ prefix: String,
        into text: String,
        selection: OmniboxSelection
    ) -> OmniboxEditResult {
        let value = text as NSString
        if selection.start != selection.end {
            let selected = value.substring(with: NSRange(
                location: selection.start,
                length: selection.end - selection.start
            ))
            let schemeLength = anchoredSchemeLength(selected)
            if schemeLength > 0 {
                let insertionPoint = selection.start + schemeLength
                if value.substring(from: insertionPoint).hasPrefix(prefix) {
                    let caret = insertionPoint + (prefix as NSString).length
                    return OmniboxEditResult(
                        text: text,
                        selection: OmniboxSelection(start: caret, end: caret)
                    )
                }
                return replacing(
                    text,
                    selection: OmniboxSelection(start: insertionPoint, end: insertionPoint),
                    with: prefix
                )
            }
            let replacement = selected.hasPrefix(prefix) ? selected : prefix + selected
            return replacing(text, selection: selection, with: replacement)
        }

        let insertionPoint = anchoredSchemeLength(text)
        if value.substring(from: insertionPoint).hasPrefix(prefix) {
            return OmniboxEditResult(text: text, selection: selection)
        }
        return replacing(
            text,
            selection: OmniboxSelection(start: insertionPoint, end: insertionPoint),
            with: prefix
        )
    }

    private static func insertSuffix(
        _ suffix: String,
        into text: String,
        selection: OmniboxSelection
    ) -> OmniboxEditResult {
        let value = text as NSString
        if selection.start != selection.end {
            let selected = value.substring(with: NSRange(
                location: selection.start,
                length: selection.end - selection.start
            ))
            return replacing(
                text,
                selection: selection,
                with: selected.hasSuffix(suffix) ? selected : selected + suffix
            )
        }
        if value.substring(to: selection.start).hasSuffix(suffix) {
            return OmniboxEditResult(text: text, selection: selection)
        }
        return replacing(text, selection: selection, with: suffix)
    }

    private static func insertPathSeparator(
        into text: String,
        selection: OmniboxSelection
    ) -> OmniboxEditResult {
        let value = text as NSString
        if selection.start != selection.end {
            let selected = value.substring(with: NSRange(
                location: selection.start,
                length: selection.end - selection.start
            ))
            return replacing(
                text,
                selection: selection,
                with: selected.hasSuffix("/") ? selected : selected + "/"
            )
        }
        if value.substring(to: selection.start).hasSuffix("/") ||
            value.substring(from: selection.start).hasPrefix("/") {
            return OmniboxEditResult(text: text, selection: selection)
        }
        return replacing(text, selection: selection, with: "/")
    }

    private static func anchoredSchemeLength(_ text: String) -> Int {
        let range = (text as NSString).range(
            of: "^[a-z][a-z0-9+.-]*://",
            options: [.regularExpression, .caseInsensitive]
        )
        return range.location == NSNotFound ? 0 : range.length
    }
}
