import AppKit
import SwiftUI

/// AppKit-backed NSTextField subclass that selects all text when initially clicked from an unfocused state,
/// matching native macOS Safari / Chrome address bar behavior.
public final class OmniboxNSTextField: NSTextField {
    var shouldSelectAllOnMouseUp: Bool = false

    public override func mouseDown(with event: NSEvent) {
        let wasAlreadyEditing = (window?.firstResponder != nil) && (window?.firstResponder === currentEditor())
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

        public func controlTextDidBeginEditing(_ obj: Notification) {
            if !parent.isFocused {
                parent.isFocused = true
            }
        }

        public func controlTextDidEndEditing(_ obj: Notification) {
            activeInlineDisplayedString = nil
            // Defer focus state teardown by one runloop tick so clicks on suggestion rows
            // inside the dropdown overlay register cleanly before the overlay disappears.
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

/// AppKit subview host that ensures SwiftUI floating overlays composite and hit-test above `WKWebView`.
public struct FloatingOverlayHostView<Content: View>: NSViewRepresentable {
    public let rootView: Content

    public init(@ViewBuilder content: () -> Content) {
        self.rootView = content()
    }

    public func makeNSView(context: Context) -> NSHostingView<Content> {
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        return hostingView
    }

    public func updateNSView(_ hostingView: NSHostingView<Content>, context: Context) {
        hostingView.rootView = rootView
    }

    public func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSHostingView<Content>, context: Context) -> CGSize {
        nsView.rootView = rootView
        let fitting = nsView.fittingSize
        return CGSize(
            width: proposal.width ?? fitting.width,
            height: fitting.height
        )
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
        .shadow(color: Color.black.opacity(0.2), radius: 14, x: 0, y: 6)
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
