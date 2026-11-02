import AppKit
import CoreServices
import Foundation
import UniformTypeIdentifiers

/// Summary of the URL schemes and document content types declared in an application's `Info.plist`.
public struct InfoPlistBrowserCapability: Equatable {
    public let declaredURLSchemes: Set<String>
    public let declaredViewerContentTypes: Set<String>

    /// macOS LaunchServices only lists an application in "System Settings → Desktop & Dock → Default web browser"
    /// when it declares itself as a Viewer for both `http`/`https` schemes and `public.html`/`public.xhtml` documents.
    public var qualifiesAsSystemDefaultWebBrowser: Bool {
        declaredURLSchemes.isSuperset(of: DefaultBrowserManager.requiredURLSchemes)
            && declaredViewerContentTypes.isSuperset(of: DefaultBrowserManager.requiredDocumentContentTypes)
    }
}

/// Manages macOS LaunchServices registration, default web browser status detection,
/// and user-initiated promotion of ZhuoBrowser as the system default browser.
public final class DefaultBrowserManager: ObservableObject {
    public static let shared = DefaultBrowserManager()

    public static let expectedBundleIdentifier = "com.youdroid.zhuobrowser.mac"
    public static let requiredURLSchemes: Set<String> = ["http", "https"]
    public static let requiredDocumentContentTypes: Set<String> = ["public.html", "public.xhtml"]

    public struct HandlerInfo: Equatable {
        public let bundleIdentifier: String?
        public let displayName: String?
        public let bundleURL: URL?

        public init(bundleIdentifier: String?, displayName: String?, bundleURL: URL?) {
            self.bundleIdentifier = bundleIdentifier
            self.displayName = displayName
            self.bundleURL = bundleURL
        }
    }

    @Published public private(set) var isDefaultBrowser: Bool = false
    @Published public private(set) var currentDefaultBrowserName: String = "Safari浏览器"
    @Published public private(set) var currentDefaultBundleIdentifier: String?
    @Published public private(set) var isRequestingDefault: Bool = false
    @Published public private(set) var statusMessage: String?

    public let ownBundleIdentifier: String
    private let defaultHandlerProvider: (String) -> HandlerInfo
    private let schemeDefaultSetter: (URL, String, @escaping (Error?) -> Void) -> Void
    private var appActiveObserver: NSObjectProtocol?

    public init(
        ownBundleIdentifier: String? = nil,
        defaultHandlerProvider: ((String) -> HandlerInfo)? = nil,
        schemeDefaultSetter: ((URL, String, @escaping (Error?) -> Void) -> Void)? = nil
    ) {
        let resolvedOwnBundleID = ownBundleIdentifier
            ?? Bundle.main.bundleIdentifier
            ?? Self.expectedBundleIdentifier
        self.ownBundleIdentifier = resolvedOwnBundleID
        self.defaultHandlerProvider = defaultHandlerProvider ?? Self.liveDefaultHandler(forScheme:)
        self.schemeDefaultSetter = schemeDefaultSetter ?? { appURL, scheme, completion in
            NSWorkspace.shared.setDefaultApplication(at: appURL, toOpenURLsWithScheme: scheme) { error in
                completion(error)
            }
        }

        refreshStatus()

        if !RuntimeEnvironment.isRunningUnitTests {
            appActiveObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.refreshStatus()
            }
        }
    }

    deinit {
        if let appActiveObserver {
            NotificationCenter.default.removeObserver(appActiveObserver)
        }
    }

    // MARK: - Info.plist Qualification Inspection

    /// Parses an `Info.plist` dictionary to verify whether it satisfies macOS's default browser criteria.
    public static func inspectInfoPlist(_ info: [String: Any]) -> InfoPlistBrowserCapability {
        var schemes = Set<String>()
        if let urlTypes = info["CFBundleURLTypes"] as? [[String: Any]] {
            for entry in urlTypes {
                let role = (entry["CFBundleTypeRole"] as? String) ?? "Viewer"
                guard role.caseInsensitiveCompare("Viewer") == .orderedSame
                    || role.caseInsensitiveCompare("Editor") == .orderedSame else {
                    continue
                }
                if let entrySchemes = entry["CFBundleURLSchemes"] as? [String] {
                    for scheme in entrySchemes {
                        schemes.insert(scheme.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
                    }
                }
            }
        }

        var contentTypes = Set<String>()
        if let docTypes = info["CFBundleDocumentTypes"] as? [[String: Any]] {
            for entry in docTypes {
                let role = (entry["CFBundleTypeRole"] as? String) ?? "Viewer"
                guard role.caseInsensitiveCompare("Viewer") == .orderedSame
                    || role.caseInsensitiveCompare("Editor") == .orderedSame else {
                    continue
                }
                if let types = entry["LSItemContentTypes"] as? [String] {
                    for type in types {
                        contentTypes.insert(type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
                    }
                }
            }
        }

        return InfoPlistBrowserCapability(
            declaredURLSchemes: schemes,
            declaredViewerContentTypes: contentTypes
        )
    }

    // MARK: - LaunchServices Registration & Status

    /// Registers the running application bundle with macOS LaunchServices so that
    /// System Settings immediately lists ZhuoBrowser under "Default web browser".
    public func ensureRegisteredWithLaunchServices() {
        guard !RuntimeEnvironment.isRunningUnitTests else { return }
        let installedAppURL = URL(fileURLWithPath: "/Applications/ZhuoBrowserMac.app")
        if FileManager.default.fileExists(atPath: installedAppURL.path),
           let installedBundle = Bundle(url: installedAppURL),
           installedBundle.bundleIdentifier?.caseInsensitiveCompare(ownBundleIdentifier) == .orderedSame,
           let info = installedBundle.infoDictionary,
           Self.inspectInfoPlist(info).qualifiesAsSystemDefaultWebBrowser {
            LSRegisterURL(installedAppURL as CFURL, true)
            return
        }
        let mainURL = Bundle.main.bundleURL
        if mainURL.pathExtension == "app" {
            LSRegisterURL(mainURL as CFURL, true)
        }
    }

    /// Resolves the best `.app` bundle URL to pass to `NSWorkspace.setDefaultApplication`.
    public func preferredApplicationBundleURL() -> URL {
        let installedAppURL = URL(fileURLWithPath: "/Applications/ZhuoBrowserMac.app")
        if FileManager.default.fileExists(atPath: installedAppURL.path),
           let installedBundle = Bundle(url: installedAppURL),
           installedBundle.bundleIdentifier?.caseInsensitiveCompare(ownBundleIdentifier) == .orderedSame,
           let info = installedBundle.infoDictionary,
           Self.inspectInfoPlist(info).qualifiesAsSystemDefaultWebBrowser {
            return installedAppURL
        }
        return Bundle.main.bundleURL
    }

    /// Re-evaluates whether ZhuoBrowser is currently the default handler for `http` and `https`.
    @discardableResult
    public func refreshStatus() -> Bool {
        let httpsHandler = defaultHandlerProvider("https")
        let httpHandler = defaultHandlerProvider("http")

        let resolvedBundleID = httpsHandler.bundleIdentifier ?? httpHandler.bundleIdentifier
        let isHTTPSOurs = Self.matchesBundleIdentifier(httpsHandler.bundleIdentifier, target: ownBundleIdentifier)
        let isHTTPOurs = Self.matchesBundleIdentifier(httpHandler.bundleIdentifier, target: ownBundleIdentifier)
        let nowDefault = isHTTPSOurs && isHTTPOurs

        let resolvedName: String
        if nowDefault {
            resolvedName = "Zhuo浏览器"
        } else if let name = httpsHandler.displayName ?? httpHandler.displayName, !name.isEmpty {
            resolvedName = name
        } else if let bundleID = resolvedBundleID, !bundleID.isEmpty {
            resolvedName = bundleID
        } else {
            resolvedName = "系统默认浏览器"
        }

        let applyUpdates = {
            if self.isDefaultBrowser != nowDefault {
                self.isDefaultBrowser = nowDefault
            }
            if self.currentDefaultBundleIdentifier != resolvedBundleID {
                self.currentDefaultBundleIdentifier = resolvedBundleID
            }
            if self.currentDefaultBrowserName != resolvedName {
                self.currentDefaultBrowserName = resolvedName
            }
            if nowDefault, self.statusMessage != nil {
                self.statusMessage = "已将 Zhuo浏览器 设为系统默认浏览器"
            }
        }

        if Thread.isMainThread {
            applyUpdates()
        } else {
            DispatchQueue.main.sync(execute: applyUpdates)
        }

        return nowDefault
    }

    /// Requests macOS to set ZhuoBrowser as the default web browser (`http` / `https` / HTML).
    public func setAsDefaultBrowser(completion: ((Bool) -> Void)? = nil) {
        ensureRegisteredWithLaunchServices()

        if refreshStatus() {
            statusMessage = "Zhuo浏览器 当前已是系统默认浏览器"
            completion?(true)
            return
        }

        let appURL = preferredApplicationBundleURL()
        isRequestingDefault = true
        statusMessage = "请在系统弹窗中确认将“Zhuo浏览器”设为默认网页浏览器..."

        schemeDefaultSetter(appURL, "http") { [weak self] httpError in
            guard let self else { return }
            self.schemeDefaultSetter(appURL, "https") { [weak self] httpsError in
                guard let self else { return }
                if !RuntimeEnvironment.isRunningUnitTests {
                    NSWorkspace.shared.setDefaultApplication(at: appURL, toOpen: .html) { _ in }
                    if let xhtmlType = UTType("public.xhtml") {
                        NSWorkspace.shared.setDefaultApplication(at: appURL, toOpen: xhtmlType) { _ in }
                    }
                }

                DispatchQueue.main.async {
                    self.isRequestingDefault = false
                    let becameDefault = self.refreshStatus()
                    if becameDefault {
                        self.statusMessage = "已将 Zhuo浏览器 设为系统默认浏览器"
                    } else if httpError != nil || httpsError != nil {
                        self.statusMessage = "未更改默认浏览器，您也可点击「系统设置...」在「默认网页浏览器」中手动选择"
                    } else {
                        self.statusMessage = "若系统未弹出确认框，请点击「系统设置...」在「默认网页浏览器」中选择 Zhuo浏览器"
                    }
                    completion?(becameDefault)
                }
            }
        }
    }

    /// Opens macOS System Settings → Desktop & Dock where "Default web browser" is located.
    public func openSystemDefaultBrowserSettings() {
        ensureRegisteredWithLaunchServices()
        let candidateURLs = [
            "x-apple.systempreferences:com.apple.Desktop-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.general"
        ]
        for raw in candidateURLs {
            if let url = URL(string: raw), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    // MARK: - Helpers

    private static func matchesBundleIdentifier(_ candidate: String?, target: String) -> Bool {
        guard let candidate = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
              !candidate.isEmpty else {
            return false
        }
        return candidate.caseInsensitiveCompare(target) == .orderedSame
    }

    private static func liveDefaultHandler(forScheme scheme: String) -> HandlerInfo {
        guard let probeURL = URL(string: "\(scheme)://example.com"),
              let appURL = NSWorkspace.shared.urlForApplication(toOpen: probeURL) else {
            return HandlerInfo(bundleIdentifier: nil, displayName: nil, bundleURL: nil)
        }
        let bundle = Bundle(url: appURL)
        let bundleID = bundle?.bundleIdentifier
        let displayName = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? FileManager.default.displayName(atPath: appURL.path)
                .replacingOccurrences(of: ".app", with: "")
        return HandlerInfo(bundleIdentifier: bundleID, displayName: displayName, bundleURL: appURL)
    }
}
