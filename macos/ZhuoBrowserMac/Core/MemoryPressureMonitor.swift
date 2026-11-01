import Foundation

/// Coarse system memory pressure, used to shrink the live WebView pool before
/// macOS starts swapping or terminates the WebContent processes on its own.
public enum MemoryPressureLevel: Int, Comparable, CaseIterable {
    case nominal = 0
    case warning = 1
    case critical = 2

    public static func < (lhs: MemoryPressureLevel, rhs: MemoryPressureLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var displayName: String {
        switch self {
        case .nominal: return "正常"
        case .warning: return "偏高"
        case .critical: return "紧张"
        }
    }
}

/// Bridges `DispatchSource.makeMemoryPressureSource` into a main-thread callback.
public final class MemoryPressureMonitor {
    public static let shared = MemoryPressureMonitor()

    public private(set) var level: MemoryPressureLevel = .nominal
    public var onChange: ((MemoryPressureLevel) -> Void)?

    private var source: DispatchSourceMemoryPressure?

    public init() {
        startMonitoring()
    }

    deinit {
        source?.cancel()
    }

    private func startMonitoring() {
        guard source == nil else { return }
        let monitor = DispatchSource.makeMemoryPressureSource(
            eventMask: [.normal, .warning, .critical],
            queue: .main
        )
        monitor.setEventHandler { [weak self, weak monitor] in
            guard let self, let monitor else { return }
            let event = monitor.data
            let newLevel: MemoryPressureLevel
            if event.contains(.critical) {
                newLevel = .critical
            } else if event.contains(.warning) {
                newLevel = .warning
            } else {
                newLevel = .nominal
            }
            self.update(newLevel)
        }
        monitor.resume()
        source = monitor
    }

    private func update(_ newLevel: MemoryPressureLevel) {
        guard newLevel != level else { return }
        level = newLevel
        onChange?(newLevel)
    }
}
