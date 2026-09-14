import Foundation

enum TabThumbnailPolicy {
    static let snapshotWidth = 360.0
    static let snapshotAspectRatio = 16.0 / 9.0

    static func shouldCapture(
        url: String,
        isPrivate: Bool,
        isAttached: Bool,
        viewWidth: Double,
        viewHeight: Double
    ) -> Bool {
        !URLPolicy.isHomeURL(url)
            && !isPrivate
            && isAttached
            && viewWidth > 0
            && viewHeight > 0
    }

    static func visibleSnapshotHeight(viewWidth: Double, viewHeight: Double) -> Double {
        guard viewWidth > 0, viewHeight > 0 else { return 0 }
        return min(viewHeight, viewWidth / snapshotAspectRatio)
    }
}
