import SwiftUI

struct PermissionPrompt: Identifiable {
    let id = UUID()
    let origin: String
    let kinds: [SitePermissionKind]
    let persist: Bool
}

struct PermissionSheet: View {
    let prompt: PermissionPrompt
    let onAllow: () -> Void
    let onDeny: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("网站权限")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(DesignTokens.textPrimary)
            Text(prompt.origin)
                .font(.system(size: 14))
                .foregroundStyle(DesignTokens.accent)
                .lineLimit(1)
                .padding(.top, 8)
            Text("该网站想使用下列功能。允许后才会向系统申请相应权限。")
                .font(.system(size: 14))
                .foregroundStyle(DesignTokens.textSecondary)
                .padding(.top, 14)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(prompt.kinds, id: \.self) { kind in
                    Text(kind.label)
                        .font(.system(size: 15))
                        .foregroundStyle(DesignTokens.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(DesignTokens.border).frame(height: 1)
                        }
                }
            }
            .padding(.top, 12)
            HStack(spacing: 12) {
                Button("拒绝", action: onDeny)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(DesignTokens.surfaceSubtle, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityIdentifier("permission-deny")
                Button("允许", action: onAllow)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundStyle(.white)
                    .background(DesignTokens.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityIdentifier("permission-allow")
            }
            .font(.system(size: 15))
            .foregroundStyle(DesignTokens.textPrimary)
            .padding(.top, 20)
        }
        .padding(20)
        .background(DesignTokens.surfacePanel)
        .accessibilityIdentifier("permission-sheet")
    }
}
