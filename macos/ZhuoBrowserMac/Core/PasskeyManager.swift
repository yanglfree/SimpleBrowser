import Foundation
import AuthenticationServices

/// Manages macOS passkey & WebAuthn authorization state and system integration.
@MainActor
public final class PasskeyManager: NSObject {
    public static let shared = PasskeyManager()

    private let credentialManager = ASAuthorizationWebBrowserPublicKeyCredentialManager()

    public var authorizationState: ASAuthorizationWebBrowserPublicKeyCredentialManager.AuthorizationState {
        credentialManager.authorizationStateForPlatformCredentials
    }

    public var isAuthorized: Bool {
        authorizationState == .authorized
    }

    /// Requests authorization for passkey access from the system if not already determined.
    @discardableResult
    public func requestAuthorizationIfNeeded() async -> ASAuthorizationWebBrowserPublicKeyCredentialManager.AuthorizationState {
        let current = credentialManager.authorizationStateForPlatformCredentials
        guard current == .notDetermined else {
            return current
        }

        return await withCheckedContinuation { continuation in
            credentialManager.requestAuthorizationForPublicKeyCredentials { newState in
                continuation.resume(returning: newState)
            }
        }
    }
}
