import Foundation

struct RemoteRuleArtifact: Codable, Equatable {
    let identifier: String
    let json: String
    let count: Int
    let truncated: Bool
}

struct RemoteRuleSnapshot: Codable, Equatable {
    let artifacts: [RemoteRuleArtifact]
    let updatedAt: Date
}

enum RemoteRuleStore {
    static let updateInterval: TimeInterval = 3 * 24 * 60 * 60
    private static let maximumSourceBytes = 20 * 1_024 * 1_024
    private static let sources = [
        RuleSource("easylist", "https://easylist-downloads.adblockplus.org/easylist.txt", true),
        RuleSource("easylistchina", "https://easylist-downloads.adblockplus.org/easylistchina.txt", true),
        RuleSource("easyprivacy", "https://easylist-downloads.adblockplus.org/easyprivacy.txt", false),
        RuleSource("adguard-chinese", "https://filters.adtidy.org/extension/ublock/filters/224.txt", false),
        RuleSource("cjx-annoyance", "https://cdn.jsdelivr.net/gh/cjx82630/cjxlist@master/cjx-annoyance.txt", false)
    ]

    static func cachedSnapshot() -> RemoteRuleSnapshot? {
        guard let data = try? Data(contentsOf: snapshotURL(), options: [.mappedIfSafe]),
              let snapshot = try? PropertyListDecoder().decode(RemoteRuleSnapshot.self, from: data),
              requiredIdentifiers.isSubset(of: Set(snapshot.artifacts.map(\.identifier))) else { return nil }
        return snapshot
    }

    static func shouldUpdate(_ snapshot: RemoteRuleSnapshot?, now: Date = Date()) -> Bool {
        guard let snapshot else { return true }
        return now.timeIntervalSince(snapshot.updatedAt) >= updateInterval
    }

    static func shouldUpdate(lastUpdatedAt: TimeInterval, now: Date = Date()) -> Bool {
        guard lastUpdatedAt > 0 else { return true }
        return now.timeIntervalSince1970 - lastUpdatedAt >= updateInterval
    }

    static func fetchSnapshot(allowsExpensiveNetworkAccess: Bool) async throws -> RemoteRuleSnapshot {
        var artifacts: [RemoteRuleArtifact] = []
        for source in sources {
            do {
                let text = try await fetch(source.url, allowsExpensiveNetworkAccess: allowsExpensiveNetworkAccess)
                let compiled = try FilterListCompiler.compile(text)
                guard compiled.count > 0 else { throw RemoteRuleError.emptySource(source.identifier) }
                artifacts.append(
                    RemoteRuleArtifact(
                        identifier: source.identifier,
                        json: compiled.json,
                        count: compiled.count,
                        truncated: compiled.truncated
                    )
                )
            } catch {
                if source.required { throw error }
            }
        }
        guard requiredIdentifiers.isSubset(of: Set(artifacts.map(\.identifier))) else {
            throw RemoteRuleError.missingRequiredSources
        }
        return RemoteRuleSnapshot(artifacts: artifacts, updatedAt: Date())
    }

    static func persist(_ snapshot: RemoteRuleSnapshot) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        try encoder.encode(snapshot).write(to: snapshotURL(), options: [.atomic])
    }

    private static var requiredIdentifiers: Set<String> {
        Set(sources.filter(\.required).map(\.identifier))
    }

    private static func fetch(_ url: URL, allowsExpensiveNetworkAccess: Bool) async throws -> String {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("text/plain", forHTTPHeaderField: "Accept")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 45
        configuration.allowsExpensiveNetworkAccess = allowsExpensiveNetworkAccess
        configuration.allowsConstrainedNetworkAccess = allowsExpensiveNetworkAccess
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              data.count <= maximumSourceBytes,
              let text = String(data: data, encoding: .utf8),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RemoteRuleError.invalidResponse(url.absoluteString)
        }
        return text
    }

    private static func snapshotURL() -> URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ZhuoBrowser/Rules", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("remote-rules.plist", isDirectory: false)
    }

    private struct RuleSource {
        let identifier: String
        let url: URL
        let required: Bool

        init(_ identifier: String, _ url: String, _ required: Bool) {
            self.identifier = identifier
            self.url = URL(string: url)!
            self.required = required
        }
    }
}

enum RemoteRuleError: Error {
    case emptySource(String)
    case invalidResponse(String)
    case missingRequiredSources
}
