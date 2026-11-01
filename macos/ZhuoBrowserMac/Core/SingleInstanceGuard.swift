import AppKit
import Foundation
import Darwin

/// Ensures only a single instance of ZhuoBrowser runs per user session.
///
/// When a secondary instance is launched (e.g. via Xcode run, terminal, secondary build,
/// or `open -n`):
/// 1. The secondary instance detects the primary instance via bundle identifier and file lock.
/// 2. If URLs or paths were passed to the secondary instance, they are forwarded to the primary
///    instance via NSWorkspace URL dispatch.
/// 3. The secondary instance activates the primary instance (bringing its window to the foreground).
/// 4. The secondary instance exits immediately without initializing UI or state.
public final class SingleInstanceGuard {
    public static let shared = SingleInstanceGuard()

    public static let lockFileName = ".instance.lock"

    private var lockFileDescriptor: Int32 = -1

    public init() {}

    deinit {
        releaseLock()
    }

    /// Enforces single-instance behavior.
    /// If another instance of the browser is already running, this process activates that
    /// instance, forwards any URL arguments, and terminates this process immediately.
    public func enforceSingleInstanceOrExit() {
        guard !RuntimeEnvironment.isRunningUnitTests else { return }

        let bundleID = Bundle.main.bundleIdentifier ?? "com.youdroid.zhuobrowser.mac"
        let currentPID = ProcessInfo.processInfo.processIdentifier

        // 1. Check for running applications sharing the same bundle identifier.
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        let otherApps = runningApps.filter { $0.processIdentifier != currentPID && !$0.isTerminated }

        // 2. Attempt atomic file lock in Application Support.
        let lockAcquired = acquireLock(currentPID: currentPID)

        if !otherApps.isEmpty || !lockAcquired {
            handleSecondaryInstanceAndExit(bundleID: bundleID, otherApps: otherApps)
        }
    }

    /// Releases the process singleton lock file descriptor.
    public func releaseLock() {
        if lockFileDescriptor >= 0 {
            flock(lockFileDescriptor, LOCK_UN)
            close(lockFileDescriptor)
            lockFileDescriptor = -1
        }
    }

    // MARK: - Lock File & Arguments Helpers

    /// Attempts to acquire an exclusive non-blocking advisory lock on the lock file.
    public func acquireLock(customLockURL: URL? = nil, currentPID: pid_t = ProcessInfo.processInfo.processIdentifier) -> Bool {
        guard let lockURL = customLockURL ?? defaultLockFileURL() else { return true }

        let directory = lockURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)

        let fd = open(lockURL.path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { return true }

        let lockResult = flock(fd, LOCK_EX | LOCK_NB)
        if lockResult == 0 {
            lockFileDescriptor = fd
            ftruncate(fd, 0)
            lseek(fd, 0, SEEK_SET)
            let pidString = "\(currentPID)\n"
            pidString.withCString { ptr in
                _ = write(fd, ptr, strlen(ptr))
            }
            return true
        } else {
            close(fd)
            return false
        }
    }

    /// Extracts potential URLs from command-line arguments.
    public static func extractURLs(from arguments: [String]) -> [String] {
        guard arguments.count > 1 else { return [] }

        var urls: [String] = []
        for arg in arguments.dropFirst() {
            if arg.hasPrefix("-") { continue }
            let trimmed = arg.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.contains("://") || (trimmed.contains(".") && !trimmed.contains(" ") && !trimmed.hasPrefix("/")) {
                urls.append(trimmed)
            }
        }
        return urls
    }

    // MARK: - Internal

    private func handleSecondaryInstanceAndExit(bundleID: String, otherApps: [NSRunningApplication]) -> Never {
        let rawURLs = Self.extractURLs(from: CommandLine.arguments)
        let urlsToOpen: [URL] = rawURLs.compactMap { raw in
            if let direct = URL(string: raw), direct.scheme != nil {
                return direct
            }
            return URL(string: "https://\(raw)")
        }

        let targetApp = otherApps.first ?? findAppFromLockFile()

        if let targetApp = targetApp, let bundleURL = targetApp.bundleURL {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.open(urlsToOpen, withApplicationAt: bundleURL, configuration: config, completionHandler: nil)

            if #available(macOS 14.0, *) {
                NSApplication.shared.yieldActivation(to: targetApp)
                targetApp.activate()
            } else {
                targetApp.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            }
        } else if let targetApp = targetApp {
            if #available(macOS 14.0, *) {
                NSApplication.shared.yieldActivation(to: targetApp)
                targetApp.activate()
            } else {
                targetApp.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            }
        }

        // Allow LaunchServices open request to dispatch before process exit
        Thread.sleep(forTimeInterval: 0.1)
        exit(0)
    }

    private func findAppFromLockFile() -> NSRunningApplication? {
        guard let lockURL = defaultLockFileURL(),
              let content = try? String(contentsOf: lockURL, encoding: .utf8) else {
            return nil
        }
        let firstLine = content.components(separatedBy: .newlines).first ?? ""
        if let pid = pid_t(firstLine.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return NSRunningApplication(processIdentifier: pid)
        }
        return nil
    }

    private func defaultLockFileURL() -> URL? {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        guard let base = appSupport else { return nil }
        return base.appendingPathComponent("ZhuoBrowserMac", isDirectory: true).appendingPathComponent(Self.lockFileName)
    }
}
