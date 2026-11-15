import SwiftUI

struct JsDialogSheet: View {
    let dialog: PendingJsDialog
    let onFinish: () -> Void

    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        ZStack {
            DesignTokens.scrim
                .ignoresSafeArea()
                .onTapGesture {
                    dialog.cancel()
                    onFinish()
                }

            VStack(alignment: .leading, spacing: 14) {
                Text("\(dialog.titleHost) 显示")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DesignTokens.textPrimary)
                    .lineLimit(2)

                if !dialog.message.isEmpty {
                    ScrollView {
                        Text(dialog.message)
                            .font(.system(size: 14))
                            .foregroundStyle(DesignTokens.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 180)
                }

                if dialog.kind == .prompt {
                    TextField("请输入内容", text: $inputText)
                        .textFieldStyle(.plain)
                        .focused($isInputFocused)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            DesignTokens.surfaceSubtle,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                        .foregroundStyle(DesignTokens.textPrimary)
                        .accessibilityIdentifier("js-dialog-input")
                }

                HStack(spacing: 10) {
                    if dialog.kind != .alert {
                        Button {
                            dialog.cancel()
                            onFinish()
                        } label: {
                            Text("取消")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(DesignTokens.textPrimary)
                                .frame(maxWidth: .infinity, minHeight: 42)
                                .background(
                                    DesignTokens.surfaceSubtle,
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                )
                        }
                        .accessibilityIdentifier("js-dialog-cancel")
                    }

                    Button {
                        submit()
                    } label: {
                        Text("确定")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(DesignTokens.accentForeground)
                            .frame(maxWidth: .infinity, minHeight: 42)
                            .background(
                                DesignTokens.accentFill,
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                    }
                    .accessibilityIdentifier("js-dialog-confirm")
                }
            }
            .padding(20)
            .frame(maxWidth: 360)
            .background(
                DesignTokens.surfacePanel,
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(DesignTokens.border, lineWidth: 1)
            )
            .padding(.horizontal, 24)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("js-dialog-sheet")
        .onAppear {
            inputText = dialog.defaultText
            if dialog.kind == .prompt {
                isInputFocused = true
            }
        }
    }

    private func submit() {
        switch dialog.kind {
        case .alert:
            dialog.completeAlert()
        case .confirm:
            dialog.completeConfirm(true)
        case .prompt:
            dialog.completePrompt(inputText)
        }
        onFinish()
    }
}
