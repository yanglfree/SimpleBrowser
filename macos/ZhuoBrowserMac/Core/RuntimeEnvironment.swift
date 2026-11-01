import Foundation

public enum RuntimeEnvironment {
    /// Unit tests must never inherit a user's persisted tab session or write to the
    /// real application-support directory.
    public static let isRunningUnitTests: Bool = {
        let environment = ProcessInfo.processInfo.environment
        if environment["XCTestConfigurationFilePath"] != nil { return true }
        if environment["XCTestBundlePath"] != nil { return true }
        if NSClassFromString("XCTestCase") != nil && environment["ZhuoBrowserForcePersistentState"] == nil {
            // Test bundles link XCTest; guard so we only report true when a test
            // runner is actually driving the process.
            return NSClassFromString("XCTestObservationCenter") != nil
        }
        return false
    }()
}
