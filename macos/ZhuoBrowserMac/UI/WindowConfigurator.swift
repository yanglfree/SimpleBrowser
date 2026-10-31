import AppKit
import SwiftUI

/// Invisible NSView helper that configures the hosting NSWindow for seamless full-size content view.
public struct WindowConfigurator: NSViewRepresentable {
    public init() {}

    public static func configure(window: NSWindow) {
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.toolbar = nil
        window.isMovableByWindowBackground = false
    }

    public func makeNSView(context: Context) -> NSView {
        let view = WindowConfiguratorNSView()
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class WindowConfiguratorNSView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window = self.window else { return }
        WindowConfigurator.configure(window: window)
    }
}

/// Transparent AppKit view providing native window dragging and double-click zoom behaviors.
public struct WindowDragBackground: NSViewRepresentable {
    public init() {}

    public func makeNSView(context: Context) -> WindowDragNSView {
        WindowDragNSView()
    }

    public func updateNSView(_ nsView: WindowDragNSView, context: Context) {}
}

public final class WindowDragNSView: NSView {
    public override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            window?.zoom(nil)
        } else {
            window?.performDrag(with: event)
        }
    }
}
