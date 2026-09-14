import Foundation

enum FeedbackServiceError: LocalizedError {
    case invalidMessage(FeedbackValidationError)
    case invalidResponse
    case rejected(Int)

    var errorDescription: String? {
        switch self {
        case .invalidMessage(.tooShort): return "反馈内容至少需要 5 个字符。"
        case .invalidMessage(.tooLong): return "反馈内容不能超过 1000 个字符。"
        case .invalidResponse, .rejected: return "提交失败，请稍后重试。"
        }
    }
}

struct FeedbackService {
    static let endpoint = URL(string: "https://gateway.youdroid.top/v1/feedback")!

    var session: URLSession = .shared
    var endpoint: URL = Self.endpoint

    func submit(message: String, contact: String, appVersion: String, build: Int) async throws -> FeedbackSubmission {
        if let validation = FeedbackPolicy.validate(message) {
            throw FeedbackServiceError.invalidMessage(validation)
        }
        let trimmedContact = contact.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload = FeedbackPayload(
            appVersion: appVersion,
            message: message.trimmingCharacters(in: .whitespacesAndNewlines),
            contact: trimmedContact,
            allowFollowUp: !trimmedContact.isEmpty,
            metadata: FeedbackMetadata(versionCode: build, platform: "ios")
        )
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("zhuobrowser", forHTTPHeaderField: "X-App-Id")
        request.setValue("iOS", forHTTPHeaderField: "X-Platform")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw FeedbackServiceError.invalidResponse
        }
        guard 200..<300 ~= http.statusCode else {
            throw FeedbackServiceError.rejected(http.statusCode)
        }
        let envelope = try JSONDecoder().decode(FeedbackResponse.self, from: data)
        guard envelope.ok else { throw FeedbackServiceError.invalidResponse }
        return FeedbackSubmission(ticketID: envelope.ticketID, requestID: envelope.requestID)
    }
}

private extension FeedbackSubmission {
    init(ticketID: String, requestID: String) {
        self.ticketID = ticketID
        self.requestID = requestID
    }
}
