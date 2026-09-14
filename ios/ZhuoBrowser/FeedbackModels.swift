import Foundation

enum FeedbackValidationError: Equatable {
    case tooShort
    case tooLong
}

enum FeedbackPolicy {
    static let minimumMessageLength = 5
    static let maximumMessageLength = 1_000

    static func validate(_ message: String) -> FeedbackValidationError? {
        let count = message.trimmingCharacters(in: .whitespacesAndNewlines).count
        if count < minimumMessageLength { return .tooShort }
        if count > maximumMessageLength { return .tooLong }
        return nil
    }
}

struct FeedbackMetadata: Encodable {
    let versionCode: Int
    let platform: String

    enum CodingKeys: String, CodingKey {
        case versionCode = "version_code"
        case platform
    }
}

struct FeedbackPayload: Encodable {
    let appID = "zhuobrowser"
    let appName = "卓阅浏览器"
    let packageName = "com.youdroid.zhuobrowser"
    let appVersion: String
    let category = "feedback"
    let message: String
    let contact: String
    let allowFollowUp: Bool
    let client = "ios"
    let metadata: FeedbackMetadata

    enum CodingKeys: String, CodingKey {
        case appID = "app_id"
        case appName = "app_name"
        case packageName = "package_name"
        case appVersion = "app_version"
        case category, message, contact, allowFollowUp, client, metadata
    }
}

struct FeedbackSubmission: Decodable, Equatable {
    let ticketID: String
    let requestID: String

    enum CodingKeys: String, CodingKey {
        case ticketID = "ticketId"
        case ticketIDSnake = "ticket_id"
        case requestID = "requestId"
        case requestIDSnake = "request_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ticketID = try container.decodeIfPresent(String.self, forKey: .ticketID)
            ?? container.decodeIfPresent(String.self, forKey: .ticketIDSnake)
            ?? ""
        requestID = try container.decodeIfPresent(String.self, forKey: .requestIDSnake)
            ?? container.decodeIfPresent(String.self, forKey: .requestID)
            ?? ""
    }
}

struct FeedbackResponse: Decodable {
    let ok: Bool
    let ticketID: String
    let requestID: String

    enum CodingKeys: String, CodingKey {
        case ok
        case ticketID = "ticketId"
        case ticketIDSnake = "ticket_id"
        case requestID = "requestId"
        case requestIDSnake = "request_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decodeIfPresent(Bool.self, forKey: .ok) ?? false
        ticketID = try container.decodeIfPresent(String.self, forKey: .ticketID)
            ?? container.decodeIfPresent(String.self, forKey: .ticketIDSnake)
            ?? ""
        requestID = try container.decodeIfPresent(String.self, forKey: .requestIDSnake)
            ?? container.decodeIfPresent(String.self, forKey: .requestID)
            ?? ""
    }
}
