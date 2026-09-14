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

        WindowGroup("浏览窗口", id: "browser-window", for: BrowserWindowRequest.self) { request in
            RootView(windowRequest: request.wrappedValue, isPrimaryWindow: false)
        }
        .commands {
            BrowserCommands()
        }
    }
}
