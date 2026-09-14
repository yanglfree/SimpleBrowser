import SwiftUI
import UIKit

struct AboutSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showsCopiedConfirmation = false

    let versionLabel: String

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 10) {
                        Image(systemName: "book.pages.fill")
                            .font(.system(size: 42, weight: .medium))
                            .foregroundStyle(DesignTokens.accent)
                            .accessibilityHidden(true)
                        Text("卓阅")
                            .font(.title2.bold())
                        Text(versionLabel)
                            .foregroundStyle(DesignTokens.textSecondary)
                        Text(AppInformation.tagline)
                            .font(.subheadline)
                            .foregroundStyle(DesignTokens.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }

                Section("法律与支持") {
                    Link("用户协议", destination: AppInformation.termsURL)
                    Link("隐私政策", destination: AppInformation.privacyURL)
                    Link("联系支持", destination: AppInformation.supportURL)
                }

                Section("备案信息") {
                    Button {
                        UIPasteboard.general.string = AppInformation.filingNumber
                        showsCopiedConfirmation = true
                    } label: {
                        LabeledContent("备案号", value: AppInformation.filingNumber)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("双击复制备案号")
                    .accessibilityIdentifier("about-copy-filing-number")
                }
            }
            .scrollContentBackground(.hidden)
            .background(DesignTokens.pageBackground)
            .navigationTitle("关于卓阅")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .alert("已复制备案号", isPresented: $showsCopiedConfirmation) {
            Button("好", role: .cancel) {}
        }
        .presentationDetents([.medium, .large])
        .accessibilityIdentifier("about-sheet")
    }
}
