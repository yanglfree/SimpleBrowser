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
        "tracker-block",
        "force-zoom"
    ]

    static func makeConfiguration(isPrivate: Bool, dataStore: WKWebsiteDataStore, blockAds: Bool) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.websiteDataStore = isPrivate ? dataStore : .default()
        configuration.preferences.isFraudulentWebsiteWarningEnabled = true
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
        var installed = Set<String>()
        if blockAds {
            ContentBlocker.shared.install(on: controller, installed: &installed)
        }
        objc_setAssociatedObject(
            configuration,
            &AssociatedKeys.installedRuleLists,
            installed,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        return configuration
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
