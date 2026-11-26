import Foundation
import WebKit

enum WebKernel {
    static let desktopUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " +
        "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

    static let documentStartFiles = [
        "blocked-link-guard",
        "long-press-target",
        "password-field-watcher"
    ]

    static let documentEndFiles = [
        "force-zoom"
    ]

    static func makeConfiguration(
        isPrivate: Bool,
        dataStore: WKWebsiteDataStore,
        blockAds: Bool,
        minimumFontSize: Int
    ) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = isPrivate ? dataStore : .default()
        configure(
            configuration,
            blockAds: blockAds,
            minimumFontSize: minimumFontSize
        )
        return configuration
    }

    /// Configures either a newly created or WebKit-provided popup `WKWebViewConfiguration`
    /// without replacing the configuration object itself (which preserves `window.opener`).
    ///
    /// WebKit hands `createWebViewWith` a copy of the opener's configuration that keeps the
    /// *same* `WKUserContentController` instance. Scripts, message handlers and content rule
    /// lists therefore already exist for the popup, so `inheritsUserContent` stops us from
    /// duplicating scripts or throwing on a duplicate message handler name.
    static func configure(
        _ configuration: WKWebViewConfiguration,
        blockAds: Bool,
        minimumFontSize: Int,
        inheritsUserContent: Bool = false
    ) {
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.allowsInlineMediaPlayback = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.preferences.isFraudulentWebsiteWarningEnabled = true
        configuration.preferences.minimumFontSize = CGFloat(minimumFontSize)

        guard !inheritsUserContent else {
            return
        }

        let controller = configuration.userContentController
        for name in documentStartFiles {
            if let script = loadScript(named: name) {
                controller.addUserScript(
                    WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: false)
                )
            }
        }
        for name in documentEndFiles {
            if let script = loadScript(named: name) {
                controller.addUserScript(
                    WKUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
                )
            }
        }
        var installed = installedRuleLists(from: configuration)
        if blockAds {
            ContentBlocker.shared.install(on: controller, installed: &installed)
        }
        storeInstalledRuleLists(installed, on: configuration)
    }

    static func installedRuleLists(from configuration: WKWebViewConfiguration) -> Set<String> {
        objc_getAssociatedObject(configuration, &AssociatedKeys.installedRuleLists) as? Set<String> ?? []
    }

    static func storeInstalledRuleLists(_ installed: Set<String>, on configuration: WKWebViewConfiguration) {
        objc_setAssociatedObject(
            configuration,
            &AssociatedKeys.installedRuleLists,
            installed,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
    }

    static func loadScript(named name: String) -> String? {
        if let url = Bundle.main.url(forResource: name, withExtension: "js", subdirectory: "js") {
            return try? String(contentsOf: url, encoding: .utf8)
        }
        if let url = Bundle.main.url(forResource: name, withExtension: "js") {
            return try? String(contentsOf: url, encoding: .utf8)
        }
        return nil
    }
}

private enum AssociatedKeys {
    static var installedRuleLists: UInt8 = 0
}
