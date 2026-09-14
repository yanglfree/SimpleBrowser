import Foundation

struct CompiledFilterList: Equatable {
    let json: String
    let count: Int
    let networkCount: Int
    let cosmeticCount: Int
    let skippedCount: Int
    let truncated: Bool
}

enum FilterListCompiler {
    static let maximumRuleCount = 50_000
    private static let resourceTypes = [
        "document", "image", "style-sheet", "script", "font",
        "raw", "svg-document", "media", "popup"
    ]

    static func compile(_ text: String, maximumRules: Int = maximumRuleCount) throws -> CompiledFilterList {
        var networkRules: [ContentRule] = []
        var cosmeticRules: [ContentRule] = []
        var networkCount = 0
        var cosmeticCount = 0
        var skippedCount = 0
        let limit = max(1, maximumRules)

        text.enumerateLines { raw, _ in
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("!") || line.hasPrefix("[") { return }
            if line.hasPrefix("@@") {
                skippedCount += 1
                return
            }
            if let separator = line.range(of: "##"),
               separator.lowerBound != line.startIndex,
               !line.hasPrefix("|"), !line.hasPrefix("/") {
                let domains = line[..<separator.lowerBound].split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                let selector = line[separator.upperBound...].trimmingCharacters(in: .whitespaces)
                guard !domains.isEmpty, !selector.isEmpty,
                      !domains.contains(where: { $0.hasPrefix("~") }) else {
                    skippedCount += 1
                    return
                }
                cosmeticCount += 1
                if cosmeticRules.count < limit {
                    cosmeticRules.append(.cosmetic(domains: domains, selector: selector))
                }
                return
            }
            guard line.hasPrefix("||"), !line.contains("$") else {
                skippedCount += 1
                return
            }
            let body = line.dropFirst(2)
            guard let separator = body.firstIndex(of: "^") else {
                skippedCount += 1
                return
            }
            let host = body[..<separator].lowercased()
            let path = String(body[body.index(after: separator)...])
            guard isValidHost(host) else {
                skippedCount += 1
                return
            }
            networkCount += 1
            if networkRules.count < limit {
                networkRules.append(.network(host: host, path: path, resourceTypes: resourceTypes))
            }
        }

        let rules = networkRules + cosmeticRules.prefix(max(0, limit - networkRules.count))
        let data = try JSONEncoder().encode(rules)
        guard let json = String(data: data, encoding: .utf8) else {
            throw FilterListCompilerError.encodingFailed
        }
        return CompiledFilterList(
            json: json, count: rules.count, networkCount: networkCount,
            cosmeticCount: cosmeticCount, skippedCount: skippedCount,
            truncated: networkCount + cosmeticCount > limit
        )
    }

    private static func isValidHost(_ host: String) -> Bool {
        !host.isEmpty && !host.contains("..") && host.unicodeScalars.allSatisfy {
            CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-").contains($0)
        }
    }

    fileprivate static func escapeRegex(_ value: String) -> String {
        let special = CharacterSet(charactersIn: ".*+?^${}()|[]\\")
        return value.unicodeScalars.map { special.contains($0) ? "\\\($0)" : String($0) }.joined()
    }

    fileprivate static func pathRegex(_ path: String) -> String {
        guard !path.isEmpty else { return "([:/].*)?" }
        let escaped = path.split(separator: "*", omittingEmptySubsequences: false)
            .map { escapeRegex(String($0)) }.joined(separator: ".*")
        return escaped.hasPrefix("/") ? escaped : "/\(escaped)"
    }
}

private struct ContentRule: Codable, Equatable {
    let trigger: Trigger
    let action: Action

    static func network(host: String, path: String, resourceTypes: [String]) -> Self {
        Self(
            trigger: Trigger(
                urlFilter: "^https?://([^/]*\\.)?\(FilterListCompiler.escapeRegex(host))\(FilterListCompiler.pathRegex(path))",
                resourceTypes: resourceTypes,
                ifDomain: nil
            ),
            action: Action(type: "block", selector: nil)
        )
    }

    static func cosmetic(domains: [String], selector: String) -> Self {
        Self(
            trigger: Trigger(
                urlFilter: ".*", resourceTypes: nil,
                ifDomain: domains.map { "*" + ($0.first == "*" ? String($0.dropFirst()) : $0) }
            ),
            action: Action(type: "css-display-none", selector: selector)
        )
    }

    struct Trigger: Codable, Equatable {
        let urlFilter: String
        let resourceTypes: [String]?
        let ifDomain: [String]?

        enum CodingKeys: String, CodingKey {
            case urlFilter = "url-filter"
            case resourceTypes = "resource-type"
            case ifDomain = "if-domain"
        }
    }

    struct Action: Codable, Equatable {
        let type: String
        let selector: String?
    }
}

enum FilterListCompilerError: Error {
    case encodingFailed
}
