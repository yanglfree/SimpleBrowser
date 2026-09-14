import SwiftUI

struct PageLoadErrorView: View {
    let kind: PageLoadErrorKind
    let onRetry: () -> Void
    let onShowSecurity: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isBreathing = false

    var body: some View {
        if let presentation = PageLoadErrorPresentation(kind: kind) {
            VStack(spacing: 14) {
                if let symbolName = presentation.symbolName {
                    Image(systemName: symbolName)
                        .font(.system(size: 48, weight: .light))
                        .foregroundStyle(DesignTokens.textSecondary)
                        .frame(width: 96, height: 96)
                        .background(DesignTokens.surfaceSubtle, in: Circle())
                        .scaleEffect(isBreathing && !reduceMotion ? 1.06 : 1)
                        .accessibilityHidden(true)
                }

                Text(presentation.title)
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(DesignTokens.textPrimary)
                    .multilineTextAlignment(.center)

                Text(presentation.message)
                    .font(.system(size: 14))
                    .foregroundStyle(DesignTokens.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 32)

                Button("重试", action: onRetry)
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    .tint(DesignTokens.accent)
                    .frame(width: 128)
                    .padding(.top, 6)
                    .accessibilityIdentifier("page-error-retry")

                if presentation.showsSecurityDetails {
                    Button("查看安全信息", action: onShowSecurity)
                        .font(.system(size: 14))
                        .foregroundStyle(DesignTokens.textSecondary)
                        .accessibilityIdentifier("page-error-security")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DesignTokens.pageBackground)
            .contentShape(Rectangle())
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("page-load-error-\(kind.rawValue)")
            .onAppear {
                guard presentation.symbolName != nil, !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    isBreathing = true
                }
            }
        }
    }
}
