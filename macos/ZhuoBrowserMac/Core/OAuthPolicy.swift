import Foundation
import WebKit

/// Policy engine detecting third-party OAuth, authentication flows, and popup window requests.
public enum OAuthPolicy {

    private static let knownOAuthHosts: Set<String> = [
        "accounts.google.com",
        "appleid.apple.com",
        "github.com",
        "gitlab.com",
        "login.microsoftonline.com",
        "login.live.com",
        "api.twitter.com",
        "twitter.com",
        "x.com",
        "facebook.com",
        "www.facebook.com",
        "auth.atlassian.com",
        "accounts.spotify.com",
        "discord.com",
        "slack.com"
    ]

    /// Determines whether a given URL is a third-party OAuth, authentication, or login endpoint.
    public static func isOAuthOrLoginURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }

        // 1. Google Accounts authentication
        if host == "accounts.google.com" || host.hasSuffix(".accounts.google.com") {
            return true
        }

        // 2. Apple ID authentication
        if host == "appleid.apple.com" {
            return true
        }

        // 3. Microsoft / Live login
        if host == "login.microsoftonline.com" || host == "login.live.com" {
            return true
        }

        let path = url.path.lowercased()

        // 4. Google Identity Services / One Tap endpoints
        if path.contains("/gsi/") {
            return true
        }

        // 5. Known OAuth hosts with auth-related paths
        if knownOAuthHosts.contains(host) {
            if path.contains("oauth")
                || path.contains("signin")
                || path.contains("login")
                || path.contains("authorize")
                || path.contains("single_sign_on")
                || path.contains("sso") {
                return true
            }
        }

        // 6. Generic OAuth/OIDC authorization endpoints (Auth0, Supabase, Clerk, Cognito, etc.)
        if path.hasSuffix("/authorize") || path.contains("/oauth2/") || path.contains("/oauth/") || path.contains("/auth/v1/authorize") {
            return true
        }

        // 7. Standard OAuth/OIDC or popup query parameters
        if let query = url.query?.lowercased() {
            if query.contains("ux_mode=popup") || query.contains("display=popup") {
                return true
            }
            let hasResponseType = query.contains("response_type=")
            let hasClientID = query.contains("client_id=")
            let hasRedirectURI = query.contains("redirect_uri=")
            if hasResponseType && (hasClientID || hasRedirectURI) {
                return true
            }
        }

        return false
    }

    /// Determines whether a window creation request should be handled as a dedicated popup window.
    public static func shouldOpenAsPopup(features: WKWindowFeatures, url: URL? = nil) -> Bool {
        // Explicit popup geometry requested by window.open(..., 'width=...,height=...')
        if features.width != nil || features.height != nil {
            return true
        }

        // Chrome controls requested hidden (e.g. menubar, toolbar, statusbar)
        if features.menuBarVisibility?.boolValue == false
            || features.toolbarsVisibility?.boolValue == false
            || features.statusBarVisibility?.boolValue == false {
            return true
        }

        // Explicit popup query parameter in requested URL
        if let query = url?.query?.lowercased(), query.contains("ux_mode=popup") || query.contains("display=popup") {
            return true
        }

        // If target URL is explicitly an OAuth/third-party login flow
        if let url = url, isOAuthOrLoginURL(url) {
            return true
        }

        return false
    }
}
