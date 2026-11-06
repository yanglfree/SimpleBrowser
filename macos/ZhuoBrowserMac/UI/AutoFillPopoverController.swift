import AppKit
import SwiftUI
import WebKit

/// Custom NSHostingView that guarantees immediate first-click event delivery even in non-activating panels.
final class AutoFillHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
}

/// Lightweight floating panel that never steals keyboard focus from the active web input.
final class AutoFillPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Manages the floating AutoFill suggestion panel positioned directly beneath the focused input field.
@MainActor
public final class AutoFillPopoverController: NSObject {
    public static let shared = AutoFillPopoverController()

    private var panel: NSPanel?
    private weak var currentWebView: WKWebView?
    private var dismissEventMonitor: Any?

    private override init() {
        super.init()
    }

    /// Presents the saved-password suggestions below the input field in the target WKWebView.
    public func show(
        in webView: WKWebView,
        fieldRect: CGRect,
        hostname: String,
        credentials: [SavedCredential],
        onSelect: @escaping (SavedCredential) -> Void
    ) {
        dismiss()
        guard let window = webView.window else { return }
        self.currentWebView = webView

        let rootView = AutoFillSuggestionView(
            credentials: credentials,
            currentHost: hostname,
            onSelectCredential: { [weak self] selected in
                self?.dismiss()
                onSelect(selected)
            }
        )

        let hostingView = AutoFillHostingView(rootView: rootView)
        hostingView.layoutSubtreeIfNeeded()
        let fittingSize = hostingView.fittingSize

        // Convert field coordinates (in webView flipped space) to screen coordinates
        let bottomPointInWebView = CGPoint(x: fieldRect.origin.x, y: fieldRect.maxY)
        let bottomPointInWindow = webView.convert(bottomPointInWebView, to: nil)
        let bottomPointOnScreen = window.convertToScreen(NSRect(origin: bottomPointInWindow, size: .zero)).origin

        var popoverOriginX = bottomPointOnScreen.x
        var popoverOriginY = bottomPointOnScreen.y - fittingSize.height - 4

        // Prevent falling off screen bottom; flip above input if needed
        if let screen = window.screen {
            if popoverOriginY < screen.visibleFrame.minY {
                let topPointInWebView = CGPoint(x: fieldRect.origin.x, y: fieldRect.origin.y)
                let topPointInWindow = webView.convert(topPointInWebView, to: nil)
                let topPointOnScreen = window.convertToScreen(NSRect(origin: topPointInWindow, size: .zero)).origin
                popoverOriginY = topPointOnScreen.y + 4
            }
            if popoverOriginX + fittingSize.width > screen.visibleFrame.maxX {
                popoverOriginX = screen.visibleFrame.maxX - fittingSize.width - 10
            }
            if popoverOriginX < screen.visibleFrame.minX {
                popoverOriginX = screen.visibleFrame.minX + 10
            }
        }

        let panelRect = NSRect(
            origin: CGPoint(x: popoverOriginX, y: popoverOriginY),
            size: fittingSize
        )

        let newPanel = AutoFillPanel(
            contentRect: panelRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        newPanel.isOpaque = false
        newPanel.backgroundColor = .clear
        newPanel.hasShadow = true
        newPanel.level = .floating
        newPanel.contentView = hostingView
        newPanel.isReleasedWhenClosed = false
        newPanel.acceptsMouseMovedEvents = true

        window.addChildWindow(newPanel, ordered: .above)
        newPanel.orderFront(nil)
        self.panel = newPanel

        // Dismiss monitor on outside click
        dismissEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, let panel = self.panel else { return event }
            let clickLocation = NSEvent.mouseLocation
            if !panel.frame.contains(clickLocation) {
                self.dismiss()
            }
            return event
        }
    }

    /// Dismisses the suggestion panel.
    public func dismiss() {
        if let monitor = dismissEventMonitor {
            NSEvent.removeMonitor(monitor)
            dismissEventMonitor = nil
        }
        if let panel = panel {
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
            self.panel = nil
        }
        currentWebView = nil
    }

    public var isVisible: Bool {
        panel != nil
    }
}
