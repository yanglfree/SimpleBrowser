import AppKit
import SwiftUI

/// Invisible NSView helper that configures the hosting NSWindow for seamless full-size content view
/// and registers its lifecycle with `ProfileManager` when a `profileID` is provided.
public struct WindowConfigurator: NSViewRepresentable {
    public let profileID: UUID?

    public init(profileID: UUID? = nil) {
        self.profileID = profileID
    }

    public static func configure(window: NSWindow) {
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.toolbar = nil
        window.isMovableByWindowBackground = false
    }

    public func makeNSView(context: Context) -> NSView {
        let view = WindowConfiguratorNSView()
        view.profileID = profileID
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        if let configuratorView = nsView as? WindowConfiguratorNSView {
            configuratorView.profileID = profileID
            configuratorView.registerCurrentWindowIfNeeded()
        }
    }
}

private final class WindowConfiguratorNSView: NSView {
    var profileID: UUID?
    private weak var observedWindow: NSWindow?
    private var becomeKeyObserver: NSObjectProtocol?
    private var willCloseObserver: NSObjectProtocol?

    deinit {
        removeWindowObservers()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window = self.window else {
            removeWindowObservers()
            return
        }
        WindowConfigurator.configure(window: window)
        registerCurrentWindowIfNeeded()
    }

    func registerCurrentWindowIfNeeded() {
        guard let window = self.window, let profileID else { return }
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, self.window === window else { return }
            ProfileManager.shared.registerWindow(window, forProfileID: profileID)
        }
        guard observedWindow !== window else { return }
        removeWindowObservers()
        observedWindow = window

        becomeKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            guard let id = self?.profileID else { return }
            ProfileManager.shared.markProfileFocused(id)
        }

        willCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            guard let id = self?.profileID else { return }
            ProfileManager.shared.handleWindowClosing(forProfileID: id)
        }
    }

    private func removeWindowObservers() {
        if let becomeKeyObserver {
            NotificationCenter.default.removeObserver(becomeKeyObserver)
            self.becomeKeyObserver = nil
        }
        if let willCloseObserver {
            NotificationCenter.default.removeObserver(willCloseObserver)
            self.willCloseObserver = nil
        }
        observedWindow = nil
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
    public override var mouseDownCanMoveWindow: Bool {
        true
    }

    public override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            window?.zoom(nil)
        } else {
            window?.performDrag(with: event)
        }
    }
}
