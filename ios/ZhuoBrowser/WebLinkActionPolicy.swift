import Foundation

enum WebLinkActionPolicy {
    static func webURL(_ url: URL?) -> URL? {
        guard let url,
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host?.isEmpty == false else {
            return nil
        }
        return url
    }

    static func canSaveForLater(isPrivate: Bool) -> Bool {
        !isPrivate
    }
}
