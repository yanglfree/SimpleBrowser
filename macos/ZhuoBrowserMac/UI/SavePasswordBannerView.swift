import SwiftUI
import AppKit

/// Safari-style slide-down banner asking whether to save or update credentials for the current website.
public struct SavePasswordBannerView: View {
    public let hostname: String
    public let username: String
    public let onSave: () -> Void
    public let onDismiss: () -> Void

    public init(
        hostname: String,
        username: String,
        onSave: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.hostname = hostname
        self.username = username
        self.onSave = onSave
        self.onDismiss = onDismiss
    }

    public var body: some View {
        HStack(spacing: 12) {
            KeychainIconView(size: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text("您想要存储“\(hostname)”的密码吗？")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(.primary)

                if !username.isEmpty {
                    Text("账户: \(username)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            Spacer(minLength: 16)

            Button("稍后") {
                onDismiss()
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundColor(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(NSColor.controlBackgroundColor))
            )

            Button("存储密码") {
                onSave()
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor)
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(Color(NSColor.windowBackgroundColor))
                .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
        )
        .frame(maxWidth: 480)
    }
}
