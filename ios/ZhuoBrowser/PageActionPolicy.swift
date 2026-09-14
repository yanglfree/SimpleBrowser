import Foundation

struct PageActionContext: Equatable {
    let isHome: Bool
    let isPrivate: Bool
    let isDesktop: Bool

    init(url: String, isPrivate: Bool, isDesktop: Bool) {
        isHome = URLPolicy.isHomeURL(url)
        self.isPrivate = isPrivate
        self.isDesktop = isDesktop
    }

    var isBrowsing: Bool {
        !isHome
    }
}
