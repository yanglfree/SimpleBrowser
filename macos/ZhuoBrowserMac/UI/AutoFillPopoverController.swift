import AppKit
import SwiftUI
import WebKit

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

    /// Presents the AutoFill suggestions below the input field in the target WKWebView.
    public func show(
        in webView: WKWebView,
        fieldRect: CGRect,
        hostname: String,
        isPasswordContext: Bool,
        credentials: [SavedCredential],
        onFill: @escaping (SavedCredential) -> Void,
        onPasskey: @escaping () -> Void
    ) {
        dismiss()
        guard let window = webView.window else { return }
        self.currentWebView = webView

        let rootDomain = SavedCredential.extractRootDomain(from: hostname)

        let rootView = AutoFillSuggestionView(
            credentials: credentials,
            currentHost: hostname,
            rootDomain: rootDomain,
            isPasswordContext: isPasswordContext,
            onSelectCredential: { [weak self] selected in
                self?.dismiss()
                onFill(selected)
            },
            onSelectOtherPasswords: { [weak self] in
                self?.dismiss()
                CredentialStore.shared.openSystemPasswordsSettings()
            },
            onSelectNearbyPasskeys: { [weak self] in
                self?.dismiss()
                onPasskey()
            }
        )

        let hostingView = NSHostingView(rootView: rootView)
        hostingView.layoutSubtreeIfNeeded()
        let fittingSize = hostingView.fittingSize

        // Convert fieldRect (in WebView flipped coordinates) to screen coordinates
        let webViewBounds = webView.bounds
        let clampedY = max(0, min(fieldRect.origin.y, webViewBounds.height))
        let clampedBottom = max(0, min(fieldRect.maxY, webViewBounds.height))
        let fieldRectInWebView = CGRect(
            x: fieldRect.origin.x,
            y: clampedY,
            width: max(20, fieldRect.width),
            height: max(10, fieldRect.height)
        )

        let rectInWindow = webView.convert(fieldRectInWebView, to: nil)
        let rectOnScreen = window.convertToScreen(rectInWindow)

        // Calculate popover origin (anchor right below the field's bottom edge)
        var popoverOriginX = rectOnScreen.origin.x
        var popoverOriginY = rectOnScreen.origin.y - fittingSize.height - 4

        // Prevent falling off screen bottom
        if let screen = window.screen {
            if popoverOriginY < screen.visibleFrame.minY {
                // Flip to top of field if space below is too small
                popoverOriginY = rectOnScreen.origin.y + fieldRect.height + 4
            }
            if popoverOriginX + fittingSize.width > screen.visibleFrame.maxX {
                popoverOriginX = screen.visibleFrame.maxX - fittingSize.width - 10
            }
        }

        let panelRect = NSRect(
            origin: CGPoint(x: popoverOriginX, y: popoverOriginY),
            size: fittingSize
        )

        let newPanel = NSPanel(
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
