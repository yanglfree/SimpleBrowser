import AppKit
import SwiftUI

/// AppKit-backed NSTextField subclass that selects all text when initially clicked from an unfocused state,
/// matching native macOS Safari / Chrome address bar behavior.
public final class OmniboxNSTextField: NSTextField {
    var shouldSelectAllOnMouseUp: Bool = false
    var onFocusBegan: (() -> Void)?

    public override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became {
            onFocusBegan?()
        }
        return became
    }

    public override func mouseDown(with event: NSEvent) {
        let wasAlreadyEditing = (window?.firstResponder != nil) && (window?.firstResponder === currentEditor())
        if !wasAlreadyEditing {
            onFocusBegan?()
        }
        shouldSelectAllOnMouseUp = !wasAlreadyEditing && !stringValue.isEmpty
        super.mouseDown(with: event)
        if shouldSelectAllOnMouseUp {
            shouldSelectAllOnMouseUp = false
            selectText(nil)
        }
    }
}

/// Native macOS Omnibox text field with inline URL autocomplete, IME composition safety,
/// and keyboard navigation (`↑`, `↓`, `Tab`, `→`, `Return`, `Esc`).
public struct MacOmniboxTextField: NSViewRepresentable {
    @Binding public var text: String
    @Binding public var isFocused: Bool
    public let placeholder: String
    public var font: NSFont = .systemFont(ofSize: 13)
    public var textColor: NSColor = .labelColor
    public var inlineCompletionProvider: ((String) -> String?)?
    public var onUserInput: (String) -> Void
    public var onMoveSelection: (Int) -> Bool
    public var onAcceptSuggestion: () -> Bool
    public var onCancelSuggestions: () -> Bool
    public var onSubmit: (String) -> Void

    public init(
        text: Binding<String>,
        isFocused: Binding<Bool>,
        placeholder: String,
        font: NSFont = .systemFont(ofSize: 13),
        textColor: NSColor = .labelColor,
        inlineCompletionProvider: ((String) -> String?)? = nil,
        onUserInput: @escaping (String) -> Void = { _ in },
        onMoveSelection: @escaping (Int) -> Bool = { _ in false },
        onAcceptSuggestion: @escaping () -> Bool = { false },
        onCancelSuggestions: @escaping () -> Bool = { false },
        onSubmit: @escaping (String) -> Void
    ) {
        self._text = text
        self._isFocused = isFocused
        self.placeholder = placeholder
        self.font = font
        self.textColor = textColor
        self.inlineCompletionProvider = inlineCompletionProvider
        self.onUserInput = onUserInput
        self.onMoveSelection = onMoveSelection
        self.onAcceptSuggestion = onAcceptSuggestion
        self.onCancelSuggestions = onCancelSuggestions
        self.onSubmit = onSubmit
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public func makeNSView(context: Context) -> OmniboxNSTextField {
        let field = OmniboxNSTextField()
        field.delegate = context.coordinator
        field.onFocusBegan = { [weak coordinator = context.coordinator] in
            coordinator?.handleFocusBegan()
        }
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = font
        field.textColor = textColor
        field.placeholderString = placeholder
        field.lineBreakMode = .byTruncatingTail
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    public func updateNSView(_ field: OmniboxNSTextField, context: Context) {
        context.coordinator.parent = self

        if field.font != font {
            field.font = font
        }
        if field.textColor != textColor {
            field.textColor = textColor
        }
        if field.placeholderString != placeholder {
            field.placeholderString = placeholder
        }

        let editor = field.currentEditor() as? NSTextView
        let isEditing = editor != nil
        let hasMarkedText = editor?.hasMarkedText() ?? false

        if !hasMarkedText {
            if isEditing,
               context.coordinator.lastUserQuery == text,
               let inlineDisplay = context.coordinator.activeInlineDisplayedString,
               field.stringValue == inlineDisplay {
                // Keep active inline completion and selection range untouched while typing forward
            } else if field.stringValue != text {
                field.stringValue = text
                context.coordinator.lastUserQuery = text
                context.coordinator.activeInlineDisplayedString = nil
                if let editor {
                    let end = (text as NSString).length
                    editor.setSelectedRange(NSRange(location: end, length: 0))
                }
            }
        }

        if isFocused && !isEditing {
            DispatchQueue.main.async { [weak field, weak coordinator = context.coordinator] in
                guard let field, let window = field.window, let coordinator else { return }
                guard coordinator.parent.isFocused else { return }
                if window.firstResponder !== field.currentEditor() {
                    window.makeFirstResponder(field)
                    if !field.stringValue.isEmpty {
                        field.selectText(nil)
                    }
                }
            }
        } else if !isFocused && isEditing {
            DispatchQueue.main.async { [weak field, weak coordinator = context.coordinator] in
                guard let field, let window = field.window, let coordinator else { return }
                guard !coordinator.parent.isFocused else { return }
                if window.firstResponder === field.currentEditor() {
                    window.makeFirstResponder(nil)
                }
            }
        }
    }

    public final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: MacOmniboxTextField
        var lastUserQuery: String = ""
        var activeInlineDisplayedString: String?
        private var isDeletingBackwardOrForward: Bool = false

        init(_ parent: MacOmniboxTextField) {
            self.parent = parent
            self.lastUserQuery = parent.text
        }

        func handleFocusBegan() {
            if !parent.isFocused {
                parent.isFocused = true
            }
        }

        public func controlTextDidBeginEditing(_ obj: Notification) {
            handleFocusBegan()
        }

        public func controlTextDidEndEditing(_ obj: Notification) {
            activeInlineDisplayedString = nil
            // Defer focus state teardown by one runloop tick so clicks on suggestion rows
            // inside the dropdown panel register cleanly before the panel disappears.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.parent.isFocused {
                    self.parent.isFocused = false
                }
            }
        }

        public func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            let editor = field.currentEditor() as? NSTextView
            let hasMarkedText = editor?.hasMarkedText() ?? false
            let currentString = field.stringValue
            let wasDeletion = isDeletingBackwardOrForward
            isDeletingBackwardOrForward = false

            lastUserQuery = currentString
            activeInlineDisplayedString = nil
            if parent.text != currentString {
                parent.text = currentString
            }
            parent.onUserInput(currentString)

            guard !wasDeletion,
                  !hasMarkedText,
                  !currentString.isEmpty,
                  let editor,
                  let completed = parent.inlineCompletionProvider?(currentString) else {
                return
            }

            let rawLength = (currentString as NSString).length
            let completedLength = (completed as NSString).length
            let currentSelection = editor.selectedRange()

            guard completedLength > rawLength,
                  completed.lowercased().hasPrefix(currentString.lowercased()),
                  currentSelection.location == rawLength,
                  currentSelection.length == 0 else {
                return
            }

            activeInlineDisplayedString = completed
            field.stringValue = completed
            editor.setSelectedRange(NSRange(location: rawLength, length: completedLength - rawLength))
        }

        public func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.deleteBackward(_:))
                || commandSelector == #selector(NSResponder.deleteForward(_:))
                || commandSelector == #selector(NSResponder.deleteWordBackward(_:))
                || commandSelector == #selector(NSResponder.deleteToBeginningOfLine(_:)) {
                isDeletingBackwardOrForward = true
                return false
            }

            if commandSelector == #selector(NSResponder.moveDown(_:)) {
                return parent.onMoveSelection(1)
            }

            if commandSelector == #selector(NSResponder.moveUp(_:)) {
                return parent.onMoveSelection(-1)
            }

            if commandSelector == #selector(NSResponder.insertTab(_:)) {
                let selection = textView.selectedRange()
                let totalLength = (control.stringValue as NSString).length
                if selection.length > 0 && NSMaxRange(selection) == totalLength {
                    acceptInlineSelection(in: control, textView: textView)
                    return true
                }
                if parent.onAcceptSuggestion() {
                    return true
                }
                return false
            }

            if commandSelector == #selector(NSResponder.moveRight(_:)) {
                let selection = textView.selectedRange()
                let totalLength = (control.stringValue as NSString).length
                if activeInlineDisplayedString != nil && selection.length > 0 && NSMaxRange(selection) == totalLength {
                    acceptInlineSelection(in: control, textView: textView)
                    return true
                }
                return false
            }

            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                let committed = control.stringValue
                activeInlineDisplayedString = nil
                lastUserQuery = committed
                if parent.text != committed {
                    parent.text = committed
                }
                parent.onSubmit(committed)
                control.window?.makeFirstResponder(nil)
                return true
            }

            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                if activeInlineDisplayedString != nil && control.stringValue != lastUserQuery {
                    let restored = lastUserQuery
                    activeInlineDisplayedString = nil
                    control.stringValue = restored
                    let end = (restored as NSString).length
                    textView.setSelectedRange(NSRange(location: end, length: 0))
                }
                if parent.onCancelSuggestions() {
                    return true
                }
                control.window?.makeFirstResponder(nil)
                return true
            }

            return false
        }

        private func acceptInlineSelection(in control: NSControl, textView: NSTextView) {
            let accepted = control.stringValue
            let end = (accepted as NSString).length
            activeInlineDisplayedString = nil
            lastUserQuery = accepted
            textView.setSelectedRange(NSRange(location: end, length: 0))
            if parent.text != accepted {
                parent.text = accepted
            }
            parent.onUserInput(accepted)
        }
    }
}

/// Borderless non-activating child panel that floats directly below the Omnibox / Search bar.
final class OmniboxSuggestionPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// NSHostingView subclass that accepts first-mouse clicks so selecting a suggestion row
/// works immediately on the first click without stealing focus from the Omnibox text field.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

/// Transparent AppKit anchor view attached to the Omnibox / Search bar background.
/// Tracks layout and window attachment changes so the child `NSPanel` stays glued directly below the bar.
public final class OmniboxAnchorNSView: NSView {
    var onLayoutOrWindowChange: (() -> Void)?
    var onWillDetachFromWindow: (() -> Void)?

    public override func layout() {
        super.layout()
        onLayoutOrWindowChange?()
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onLayoutOrWindowChange?()
    }

    public override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            onWillDetachFromWindow?()
        }
        super.viewWillMove(toWindow: newWindow)
    }
}

/// Manages a borderless non-activating child `NSPanel` anchored directly below the Omnibox `NSView`.
public final class OmniboxSuggestionPanelController {
    public static let verticalGap: CGFloat = 4

    private var panel: OmniboxSuggestionPanel?
    private var hostingView: FirstMouseHostingView<AnyView>?
    private weak var observedWindow: NSWindow?
    private weak var currentAnchorView: NSView?
    private var windowObservers: [NSObjectProtocol] = []
    private var localMouseMonitor: Any?
    private var onDismissCallback: (() -> Void)?

    public init() {}

    deinit {
        hide()
    }

    public var isPanelVisible: Bool {
        panel?.isVisible ?? false
    }

    public var currentPanelFrame: NSRect? {
        panel?.frame
    }

    /// Computes the screen frame for the dropdown panel so its top edge (`maxY`) sits `verticalGap` points
    /// directly below `anchorView`'s bottom edge (`minY`), matching `anchorView`'s left edge and width.
    public static func panelScreenFrame(
        for anchorView: NSView,
        in parentWindow: NSWindow,
        contentHeight: CGFloat,
        minWidth: CGFloat = 320,
        verticalGap: CGFloat = OmniboxSuggestionPanelController.verticalGap
    ) -> NSRect {
        let rectInWindow = anchorView.convert(anchorView.bounds, to: nil)
        let anchorScreenRect = parentWindow.convertToScreen(rectInWindow)
        let width = max(round(anchorScreenRect.width), minWidth)
        let height = max(ceil(contentHeight), 1)
        let x = round(anchorScreenRect.minX)
        let y = round(anchorScreenRect.minY - verticalGap - height)
        return NSRect(x: x, y: y, width: width, height: height)
    }

    public func update(
        anchorView: NSView,
        session: BrowserSession,
        suggestions: [OmniboxSuggestion],
        selectedIndex: Int,
        isPresented: Bool,
        onSelect: @escaping (OmniboxSuggestion) -> Void,
        onDismiss: @escaping () -> Void = {}
    ) {
        self.currentAnchorView = anchorView
        self.onDismissCallback = onDismiss

        guard isPresented,
              !suggestions.isEmpty,
              let parentWindow = anchorView.window,
              anchorView.bounds.width > 0 else {
            hide()
            return
        }

        let rectInWindow = anchorView.convert(anchorView.bounds, to: nil)
        let anchorScreenRect = parentWindow.convertToScreen(rectInWindow)
        let targetWidth = max(round(anchorScreenRect.width), 320)

        let dropdownRoot = AnyView(
            OmniboxSuggestionsDropdownView(
                session: session,
                suggestions: suggestions,
                selectedIndex: selectedIndex,
                onSelect: onSelect
            )
            .frame(width: targetWidth)
            .fixedSize(horizontal: false, vertical: true)
        )

        let panel: OmniboxSuggestionPanel
        let hostingView: FirstMouseHostingView<AnyView>
        if let existingPanel = self.panel, let existingHost = self.hostingView {
            panel = existingPanel
            hostingView = existingHost
            hostingView.rootView = dropdownRoot
        } else {
            let newHost = FirstMouseHostingView(rootView: dropdownRoot)
            newHost.wantsLayer = true
            newHost.layer?.backgroundColor = NSColor.clear.cgColor

            let newPanel = OmniboxSuggestionPanel(
                contentRect: NSRect(x: 0, y: 0, width: targetWidth, height: 80),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            newPanel.isOpaque = false
            newPanel.backgroundColor = .clear
            newPanel.hasShadow = true
            newPanel.level = .popUpMenu
            newPanel.acceptsMouseMovedEvents = true
            newPanel.isMovable = false
            newPanel.isReleasedWhenClosed = false
            newPanel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            newPanel.contentView = newHost

            self.panel = newPanel
            self.hostingView = newHost
            panel = newPanel
            hostingView = newHost
        }

        hostingView.frame = NSRect(x: 0, y: 0, width: targetWidth, height: 10)
        hostingView.layoutSubtreeIfNeeded()
        let fittingHeight = max(hostingView.fittingSize.height, 36)

        let panelFrame = Self.panelScreenFrame(
            for: anchorView,
            in: parentWindow,
            contentHeight: fittingHeight
        )
        panel.setFrame(panelFrame, display: true)
        panel.invalidateShadow()

        if panel.parent !== parentWindow {
            panel.parent?.removeChildWindow(panel)
            parentWindow.addChildWindow(panel, ordered: .above)
        }
        if !panel.isVisible {
            panel.orderFront(nil)
        }

        observeWindowIfNeeded(parentWindow)
        installLocalMouseMonitorIfNeeded()
    }

    public func repositionIfVisible() {
        guard let panel,
              panel.isVisible,
              let anchorView = currentAnchorView,
              let parentWindow = anchorView.window,
              anchorView.bounds.width > 0,
              let hostingView else {
            return
        }
        let rectInWindow = anchorView.convert(anchorView.bounds, to: nil)
        let anchorScreenRect = parentWindow.convertToScreen(rectInWindow)
        let targetWidth = max(round(anchorScreenRect.width), 320)
        hostingView.frame = NSRect(x: 0, y: 0, width: targetWidth, height: hostingView.frame.height)
        hostingView.layoutSubtreeIfNeeded()
        let fittingHeight = max(hostingView.fittingSize.height, 36)

        let panelFrame = Self.panelScreenFrame(
            for: anchorView,
            in: parentWindow,
            contentHeight: fittingHeight
        )
        if panel.frame != panelFrame {
            panel.setFrame(panelFrame, display: true)
            panel.invalidateShadow()
        }
    }

    public func hide() {
        removeWindowObservers()
        removeLocalMouseMonitor()
        if let panel {
            panel.parent?.removeChildWindow(panel)
            if panel.isVisible {
                panel.orderOut(nil)
            }
        }
    }

    private func observeWindowIfNeeded(_ window: NSWindow) {
        guard observedWindow !== window else { return }
        removeWindowObservers()
        observedWindow = window

        let center = NotificationCenter.default
        let resizeObs = center.addObserver(
            forName: NSWindow.didResizeNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.repositionIfVisible()
        }
        let moveObs = center.addObserver(
            forName: NSWindow.didMoveNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.repositionIfVisible()
        }
        let resignObs = center.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.onDismissCallback?()
            self?.hide()
        }
        let closeObs = center.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.hide()
        }
        windowObservers = [resizeObs, moveObs, resignObs, closeObs]
    }

    private func removeWindowObservers() {
        for observer in windowObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        windowObservers.removeAll()
        observedWindow = nil
    }

    private func installLocalMouseMonitorIfNeeded() {
        guard localMouseMonitor == nil else { return }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, let panel = self.panel, panel.isVisible else {
                return event
            }
            if event.window === panel {
                return event
            }
            if let anchorView = self.currentAnchorView,
               event.window === anchorView.window {
                let pointInAnchor = anchorView.convert(event.locationInWindow, from: nil)
                if anchorView.bounds.contains(pointInAnchor) {
                    return event
                }
            }
            self.onDismissCallback?()
            self.hide()
            return event
        }
    }

    private func removeLocalMouseMonitor() {
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
    }
}

/// SwiftUI background anchor that attaches an `OmniboxSuggestionPanelController` directly beneath
/// the Omnibox or Start Page search bar.
public struct OmniboxDropdownAnchorView: NSViewRepresentable {
    @ObservedObject public var session: BrowserSession
    public let suggestions: [OmniboxSuggestion]
    public let selectedIndex: Int
    public let isPresented: Bool
    public let onSelect: (OmniboxSuggestion) -> Void
    public var onDismiss: () -> Void = {}

    public init(
        session: BrowserSession,
        suggestions: [OmniboxSuggestion],
        selectedIndex: Int,
        isPresented: Bool,
        onSelect: @escaping (OmniboxSuggestion) -> Void,
        onDismiss: @escaping () -> Void = {}
    ) {
        self.session = session
        self.suggestions = suggestions
        self.selectedIndex = selectedIndex
        self.isPresented = isPresented
        self.onSelect = onSelect
        self.onDismiss = onDismiss
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    public func makeNSView(context: Context) -> OmniboxAnchorNSView {
        let view = OmniboxAnchorNSView()
        view.onLayoutOrWindowChange = { [weak view, weak coordinator = context.coordinator] in
            guard let view, let coordinator else { return }
            coordinator.syncPanel(with: view)
        }
        view.onWillDetachFromWindow = { [weak coordinator = context.coordinator] in
            coordinator?.panelController.hide()
        }
        return view
    }

    public func updateNSView(_ nsView: OmniboxAnchorNSView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.syncPanel(with: nsView)
    }

    public static func dismantleNSView(_ nsView: OmniboxAnchorNSView, coordinator: Coordinator) {
        coordinator.panelController.hide()
    }

    public final class Coordinator {
        var parent: OmniboxDropdownAnchorView
        let panelController = OmniboxSuggestionPanelController()

        init(parent: OmniboxDropdownAnchorView) {
            self.parent = parent
        }

        func syncPanel(with anchorView: NSView) {
            panelController.update(
                anchorView: anchorView,
                session: parent.session,
                suggestions: parent.suggestions,
                selectedIndex: parent.selectedIndex,
                isPresented: parent.isPresented,
                onSelect: parent.onSelect,
                onDismiss: parent.onDismiss
            )
        }
    }
}

/// Dropdown card displaying ranked Omnibox suggestions (Hosts first, then Full Links, then Search).
public struct OmniboxSuggestionsDropdownView: View {
    @ObservedObject public var session: BrowserSession
    public let suggestions: [OmniboxSuggestion]
    public let selectedIndex: Int
    public let onSelect: (OmniboxSuggestion) -> Void

    @State private var hoveredID: String?

    public init(
        session: BrowserSession,
        suggestions: [OmniboxSuggestion],
        selectedIndex: Int,
        onSelect: @escaping (OmniboxSuggestion) -> Void
    ) {
        self.session = session
        self.suggestions = suggestions
        self.selectedIndex = selectedIndex
        self.onSelect = onSelect
    }

    private var hostSuggestions: [(index: Int, item: OmniboxSuggestion)] {
        suggestions.enumerated().compactMap { idx, item in
            item.kind == .host ? (idx, item) : nil
        }
    }

    private var fullLinkSuggestions: [(index: Int, item: OmniboxSuggestion)] {
        suggestions.enumerated().compactMap { idx, item in
            (item.kind == .history || item.kind == .bookmark) ? (idx, item) : nil
        }
    }

    private var searchSuggestions: [(index: Int, item: OmniboxSuggestion)] {
        suggestions.enumerated().compactMap { idx, item in
            item.kind == .search ? (idx, item) : nil
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // 1. Priority 1: Host suggestions from History & Bookmarks
            if !hostSuggestions.isEmpty {
                sectionHeader(title: "常访与收藏域名 (Host)", icon: "globe")

                ForEach(hostSuggestions, id: \.item.id) { pair in
                    suggestionRow(for: pair.item, index: pair.index)
                }
            }

            // 2. Priority 2: Full Link suggestions from History & Bookmarks
            if !fullLinkSuggestions.isEmpty {
                if !hostSuggestions.isEmpty {
                    Divider()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                }

                sectionHeader(title: "历史记录与收藏夹完整链接", icon: "link")

                ForEach(fullLinkSuggestions, id: \.item.id) { pair in
                    suggestionRow(for: pair.item, index: pair.index)
                }
            }

            // 3. Priority 3: Search engine fallback
            if !searchSuggestions.isEmpty {
                if !hostSuggestions.isEmpty || !fullLinkSuggestions.isEmpty {
                    Divider()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                }

                ForEach(searchSuggestions, id: \.item.id) { pair in
                    suggestionRow(for: pair.item, index: pair.index)
                }
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.secondary.opacity(0.24), lineWidth: 1)
        )
    }

    private func sectionHeader(title: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundColor(.secondary)
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.top, 4)
        .padding(.bottom, 2)
    }

    @ViewBuilder
    private func suggestionRow(for suggestion: OmniboxSuggestion, index: Int) -> some View {
        let isHighlighted = (selectedIndex == index) || (hoveredID == suggestion.id)

        Button(action: {
            onSelect(suggestion)
        }) {
            HStack(spacing: 10) {
                leadingIcon(for: suggestion, isHighlighted: isHighlighted)

                centerText(for: suggestion)

                Spacer(minLength: 8)

                trailingBadge(for: suggestion, isHighlighted: isHighlighted)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isHighlighted ? Color.accentColor.opacity(0.14) : Color(nsColor: .clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                hoveredID = suggestion.id
            } else if hoveredID == suggestion.id {
                hoveredID = nil
            }
        }
    }

    @ViewBuilder
    private func leadingIcon(for suggestion: OmniboxSuggestion, isHighlighted: Bool) -> some View {
        if suggestion.kind == .search {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.accentColor.opacity(0.12))
                .frame(width: 22, height: 22)
                .overlay(
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.accentColor)
                )
        } else if let iconName = suggestion.iconName,
                  !iconName.isEmpty,
                  let bundleImage = FavoritesManager.shared.iconImage(named: iconName) {
            Image(nsImage: bundleImage)
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        } else if let siteIcon = session.siteIcon(for: suggestion.url) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
                .frame(width: 22, height: 22)
                .overlay(
                    SiteIconThumbnail(image: siteIcon, size: 15)
                )
        } else {
            switch suggestion.kind {
            case .host:
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.accentColor.opacity(0.14))
                    .frame(width: 22, height: 22)
                    .overlay(
                        Image(systemName: "globe")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundColor(.accentColor)
                    )
            case .bookmark:
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.yellow.opacity(0.18))
                    .frame(width: 22, height: 22)
                    .overlay(
                        Image(systemName: "star.fill")
                            .font(.system(size: 10.5))
                            .foregroundColor(.orange)
                    )
            case .history:
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(width: 22, height: 22)
                    .overlay(
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary)
                    )
            case .search:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private func centerText(for suggestion: OmniboxSuggestion) -> some View {
        switch suggestion.kind {
        case .host:
            HStack(spacing: 6) {
                Text(suggestion.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                if !suggestion.subtitle.isEmpty {
                    Text("— \(suggestion.subtitle)")
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

        case .history, .bookmark:
            VStack(alignment: .leading, spacing: 1.5) {
                Text(suggestion.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text(suggestion.subtitle)
                    .font(.system(size: 10.5))
                    .foregroundColor(.accentColor.opacity(0.9))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

        case .search:
            HStack(spacing: 6) {
                Text(suggestion.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text("— \(suggestion.subtitle)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private func trailingBadge(for suggestion: OmniboxSuggestion, isHighlighted: Bool) -> some View {
        switch suggestion.kind {
        case .host:
            HStack(spacing: 3) {
                Text("域名 · \(suggestion.source.badgeLabel)")
                    .font(.system(size: 9.5, weight: .medium))
            }
            .foregroundColor(isHighlighted ? .accentColor : .secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(isHighlighted ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.1))
            )

        case .bookmark, .history:
            HStack(spacing: 3) {
                Image(systemName: suggestion.source == .history ? "clock" : "star.fill")
                    .font(.system(size: 8.5))
                    .foregroundColor(suggestion.source == .history ? .secondary : .orange)
                Text(suggestion.source.badgeLabel)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(Color.secondary.opacity(0.1))
            )

        case .search:
            Text("搜索 ↵")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(Color.secondary.opacity(0.1))
                )
        }
    }
}
