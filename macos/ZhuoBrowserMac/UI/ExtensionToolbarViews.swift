import AppKit
import SwiftUI
import WebKit

/// Chrome-style extension bar embedded in the right side of `UnifiedToolbarView`.
/// Displays pinned extension action buttons (with live badges and popups) plus the Puzzle menu button.
public struct ExtensionToolbarBarView: View {
    @ObservedObject var session: BrowserSession
    @ObservedObject var extensionManager: ExtensionManager

    public init(session: BrowserSession, extensionManager: ExtensionManager = .shared) {
        self.session = session
        self.extensionManager = extensionManager
    }

    private var activeTab: BrowserTab? {
        session.activeTab
    }

    private var currentHost: String {
        guard let url = activeTab?.url else { return "" }
        return URLPolicy.rawHost(url)
    }

    public var body: some View {
        HStack(spacing: 4) {
            // Pinned Extension Action Icons
            ForEach(extensionManager.pinnedToolbarExtensions) { ext in
                PinnedExtensionToolbarButton(
                    session: session,
                    extensionManager: extensionManager,
                    extensionItem: ext,
                    activeTab: activeTab,
                    currentHost: currentHost
                )
            }

            // Chrome-style Puzzle Piece ("扩展程序") Menu Button
            Button(action: {
                extensionManager.activePopupExtensionID = nil
                extensionManager.isShowingToolbarPuzzlePopover.toggle()
            }) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: extensionManager.enabledExtensions.isEmpty ? "puzzlepiece.extension" : "puzzlepiece.extension.fill")
                        .font(.system(size: 13))
                        .foregroundColor(extensionManager.isShowingToolbarPuzzlePopover ? .accentColor : .primary)
                        .frame(width: 24, height: 24)

                    if !extensionManager.enabledExtensions.isEmpty {
                        Text("\(extensionManager.enabledExtensions.count)")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 3.5)
                            .padding(.vertical, 0.5)
                            .background(Capsule().fill(Color.accentColor))
                            .offset(x: 4, y: -2)
                    }
                }
            }
            .buttonStyle(ExtensionToolbarButtonStyle())
            .help("扩展程序菜单 · 已启用 \(extensionManager.enabledExtensions.count) 个扩展 (Cmd+Shift+E)")
            .popover(
                isPresented: $extensionManager.isShowingToolbarPuzzlePopover,
                attachmentAnchor: .rect(.bounds),
                arrowEdge: .bottom
            ) {
                ExtensionsMenuPopoverView(
                    session: session,
                    extensionManager: extensionManager,
                    isPresented: $extensionManager.isShowingToolbarPuzzlePopover
                )
            }
        }
    }
}

/// A single pinned extension icon button in the toolbar, supporting badges, popups, and right-click context menus.
private struct PinnedExtensionToolbarButton: View {
    @ObservedObject var session: BrowserSession
    @ObservedObject var extensionManager: ExtensionManager
    let extensionItem: InstalledExtension
    let activeTab: BrowserTab?
    let currentHost: String

    private var isShowingPopupBinding: Binding<Bool> {
        Binding(
            get: { extensionManager.activePopupExtensionID == extensionItem.id },
            set: { newValue in
                if newValue {
                    extensionManager.activePopupExtensionID = extensionItem.id
                } else if extensionManager.activePopupExtensionID == extensionItem.id {
                    extensionManager.activePopupExtensionID = nil
                }
            }
        )
    }

    private var badgeText: String {
        extensionItem.actionState.badgeText(forTabID: activeTab?.id)
    }

    private var badgeColor: Color {
        ExtensionColorHelper.color(fromHex: extensionItem.actionState.badgeColorHex(forTabID: activeTab?.id))
            ?? ExtensionColorHelper.color(fromHex: extensionItem.accentColorHex)
            ?? Color.accentColor
    }

    private var accentColor: Color {
        ExtensionColorHelper.color(fromHex: extensionItem.accentColorHex) ?? Color.accentColor
    }

    private var canRunOnCurrentTab: Bool {
        guard let tab = activeTab, !tab.isHome else { return false }
        return extensionItem.canRunOn(url: tab.url, isPrivateTab: tab.isPrivate)
    }

    var body: some View {
        Button(action: {
            extensionManager.triggerExtensionAction(id: extensionItem.id, in: session)
        }) {
            ZStack(alignment: .bottomTrailing) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(accentColor.opacity(0.14))
                        .frame(width: 22, height: 22)

                    if let customIcon = extensionManager.icon(for: extensionItem) {
                        Image(nsImage: customIcon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 15, height: 15)
                    } else {
                        Image(systemName: extensionItem.sfSymbolFallback)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundColor(accentColor)
                    }
                }
                .frame(width: 24, height: 24)

                if !badgeText.isEmpty {
                    Text(badgeText.prefix(4))
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 0.5)
                        .background(Capsule().fill(badgeColor))
                        .offset(x: 4, y: 2)
                } else if canRunOnCurrentTab {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 5, height: 5)
                        .offset(x: -1, y: -1)
                }
            }
        }
        .buttonStyle(ExtensionToolbarButtonStyle())
        .help("\(extensionItem.displayTitle) (v\(extensionItem.manifest.version))")
        .contextMenu {
            Text("\(extensionItem.manifest.name) v\(extensionItem.manifest.version)")
            Divider()

            if !currentHost.isEmpty {
                let isHostBlocked = extensionItem.blockedHosts.contains(currentHost)
                Button(isHostBlocked ? "在 \(currentHost) 上恢复启用" : "在 \(currentHost) 上暂停运行") {
                    extensionManager.toggleBlockHost(id: extensionItem.id, host: currentHost)
                }
            }

            Menu("网站访问权限 (\(extensionItem.hostAccessMode.shortLabel))") {
                ForEach(ExtensionHostAccessMode.allCases) { mode in
                    Button(action: {
                        extensionManager.setHostAccessMode(id: extensionItem.id, mode: mode)
                    }) {
                        HStack {
                            Text(mode.displayName)
                            if extensionItem.hostAccessMode == mode {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            if extensionItem.manifest.optionsPage != nil {
                Button("扩展选项 (Options)...") {
                    extensionManager.openOptionsPage(forExtensionID: extensionItem.id, in: session)
                }
            }

            Button("从工具栏取消固定") {
                extensionManager.togglePinToToolbar(id: extensionItem.id)
            }

            Button("重新加载扩展") {
                _ = extensionManager.reloadExtension(id: extensionItem.id)
            }

            Divider()

            Button("管理扩展程序...") {
                extensionManager.inspectingExtensionID = extensionItem.id
                extensionManager.isShowingExtensionManager = true
            }

            Button("禁用此扩展", role: .destructive) {
                extensionManager.setExtensionEnabled(id: extensionItem.id, enabled: false)
            }
        }
        .popover(
            isPresented: isShowingPopupBinding,
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .bottom
        ) {
            ExtensionPopupPopoverView(
                session: session,
                extensionManager: extensionManager,
                extensionItem: extensionItem,
                isPresented: isShowingPopupBinding
            )
        }
    }
}

/// Popover hosting a live `WKWebView` rendering the extension's `default_popup` (`zhuo-extension://<id>/popup.html`).
public struct ExtensionPopupPopoverView: View {
    @ObservedObject var session: BrowserSession
    @ObservedObject var extensionManager: ExtensionManager
    let extensionItem: InstalledExtension
    @Binding var isPresented: Bool

    public var body: some View {
        VStack(spacing: 0) {
            // Compact Extension Popup Header
            HStack(spacing: 8) {
                Image(systemName: extensionItem.sfSymbolFallback)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(ExtensionColorHelper.color(fromHex: extensionItem.accentColorHex) ?? .accentColor)

                Text(extensionItem.manifest.name)
                    .font(.system(size: 11.5, weight: .semibold))
                    .lineLimit(1)

                Spacer()

                if extensionItem.manifest.optionsPage != nil {
                    Button(action: {
                        isPresented = false
                        extensionManager.openOptionsPage(forExtensionID: extensionItem.id, in: session)
                    }) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("打开扩展选项页")
                }

                Button(action: {
                    _ = extensionManager.reloadExtension(id: extensionItem.id)
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("重新加载此扩展")

                Button(action: {
                    isPresented = false
                    extensionManager.inspectingExtensionID = extensionItem.id
                    extensionManager.isShowingExtensionManager = true
                }) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("查看扩展权限与详情")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            if let popupURL = extensionItem.popupURL {
                ExtensionPopupWebView(
                    popupURL: popupURL,
                    extensionManager: extensionManager,
                    activeTabID: session.activeTabID
                )
                .frame(width: 340, height: 390)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: extensionItem.sfSymbolFallback)
                        .font(.system(size: 28))
                        .foregroundColor(.accentColor)
                    Text(extensionItem.manifest.name)
                        .font(.system(size: 13, weight: .bold))
                    Text(extensionItem.manifest.description ?? "此扩展在后台或页面加载时自动运行。")
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(20)
                .frame(width: 280, height: 180)
            }
        }
    }
}

/// `NSViewRepresentable` wrapping a `WKWebView` configured with `zhuo-extension://` scheme handler
/// and `ExtensionRuntimeBridge` script message handler for extension popups.
public struct ExtensionPopupWebView: NSViewRepresentable {
    public let popupURL: URL
    public let extensionManager: ExtensionManager
    public let activeTabID: String?

    public final class Coordinator: NSObject, WKScriptMessageHandler {
        weak var extensionManager: ExtensionManager?
        weak var webView: WKWebView?
        var activeTabID: String?
        var loadedURL: URL?

        init(extensionManager: ExtensionManager, activeTabID: String?) {
            self.extensionManager = extensionManager
            self.activeTabID = activeTabID
        }

        public func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            extensionManager?.handleScriptMessage(message, sourceWebView: webView, tabID: activeTabID)
        }
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(extensionManager: extensionManager, activeTabID: activeTabID)
    }

    public func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let schemeHandler = ExtensionSchemeHandler(extensionManager: extensionManager)
        config.setURLSchemeHandler(schemeHandler, forURLScheme: ExtensionSchemeHandler.scheme)
        config.userContentController.add(context.coordinator, name: ExtensionRuntimeBridge.messageHandlerName)

        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }
        context.coordinator.webView = webView
        context.coordinator.loadedURL = popupURL
        extensionManager.activePopupWebView = webView
        webView.load(URLRequest(url: popupURL))
        return webView
    }

    public func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.activeTabID = activeTabID
        if context.coordinator.loadedURL != popupURL {
            context.coordinator.loadedURL = popupURL
            webView.load(URLRequest(url: popupURL))
        }
    }

    public static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: ExtensionRuntimeBridge.messageHandlerName
        )
        if coordinator.extensionManager?.activePopupWebView === webView {
            coordinator.extensionManager?.activePopupWebView = nil
        }
    }
}

/// Chrome-style Puzzle dropdown menu listing all installed extensions with quick pin, toggle, and management actions.
public struct ExtensionsMenuPopoverView: View {
    @ObservedObject var session: BrowserSession
    @ObservedObject var extensionManager: ExtensionManager
    @Binding var isPresented: Bool

    private var currentHost: String {
        guard let url = session.activeTab?.url else { return "" }
        return URLPolicy.rawHost(url)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "puzzlepiece.extension.fill")
                        .foregroundColor(.accentColor)
                        .font(.system(size: 13))
                    Text("扩展程序 (Extensions)")
                        .font(.system(size: 13, weight: .bold))
                }
                Spacer()
                Text("\(extensionManager.enabledExtensions.count)/\(extensionManager.extensions.count) 已启用")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            // Extensions List
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 4) {
                    ForEach(extensionManager.extensions) { ext in
                        extensionRow(ext)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .frame(maxHeight: 300)

            Divider()

            // Footer Actions
            VStack(spacing: 4) {
                Button(action: {
                    isPresented = false
                    extensionManager.isShowingCreatorSheet = true
                    extensionManager.isShowingExtensionManager = true
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.square.on.square")
                            .font(.system(size: 12))
                            .frame(width: 16)
                        Text("新建自定义脚本 / 扩展...")
                            .font(.system(size: 12))
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(ExtensionMenuRowButtonStyle())

                Button(action: {
                    isPresented = false
                    extensionManager.promptInstallExtensionPackage()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 12))
                            .frame(width: 16)
                        Text("安装 CRX / ZIP / .user.js 脚本...")
                            .font(.system(size: 12))
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(ExtensionMenuRowButtonStyle())

                Button(action: {
                    isPresented = false
                    extensionManager.isShowingExtensionManager = true
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "gearshape.2")
                            .font(.system(size: 12))
                            .frame(width: 16)
                        Text("管理所有扩展程序...")
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        Text("⌘⇧E")
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(ExtensionMenuRowButtonStyle())
            }
            .padding(8)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 340)
    }

    @ViewBuilder
    private func extensionRow(_ ext: InstalledExtension) -> some View {
        let accent = ExtensionColorHelper.color(fromHex: ext.accentColorHex) ?? Color.accentColor
        let badge = ext.actionState.badgeText(forTabID: session.activeTabID)

        HStack(spacing: 10) {
            // Clickable area to trigger popup or action
            Button(action: {
                if !ext.isEnabled {
                    extensionManager.setExtensionEnabled(id: ext.id, enabled: true)
                }
                isPresented = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    extensionManager.triggerExtensionAction(id: ext.id, in: session)
                }
            }) {
                HStack(spacing: 9) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 7)
                            .fill(accent.opacity(ext.isEnabled ? 0.16 : 0.07))
                            .frame(width: 28, height: 28)

                        if let customIcon = extensionManager.icon(for: ext) {
                            Image(nsImage: customIcon)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 18, height: 18)
                        } else {
                            Image(systemName: ext.sfSymbolFallback)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(ext.isEnabled ? accent : .secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 1.5) {
                        HStack(spacing: 5) {
                            Text(ext.manifest.name)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(ext.isEnabled ? .primary : .secondary)
                                .lineLimit(1)

                            if !badge.isEmpty && ext.isEnabled {
                                Text(badge)
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 0.5)
                                    .background(Capsule().fill(accent))
                            }
                        }

                        Text(statusSubtitle(for: ext))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Pin / Unpin button
            Button(action: {
                extensionManager.togglePinToToolbar(id: ext.id)
            }) {
                Image(systemName: ext.isPinnedToToolbar ? "pin.fill" : "pin")
                    .font(.system(size: 11.5))
                    .foregroundColor(ext.isPinnedToToolbar ? .accentColor : .secondary.opacity(0.6))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help(ext.isPinnedToToolbar ? "从工具栏取消固定" : "固定到工具栏")

            // Enable / Disable switch
            Toggle("", isOn: Binding(
                get: { ext.isEnabled },
                set: { extensionManager.setExtensionEnabled(id: ext.id, enabled: $0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.secondary.opacity(0.06))
        )
    }

    private func statusSubtitle(for ext: InstalledExtension) -> String {
        guard ext.isEnabled else { return "已禁用 · 点击启用" }
        if !currentHost.isEmpty && ext.blockedHosts.contains(currentHost) {
            return "已在 \(currentHost) 暂停"
        }
        return "\(ext.sourceKind.displayName) · \(ext.hostAccessMode.shortLabel)"
    }
}

// MARK: - Shared Styling Helpers

public enum ExtensionColorHelper {
    public static func color(fromHex hex: String) -> Color? {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if cleaned.hasPrefix("#") {
            cleaned.removeFirst()
        }
        guard cleaned.count == 6, let rgb = UInt64(cleaned, radix: 16) else {
            return nil
        }
        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8) & 0xFF) / 255.0
        let b = Double(rgb & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }
}

private struct ExtensionToolbarButtonStyle: ButtonStyle {
    @State private var isHovered: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(configuration.isPressed ? Color.secondary.opacity(0.18) : (isHovered ? Color.secondary.opacity(0.1) : Color.clear))
            )
            .scaleEffect(configuration.isPressed ? 0.92 : (isHovered ? 1.04 : 1.0))
            .animation(.spring(response: 0.2, dampingFraction: 0.75), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

private struct ExtensionMenuRowButtonStyle: ButtonStyle {
    @State private var isHovered: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.accentColor.opacity(0.12) : Color.clear)
            )
            .onHover { hovering in
                isHovered = hovering
            }
    }
}
