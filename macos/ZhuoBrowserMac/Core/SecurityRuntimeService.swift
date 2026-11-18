import Foundation
import Network
import WebKit

/// Connects security preferences in `BrowserSettings` to real WebKit, Network.framework,
/// hardened JS runtime, and local password-compromise checks.
public enum SecurityRuntimeService {
    /// Applies the user's Safe Browsing tier to WebKit's native fraudulent-website warning preference.
    public static func applySafeBrowsing(
        level: SafeBrowsingLevel,
        to configuration: WKWebViewConfiguration
    ) {
        configuration.preferences.isFraudulentWebsiteWarningEnabled = (level != .disabled)
    }

    /// Resolves a validated HTTPS DoH endpoint URL when Secure DNS is enabled and configured.
    public static func effectiveDoHURL(
        enabled: Bool,
        provider: SecureDNSProvider,
        customURL: String
    ) -> URL? {
        guard enabled else { return nil }
        let raw = (provider == .custom ? customURL : provider.defaultDoHURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty,
              let url = URL(string: raw),
              url.scheme?.lowercased() == "https",
              let host = url.host,
              !host.isEmpty else {
            return nil
        }
        return url
    }

    /// Configures process-wide encrypted DNS-over-HTTPS resolution via Network.framework.
    public static func applySecureDNS(
        enabled: Bool,
        provider: SecureDNSProvider,
        customURL: String
    ) {
        if let dohURL = effectiveDoHURL(enabled: enabled, provider: provider, customURL: customURL) {
            NWParameters.PrivacyContext.default.requireEncryptedNameResolution(
                true,
                fallbackResolver: .https(dohURL, serverAddresses: [])
            )
        } else {
            NWParameters.PrivacyContext.default.requireEncryptedNameResolution(
                false,
                fallbackResolver: nil
            )
        }
    }

    /// Hardens the webpage execution environment when JIT optimization is turned off by
    /// removing high-risk shared-memory/binary JIT surfaces (`WebAssembly`, `SharedArrayBuffer`, `Atomics`).
    public static func makeHardenedNoJITScript() -> WKUserScript {
        let source = """
        (function() {
            window.__zhuoHardenedNoJIT = true;
            try { Object.defineProperty(window, 'WebAssembly', { value: undefined, configurable: false }); } catch (_) {}
            try { Object.defineProperty(window, 'SharedArrayBuffer', { value: undefined, configurable: false }); } catch (_) {}
            try { Object.defineProperty(window, 'Atomics', { value: undefined, configurable: false }); } catch (_) {}
        })();
        """
        return WKUserScript(
            source: source,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false,
            in: .page
        )
    }

    private static let knownCompromisedPasswords: Set<String> = [
        "123456", "1234567", "12345678", "123456789", "1234567890",
        "password", "password1", "password123", "passw0rd", "p@ssword",
        "qwerty", "qwerty123", "qwertyuiop", "111111", "000000", "666666", "888888",
        "admin", "admin123", "administrator", "root", "toor",
        "abc123", "iloveyou", "welcome", "letmein", "monkey", "dragon",
        "123123", "654321", "5201314", "asdfgh", "zxcvbn", "test123"
    ]

    /// Performs zero-network privacy-preserving local check against common breached and trivial passwords.
    public static func isPasswordKnownCompromised(_ password: String) -> Bool {
        guard !password.isEmpty else { return false }
        let lower = password.lowercased()
        if knownCompromisedPasswords.contains(lower) {
            return true
        }
        if Set(password).count == 1 {
            return true
        }
        if password.count >= 4, isSequentialDigits(password) {
            return true
        }
        return false
    }

    private static func isSequentialDigits(_ password: String) -> Bool {
        guard password.unicodeScalars.allSatisfy({ $0.value >= 48 && $0.value <= 57 }) else {
            return false
        }
        return "01234567890".contains(password) || "09876543210".contains(password)
    }
}
