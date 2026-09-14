enum PageRefreshPolicy {
    static func isEnabled(
        isBrowsing: Bool,
        isReader: Bool,
        isLoading: Bool,
        hasLoadError: Bool
    ) -> Bool {
        isBrowsing && !isReader && !isLoading && !hasLoadError
    }
}
