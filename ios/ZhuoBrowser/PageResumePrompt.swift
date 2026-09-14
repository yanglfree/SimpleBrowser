import SwiftUI

struct PageResumePrompt: View {
    let onContinue: () -> Void
    let onStartOver: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text("继续上次阅读位置？")
                .font(.system(size: 13.5))
                .foregroundStyle(DesignTokens.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button("继续", action: onContinue)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(DesignTokens.accent)
                .accessibilityIdentifier("resume-page-continue")
            Button(action: onStartOver) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DesignTokens.textSecondary)
                    .frame(width: 24, height: 24)
            }
            .accessibilityLabel("从头开始")
            .accessibilityIdentifier("resume-page-start-over")
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .frame(height: 44)
        .background(DesignTokens.surfacePanel, in: Capsule())
        .overlay {
            Capsule().stroke(DesignTokens.border, lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.08), radius: 8, y: 3)
        .accessibilityIdentifier("resume-page-prompt")
    }
}
