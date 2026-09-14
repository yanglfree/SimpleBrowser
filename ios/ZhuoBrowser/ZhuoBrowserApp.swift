import SwiftUI

@main
struct ZhuoBrowserApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .commands {
            BrowserCommands()
        }
    }
}
