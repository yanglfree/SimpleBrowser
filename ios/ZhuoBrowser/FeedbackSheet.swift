import SwiftUI

struct FeedbackSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var message = ""
    @State private var contact = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $message)
                        .frame(minHeight: 140)
                        .disabled(isSubmitting)
                        .accessibilityIdentifier("feedback-message")
                    Text("\(message.count)/\(FeedbackPolicy.maximumMessageLength)")
                        .font(.caption)
                        .foregroundStyle(message.count > FeedbackPolicy.maximumMessageLength ? .red : DesignTokens.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                } header: {
                    Text("反馈内容")
                } footer: {
                    Text("请勿填写密码、验证码或网页正文。")
                }

                Section("联系方式（可选）") {
                    TextField("邮箱或其他联系方式", text: $contact)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .disabled(isSubmitting)
                        .accessibilityIdentifier("feedback-contact")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("feedback-error")
                    }
                }
            }
            .navigationTitle("意见反馈")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .disabled(isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await submit() }
                    } label: {
                        if isSubmitting {
                            ProgressView()
                        } else {
                            Text("提交")
                        }
                    }
                    .disabled(isSubmitting)
                    .accessibilityIdentifier("feedback-submit")
                }
            }
        }
    }

    @MainActor
    private func submit() async {
        if let validation = FeedbackPolicy.validate(message) {
            errorMessage = FeedbackServiceError.invalidMessage(validation).localizedDescription
            return
        }
        errorMessage = nil
        isSubmitting = true
        defer { isSubmitting = false }

        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0
        do {
            _ = try await FeedbackService().submit(
                message: message,
                contact: contact,
                appVersion: shortVersion,
                build: build
            )
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "提交失败，请稍后重试。"
        }
    }
}
