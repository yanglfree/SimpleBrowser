import Foundation

struct PageIssueDiagnostic: Identifiable, Equatable {
    let id = UUID()
    let appVersion: String
    let layoutClass: BrowserLayoutClass
    let widthPoints: Int
    let heightPoints: Int
    let loadError: PageLoadErrorKind
    let blockEventCount: Int
    let observableCleanupCount: Int
    let siteOverrideCount: Int

    var summary: String {
        [
            "app_version=\(appVersion)",
            "layout_class=\(layoutClass.rawValue)",
            "window_points=\(widthPoints)x\(heightPoints)",
            "load_error=\(loadError.rawValue)",
            "block_events=\(blockEventCount)",
            "observable_cleanup_count=\(observableCleanupCount)",
            "native_network_event_count=unavailable",
            "site_overrides=\(siteOverrideCount)"
        ].joined(separator: "\n")
    }

    static func create(
        appVersion: String,
        width: Double,
        height: Double,
        loadError: PageLoadErrorKind,
        events: [BlockEvent],
        control: SiteControl
    ) -> PageIssueDiagnostic {
        PageIssueDiagnostic(
            appVersion: appVersion,
            layoutClass: .resolve(width: width),
            widthPoints: Int(width.rounded()),
            heightPoints: Int(height.rounded()),
            loadError: loadError,
            blockEventCount: events.count,
            observableCleanupCount: events.reduce(0) { $0 + max(0, $1.count) },
            siteOverrideCount: [
                control.networkBlocking,
                control.trackerBlocking,
                control.cosmeticCleanup,
                control.autoReader,
                control.darkMode,
                control.desktopUserAgent
            ].filter { $0 != .inherit }.count
        )
    }
}
