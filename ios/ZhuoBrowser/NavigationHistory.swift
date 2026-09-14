import Foundation

enum NavigationHistoryDirection: String {
    case back
    case forward
}

struct NavigationHistoryEntry: Identifiable, Equatable {
    let id: String
    let title: String
    let url: String
    let offset: Int
    let direction: NavigationHistoryDirection

    init(title: String, url: String, offset: Int, direction: NavigationHistoryDirection) {
        self.id = "\(direction.rawValue)-\(offset)-\(url)"
        self.title = title
        self.url = url
        self.offset = offset
        self.direction = direction
    }
}
