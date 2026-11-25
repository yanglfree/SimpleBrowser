import Carbon
import Darwin
import Foundation
import ObjectiveC
import os

/// Protects macOS sandboxed sessions against `EXC_BREAKPOINT (SIGTRAP): CFRelease(NULL)` inside
/// `-[TUINSCursorUIController _selectCurrentInputSource]` when switching to a newly installed
/// third-party input method whose `IntlDataCache` has not been refreshed inside the sandbox.
public enum InputSourceCrashGuard {
    public struct InstalledInputMethodBundle: Equatable {
        public let bundleURL: URL
        public let bundleID: String
        public let inputSourceIDs: [String]

        public init(bundleURL: URL, bundleID: String, inputSourceIDs: [String]) {
            self.bundleURL = bundleURL
            self.bundleID = bundleID
            self.inputSourceIDs = inputSourceIDs
        }
    }

    private static let logger = Logger(
        subsystem: "com.youdroid.zhuobrowser.mac",
        category: "InputSourceCrashGuard"
    )
    private static let lock = NSLock()
    private static var isSwizzled = false

    private typealias CopyInputSourceRefFn = @convention(c) (CFString) -> Unmanaged<TISInputSource>?
    private typealias ShowMenuHUDFn = @convention(c) (AnyObject, Selector, AnyObject?) -> Void
    private typealias SelectCurrentInputSourceFn = @convention(c) (AnyObject, Selector) -> Void

    private static let copyInputSourceRefFn: CopyInputSourceRefFn? = {
        let hitoolboxPath = "/System/Library/Frameworks/Carbon.framework/Versions/A/Frameworks/HIToolbox.framework/Versions/A/HIToolbox"
        guard let handle = dlopen(hitoolboxPath, RTLD_LAZY),
              let sym = dlsym(handle, "TISCopyInputSourceRefForInputSourceID") else {
            return nil
        }
        return unsafeBitCast(sym, to: CopyInputSourceRefFn.self)
    }()

    /// Installs cache self-healing and the `TUINSCursorUIController` NULL-input-source guard.
    /// Safe to call multiple times; swizzling is applied at most once per process.
    public static func install() {
        healStaleInputSourceCacheIfNeeded()
        installCursorUISwizzleIfNeeded()
    }

    public static func defaultInputMethodDirectories() -> [URL] {
        [
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Input Methods"),
            URL(fileURLWithPath: "/Library/Input Methods")
        ]
    }

    public static func installedThirdPartyInputMethodBundles(
        in directories: [URL] = defaultInputMethodDirectories(),
        fileManager: FileManager = .default
    ) -> [InstalledInputMethodBundle] {
        var result: [InstalledInputMethodBundle] = []

        for dir in directories {
            guard let entries = try? fileManager.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            let sortedApps = entries
                .filter { $0.pathExtension.caseInsensitiveCompare("app") == .orderedSame }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }

            for appURL in sortedApps {
                let infoURL = appURL
                    .appendingPathComponent("Contents")
                    .appendingPathComponent("Info.plist")
                guard let infoDict = NSDictionary(contentsOf: infoURL) as? [String: Any],
                      let bundleID = infoDict["CFBundleIdentifier"] as? String,
                      !bundleID.isEmpty else {
                    continue
                }

                var modeIDs: [String] = []
                if let compDict = infoDict["ComponentInputModeDict"] as? [String: Any],
                   let modeList = compDict["tsInputModeListKey"] as? [String: Any] {
                    for modeKey in modeList.keys.sorted() {
                        if let modeDict = modeList[modeKey] as? [String: Any],
                           let tisID = modeDict["TISInputSourceID"] as? String,
                           !tisID.isEmpty {
                            modeIDs.append(tisID)
                        } else if !modeKey.isEmpty {
                            modeIDs.append(modeKey)
                        }
                    }
                }

                result.append(
                    InstalledInputMethodBundle(
                        bundleURL: appURL,
                        bundleID: bundleID,
                        inputSourceIDs: modeIDs
                    )
                )
            }
        }

        return result
    }

    public static func isIntlDataCacheStale(
        kbdxData: Data?,
        installedBundles: [InstalledInputMethodBundle]
    ) -> Bool {
        guard !installedBundles.isEmpty, let kbdxData, !kbdxData.isEmpty else {
            return false
        }

        for bundle in installedBundles {
            if kbdxData.range(of: Data(bundle.bundleID.utf8)) == nil {
                return true
            }
            for modeID in bundle.inputSourceIDs where kbdxData.range(of: Data(modeID.utf8)) == nil {
                return true
            }
        }

        return false
    }

    public static func canResolveInputSource(id: String) -> Bool {
        guard !id.isEmpty else { return false }

        if let copyRef = copyInputSourceRefFn {
            return copyRef(id as CFString)?.takeRetainedValue() != nil
        }

        let query = [kTISPropertyInputSourceID as String: id] as CFDictionary
        if let active = TISCreateInputSourceList(query, false)?.takeRetainedValue() as? [TISInputSource],
           !active.isEmpty {
            return true
        }
        if let all = TISCreateInputSourceList(query, true)?.takeRetainedValue() as? [TISInputSource],
           !all.isEmpty {
            return true
        }
        return false
    }

    private static func darwinUserCacheDirectory() -> URL? {
        var buf = [CChar](repeating: 0, count: Int(PATH_MAX))
        let len = confstr(_CS_DARWIN_USER_CACHE_DIR, &buf, buf.count)
        guard len > 0, len <= buf.count else { return nil }
        let path = String(cString: buf)
        guard !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private static func registerInputMethodBundles(_ bundles: [InstalledInputMethodBundle]) {
        for bundle in bundles {
            let status = TISRegisterInputSource(bundle.bundleURL as CFURL)
            if status != noErr {
                logger.warning("TISRegisterInputSource(\(bundle.bundleID, privacy: .public)) returned \(status)")
            }
        }
    }

    private static func registerInstalledInputMethodsInProcess() {
        let bundles = installedThirdPartyInputMethodBundles()
        guard !bundles.isEmpty else { return }
        registerInputMethodBundles(bundles)
    }

    private static func healStaleInputSourceCacheIfNeeded() {
        let bundles = installedThirdPartyInputMethodBundles()
        guard !bundles.isEmpty else { return }

        var needsRegistration = false
        let fileManager = FileManager.default

        if let cacheDir = darwinUserCacheDirectory() {
            let intlCacheURL = cacheDir.appendingPathComponent("com.apple.IntlDataCache.le")
            let kbdxURL = cacheDir.appendingPathComponent("com.apple.IntlDataCache.le.kbdx")
            if let kbdxData = try? Data(contentsOf: kbdxURL),
               isIntlDataCacheStale(kbdxData: kbdxData, installedBundles: bundles) {
                logger.notice("Detected stale IntlDataCache.le.kbdx; invalidating and refreshing input methods")
                try? fileManager.removeItem(at: intlCacheURL)
                try? fileManager.removeItem(at: kbdxURL)
                needsRegistration = true
            }
        }

        if !needsRegistration {
            let hasUnresolvedMode = bundles.contains { bundle in
                bundle.inputSourceIDs.contains { !canResolveInputSource(id: $0) }
            }
            if hasUnresolvedMode {
                needsRegistration = true
            }
        }

        if needsRegistration {
            registerInputMethodBundles(bundles)
        }
    }

    private static func installCursorUISwizzleIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        guard !isSwizzled else { return }

        let frameworkPath = "/System/Library/PrivateFrameworks/TextInputUIMacHelper.framework/Versions/A/TextInputUIMacHelper"
        _ = dlopen(frameworkPath, RTLD_LAZY)

        guard let ctrlCls: AnyClass = NSClassFromString("TUINSCursorUIController") else {
            return
        }

        let showSel = NSSelectorFromString("showTextInputMenuHUD:")
        if let showMethod = class_getInstanceMethod(ctrlCls, showSel) {
            var origShowIMP: IMP?
            let showBlock: @convention(block) (AnyObject, AnyObject?) -> Void = { controller, payload in
                if let dict = payload as? NSDictionary,
                   let ids = dict["tsmEnabledInputSourceIDs"] as? [String],
                   ids.contains(where: { !canResolveInputSource(id: $0) }) {
                    logger.notice("Unresolved input source in showTextInputMenuHUD; refreshing installed IMEs")
                    registerInstalledInputMethodsInProcess()
                }
                if let imp = origShowIMP {
                    let origShow = unsafeBitCast(imp, to: ShowMenuHUDFn.self)
                    origShow(controller, showSel, payload)
                }
            }
            let newShowIMP = imp_implementationWithBlock(showBlock as Any)
            origShowIMP = method_setImplementation(showMethod, newShowIMP)
        }

        let selectSel = NSSelectorFromString("_selectCurrentInputSource")
        if let selectMethod = class_getInstanceMethod(ctrlCls, selectSel) {
            let switcherSel = NSSelectorFromString("inputSourceSwitcher")
            let inputSourceIDSel = NSSelectorFromString("inputSourceID")
            var origSelectIMP: IMP?

            let selectBlock: @convention(block) (AnyObject) -> Void = { controller in
                let callOriginal: () -> Void = {
                    if let imp = origSelectIMP {
                        let origSelect = unsafeBitCast(imp, to: SelectCurrentInputSourceFn.self)
                        origSelect(controller, selectSel)
                    }
                }

                guard let nsCtrl = controller as? NSObject,
                      nsCtrl.responds(to: switcherSel) else {
                    callOriginal()
                    return
                }

                guard let switcher = nsCtrl.value(forKey: "inputSourceSwitcher") as? NSObject else {
                    return
                }

                guard switcher.responds(to: inputSourceIDSel) else {
                    callOriginal()
                    return
                }

                guard let inputID = switcher.value(forKey: "inputSourceID") as? String,
                      !inputID.isEmpty else {
                    return
                }

                if canResolveInputSource(id: inputID) {
                    callOriginal()
                    return
                }

                registerInstalledInputMethodsInProcess()
                if canResolveInputSource(id: inputID) {
                    callOriginal()
                    return
                }

                logger.error("Blocked TUINSCursorUIController._selectCurrentInputSource for unresolved input source '\(inputID, privacy: .public)' to prevent CFRelease(NULL) crash")
            }
            let newSelectIMP = imp_implementationWithBlock(selectBlock as Any)
            origSelectIMP = method_setImplementation(selectMethod, newSelectIMP)
        }

        isSwizzled = true
    }
}
