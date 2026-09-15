import Foundation

enum InboundShareAction: String, Codable, CaseIterable {
    case cleanOpen
    case privateOpen
    case readAndClose
    case saveArticle
    case originalOpen

    var usesPrivateTab: Bool {
        self == .privateOpen || self == .readAndClose
    }

    var opensDisposableReader: Bool {
        self == .readAndClose
    }

    var requiresPro: Bool {
        self == .saveArticle
    }

    var shouldCaptureArticle: Bool {
        self == .saveArticle
    }

    func targetURL(in request: InboundShareRequest) -> String {
        self == .originalOpen ? request.rawURL : request.cleanURL
    }
}

struct InboundShareRequest: Codable, Identifiable, Equatable {
    let id: UUID
    let rawURL: String
    let cleanURL: String
    let title: String
    let action: InboundShareAction
    let createdAt: Date
    let removedTrackingParameters: [String]
}

enum InboundSharePolicy {
    private static let marketingParameters: Set<String> = [
        "fbclid", "gclid", "msclkid", "mc_cid", "mc_eid", "igshid", "_ga", "_gl"
    ]

    static func create(
        rawURL: String,
        title: String = "",
        action: InboundShareAction,
        id: UUID = UUID(),
        createdAt: Date = Date()
    ) -> InboundShareRequest? {
        let value = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isHTTPURL(value) else { return nil }
        let cleaned = removeMarketingParameters(from: value)
        return InboundShareRequest(
            id: id,
            rawURL: value,
            cleanURL: cleaned.url,
            title: String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200)),
            action: action,
            createdAt: createdAt,
            removedTrackingParameters: cleaned.removed
        )
    }

    static func extractHTTPURL(from text: String) -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = value.range(
            of: #"https?://[^\s<>"']+"#,
            options: [.regularExpression, .caseInsensitive]
        ) else { return nil }
        let trailing = CharacterSet(charactersIn: ")]}>.,;!，。；！")
        let candidate = String(value[range]).trimmingCharacters(in: trailing)
        return isHTTPURL(candidate) ? candidate : nil
    }

    static func availableActions(for request: InboundShareRequest) -> [InboundShareAction] {
        var actions: [InboundShareAction] = [
            .cleanOpen,
            .privateOpen,
            .readAndClose,
            .saveArticle
        ]
        if !request.removedTrackingParameters.isEmpty {
            actions.append(.originalOpen)
        }
        return actions
    }

    private static func removeMarketingParameters(from rawURL: String) -> (url: String, removed: [String]) {
        let fragmentIndex = rawURL.firstIndex(of: "#")
        let beforeFragment = fragmentIndex.map { String(rawURL[..<$0]) } ?? rawURL
        let fragment = fragmentIndex.map { String(rawURL[$0...]) } ?? ""
        guard let queryIndex = beforeFragment.firstIndex(of: "?") else {
            return (rawURL, [])
        }

        let base = String(beforeFragment[..<queryIndex])
        let queryStart = beforeFragment.index(after: queryIndex)
        let query = String(beforeFragment[queryStart...])
        var retained: [String] = []
        var removed: [String] = []
        for part in query.components(separatedBy: "&") where !part.isEmpty {
            let encodedName = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
            let decodedName = encodedName
                .replacingOccurrences(of: "+", with: " ")
                .removingPercentEncoding
            let name = (decodedName ?? encodedName).lowercased()
            if name.hasPrefix("utm_") || marketingParameters.contains(name) {
                removed.append(name)
            } else {
                retained.append(part)
            }
        }
        let suffix = retained.isEmpty ? "" : "?\(retained.joined(separator: "&"))"
        return ("\(base)\(suffix)\(fragment)", removed)
    }

    private static func isHTTPURL(_ value: String) -> Bool {
        value.range(
            of: #"^https?://[^\s/?#]+"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }
}

enum InboundShareQueueError: Error {
    case appGroupUnavailable
}

enum InboundShareQueue {
    static let appGroupIdentifier = "group.com.youdroid.zhuobrowser"
    static let retention: TimeInterval = 7 * 24 * 60 * 60
    static let maximumPendingCount = 20
    private static let directoryName = "InboundShares"

    static func enqueue(_ request: InboundShareRequest) throws {
        let directory = try directoryURL()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        let data = try JSONEncoder().encode(request)
        try data.write(
            to: fileURL(for: request.id, in: directory),
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
        try prune(directory: directory, now: Date())
    }

    static func pending(now: Date = Date()) throws -> [InboundShareRequest] {
        let directory = try directoryURL()
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension == "json" }
        var requests: [InboundShareRequest] = []
        for url in urls {
            guard let data = try? Data(contentsOf: url),
                  let request = try? JSONDecoder().decode(InboundShareRequest.self, from: data),
                  now.timeIntervalSince(request.createdAt) <= retention else {
                try? FileManager.default.removeItem(at: url)
                continue
            }
            requests.append(request)
        }
        return requests.sorted { $0.createdAt < $1.createdAt }
    }

    static func remove(_ request: InboundShareRequest) throws {
        let directory = try directoryURL()
        let url = fileURL(for: request.id, in: directory)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private static func prune(directory: URL, now: Date) throws {
        let requests = try pending(now: now)
        for request in requests.dropLast(maximumPendingCount) {
            try? FileManager.default.removeItem(at: fileURL(for: request.id, in: directory))
        }
    }

    private static func directoryURL() throws -> URL {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            throw InboundShareQueueError.appGroupUnavailable
        }
        return container.appendingPathComponent(directoryName, isDirectory: true)
    }

    private static func fileURL(for id: UUID, in directory: URL) -> URL {
        directory.appendingPathComponent(id.uuidString).appendingPathExtension("json")
    }
}
