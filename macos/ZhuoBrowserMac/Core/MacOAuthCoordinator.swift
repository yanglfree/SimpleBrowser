import AppKit
import AuthenticationServices
import Foundation

@MainActor
final class MacOAuthCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding, ASWebAuthenticationPresentationContextProviding {
    static let callbackScheme = "zhuobrowser-auth"
    static let callbackURL = "zhuobrowser-auth://oauth/callback"

    private var appleContinuation: CheckedContinuation<AppleNativeResult, Error>?
    private var webAuthSession: ASWebAuthenticationSession?

    struct AppleNativeResult {
        let identityToken: String
        let displayName: String?
    }

    func performNativeAppleSignIn() async throws -> AppleNativeResult {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]

        return try await withCheckedThrowingContinuation { continuation in
            self.appleContinuation = continuation
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    func performWebOAuth(provider: String, baseURL: String) async throws -> String {
        guard var components = URLComponents(string: "\(baseURL)/api/auth/oauth/\(provider)/start") else {
            throw NSError(domain: "ZhuoBrowserAuth", code: -1, userInfo: [NSLocalizedDescriptionKey: "无效的认证地址"])
        }
        components.queryItems = [
            URLQueryItem(name: "platform", value: "macos"),
            URLQueryItem(name: "client_redirect_uri", value: Self.callbackURL)
        ]
        guard let startURL = components.url else {
            throw NSError(domain: "ZhuoBrowserAuth", code: -1, userInfo: [NSLocalizedDescriptionKey: "无效的认证地址"])
        }

        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: startURL,
                callbackURLScheme: Self.callbackScheme
            ) { [weak self] callbackURL, error in
                self?.webAuthSession = nil
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let callbackURL,
                      let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems else {
                    continuation.resume(throwing: NSError(
                        domain: "ZhuoBrowserAuth",
                        code: -2,
                        userInfo: [NSLocalizedDescriptionKey: "未收到授权回调凭据"]
                    ))
                    return
                }
                if let err = items.first(where: { $0.name == "error" })?.value {
                    continuation.resume(throwing: NSError(
                        domain: "ZhuoBrowserAuth",
                        code: -3,
                        userInfo: [NSLocalizedDescriptionKey: "授权失败: \(err)"]
                    ))
                    return
                }
                guard let ticket = items.first(where: { $0.name == "ticket" })?.value, !ticket.isEmpty else {
                    continuation.resume(throwing: NSError(
                        domain: "ZhuoBrowserAuth",
                        code: -4,
                        userInfo: [NSLocalizedDescriptionKey: "授权票据为空"]
                    ))
                    return
                }
                continuation.resume(returning: ticket)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.webAuthSession = session
            if !session.start() {
                self.webAuthSession = nil
                continuation.resume(throwing: NSError(
                    domain: "ZhuoBrowserAuth",
                    code: -5,
                    userInfo: [NSLocalizedDescriptionKey: "无法启动系统认证窗口"]
                ))
            }
        }
    }

    // MARK: - ASAuthorizationControllerDelegate

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let token = String(data: tokenData, encoding: .utf8),
              !token.isEmpty else {
            appleContinuation?.resume(throwing: NSError(
                domain: "ZhuoBrowserAuth",
                code: -10,
                userInfo: [NSLocalizedDescriptionKey: "Apple 登录未返回有效的身份令牌"]
            ))
            appleContinuation = nil
            return
        }

        let formatter = PersonNameComponentsFormatter()
        let fullName = credential.fullName.map { formatter.string(from: $0).trimmingCharacters(in: .whitespacesAndNewlines) }
        let cleanName = (fullName?.isEmpty == false) ? fullName : nil
        appleContinuation?.resume(returning: AppleNativeResult(identityToken: token, displayName: cleanName))
        appleContinuation = nil
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        appleContinuation?.resume(throwing: error)
        appleContinuation = nil
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        NSApp.keyWindow ?? ProfileManager.shared.focusedSession.hostWindow ?? NSApp.windows.first ?? NSWindow()
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.keyWindow ?? ProfileManager.shared.focusedSession.hostWindow ?? NSApp.windows.first ?? NSWindow()
    }
}
