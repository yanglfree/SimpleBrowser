import SwiftUI
import UIKit

struct OmniboxTextField: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    @Binding var selection: OmniboxSelection
    let placeholder: String
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.delegate = context.coordinator
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.keyboardType = .URL
        field.returnKeyType = .go
        field.clearButtonMode = .whileEditing
        field.borderStyle = .none
        field.font = .systemFont(ofSize: 15)
        field.textColor = .label
        field.tintColor = UIColor(DesignTokens.accent)
        field.accessibilityIdentifier = "omni-field"
        field.addTarget(context.coordinator, action: #selector(Coordinator.textChanged), for: .editingChanged)
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        if field.text != text {
            field.text = text
        }
        field.placeholder = placeholder
        if isFocused, !field.isFirstResponder {
            field.becomeFirstResponder()
        } else if !isFocused, field.isFirstResponder {
            field.resignFirstResponder()
        }
        context.coordinator.apply(selection, to: field)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: OmniboxTextField
        private var selectsAllOnFocus = true

        init(_ parent: OmniboxTextField) {
            self.parent = parent
        }

        @objc func textChanged(_ field: UITextField) {
            parent.text = field.text ?? ""
            captureSelection(from: field)
        }

        func textFieldDidBeginEditing(_ field: UITextField) {
            parent.isFocused = true
            guard selectsAllOnFocus else {
                captureSelection(from: field)
                return
            }
            selectsAllOnFocus = false
            DispatchQueue.main.async { [weak self, weak field] in
                guard let self, let field else { return }
                field.selectAll(nil)
                self.captureSelection(from: field)
            }
        }

        func textFieldDidEndEditing(_ field: UITextField) {
            parent.isFocused = false
            selectsAllOnFocus = true
            captureSelection(from: field)
        }

        func textFieldDidChangeSelection(_ field: UITextField) {
            captureSelection(from: field)
        }

        func textFieldShouldReturn(_ field: UITextField) -> Bool {
            parent.onSubmit()
            return true
        }

        func apply(_ selection: OmniboxSelection, to field: UITextField) {
            guard field.isFirstResponder,
                  let start = field.position(from: field.beginningOfDocument, offset: selection.start),
                  let end = field.position(from: field.beginningOfDocument, offset: selection.end),
                  field.selectedTextRange?.start != start || field.selectedTextRange?.end != end else {
                return
            }
            field.selectedTextRange = field.textRange(from: start, to: end)
        }

        private func captureSelection(from field: UITextField) {
            guard let range = field.selectedTextRange else { return }
            let next = OmniboxSelection(
                start: field.offset(from: field.beginningOfDocument, to: range.start),
                end: field.offset(from: field.beginningOfDocument, to: range.end)
            )
            if parent.selection != next {
                parent.selection = next
            }
        }
    }
}

struct OmniboxShortcutBar: View {
    let shortcuts: [OmniboxShortcut]
    let onSelect: (OmniboxShortcut) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(shortcuts) { shortcut in
                Button(shortcut.label) {
                    onSelect(shortcut)
                }
                .font(.system(size: 13))
                .foregroundStyle(DesignTokens.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(DesignTokens.surfacePanel, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(DesignTokens.border, lineWidth: 1))
                .accessibilityIdentifier(shortcut.accessibilityIdentifier)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(DesignTokens.pageBackground)
    }
}
