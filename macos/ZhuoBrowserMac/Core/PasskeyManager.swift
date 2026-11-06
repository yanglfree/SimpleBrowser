import Foundation
import AuthenticationServices
import Security

/// Manages macOS passkey & WebAuthn authorization state and system integration.
@MainActor
public final class PasskeyManager: NSObject {
    public static let shared = PasskeyManager()

    private let credentialManager = ASAuthorizationWebBrowserPublicKeyCredentialManager()

    /// Determines whether the current running process possesses Apple's restricted browser passkey entitlement
    /// (`com.apple.developer.web-browser.public-key-credential`).
    nonisolated public var hasBrowserPasskeyEntitlement: Bool {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        guard let val = SecTaskCopyValueForEntitlement(task, "com.apple.developer.web-browser.public-key-credential" as CFString, nil) else {
            return false
        }
        if CFGetTypeID(val) == CFBooleanGetTypeID() {
            return CFBooleanGetValue((val as! CFBoolean))
        }
        return false
    }

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
