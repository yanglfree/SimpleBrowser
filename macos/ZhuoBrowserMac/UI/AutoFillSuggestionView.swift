import SwiftUI
import AppKit

/// Renders the iconic macOS Keychain 3-key badge (black rounded background with multi-colored keys).
public struct KeychainIconView: View {
    public var size: CGFloat = 28

    public init(size: CGFloat = 28) {
        self.size = size
    }

    public var body: some View {
        ZStack {
            // Dark rounded container
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(Color(white: 0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                )

            // Three colored keys (Yellow, Cyan/Blue, Green)
            HStack(spacing: size * 0.05) {
                // Key 1: Gold / Yellow
                keyShape(color: Color(red: 0.98, green: 0.78, blue: 0.22))
                // Key 2: Cyan / Blue
                keyShape(color: Color(red: 0.35, green: 0.75, blue: 0.98))
                // Key 3: Mint / Green
                keyShape(color: Color(red: 0.38, green: 0.85, blue: 0.45))
            }
            .scaleEffect(0.72)
        }
        .frame(width: size, height: size)
    }

    private func keyShape(color: Color) -> some View {
        VStack(spacing: 0) {
            // Key head (circle with hole)
            Circle()
                .stroke(color, lineWidth: size * 0.08)
                .frame(width: size * 0.28, height: size * 0.28)
            // Key stem
            Rectangle()
                .fill(color)
                .frame(width: size * 0.07, height: size * 0.22)
            // Key teeth
            HStack(spacing: 0) {
                Spacer().frame(width: size * 0.03)
                Rectangle()
                    .fill(color)
                    .frame(width: size * 0.07, height: size * 0.06)
            }
        }
    }
}

/// SwiftUI View presenting the exact Safari-style AutoFill & Passkey Quick-Login suggestion popup.
public struct AutoFillSuggestionView: View {
    public let credentials: [SavedCredential]
    public let currentHost: String
    public let rootDomain: String
    public let isPasswordContext: Bool
    public let onSelectCredential: (SavedCredential) -> Void
    public let onSelectOtherPasswords: () -> Void
    public let onSelectNearbyPasskeys: () -> Void

    @State private var hoveredIndex: Int = 0

    public init(
        credentials: [SavedCredential],
        currentHost: String,
        rootDomain: String? = nil,
        isPasswordContext: Bool = false,
        onSelectCredential: @escaping (SavedCredential) -> Void,
        onSelectOtherPasswords: @escaping () -> Void,
        onSelectNearbyPasskeys: @escaping () -> Void
    ) {
        self.credentials = credentials
        self.currentHost = currentHost
        self.rootDomain = rootDomain ?? SavedCredential.extractRootDomain(from: currentHost)
        self.isPasswordContext = isPasswordContext
        self.onSelectCredential = onSelectCredential
        self.onSelectOtherPasswords = onSelectOtherPasswords
        self.onSelectNearbyPasskeys = onSelectNearbyPasskeys
    }

    private var hasPasskeys: Bool {
        credentials.contains { $0.isPasskey }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 1. Matched Credentials List
            ForEach(Array(credentials.enumerated()), id: \.element.id) { index, item in
                let isSelected = hoveredIndex == index
                Button {
                    onSelectCredential(item)
                } label: {
                    credentialRow(item: item, isSelected: isSelected)
                }
                .buttonStyle(.plain)
                .onHover { inside in
                    if inside { hoveredIndex = index }
                }

                if index < credentials.count - 1 {
                    Divider().opacity(0.35)
                }
            }

            // Divider separating credentials from secondary actions
            if !credentials.isEmpty {
                Divider()
                    .padding(.vertical, 2)
                    .opacity(0.5)
            }

            // 2. Action: Other Passwords / Accounts on this domain
            let otherText = credentials.isEmpty
                ? "“\(rootDomain)” 的密码..."
                : (hasPasskeys ? "\(rootDomain) 的其他账户..." : "“\(rootDomain)” 的其他密码...")

            Button {
                onSelectOtherPasswords()
            } label: {
                actionRow(title: otherText, isSelected: hoveredIndex == credentials.count)
            }
            .buttonStyle(.plain)
            .onHover { inside in
                if inside { hoveredIndex = credentials.count }
            }

            // 3. Action: Nearby Passkeys (if passkey supported or present)
            if hasPasskeys || !isPasswordContext {
                Button {
                    onSelectNearbyPasskeys()
                } label: {
                    actionRow(title: "附近设备的通行密钥...", isSelected: hoveredIndex == credentials.count + 1)
                }
                .buttonStyle(.plain)
                .onHover { inside in
                    if inside { hoveredIndex = credentials.count + 1 }
                }
            }
        }
        .padding(5)
        .frame(minWidth: 260, maxWidth: 330)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color(NSColor.windowBackgroundColor).opacity(0.96))
                .shadow(color: Color.black.opacity(0.18), radius: 10, x: 0, y: 5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(Color(NSColor.separatorColor).opacity(0.8), lineWidth: 0.5)
        )
    }

    private func credentialRow(item: SavedCredential, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            KeychainIconView(size: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.username)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isSelected ? .white : .primary)
                    .lineLimit(1)

                Text(item.isPasskey ? "此网站的通行密钥" : (item.domain.isEmpty ? currentHost : item.domain))
                    .font(.system(size: 11))
                    .foregroundColor(isSelected ? Color.white.opacity(0.88) : .secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isSelected ? Color.accentColor : Color.clear)
        )
        .contentShape(Rectangle())
    }

    private func actionRow(title: String, isSelected: Bool) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12.5))
                .foregroundColor(isSelected ? Color.accentColor : .primary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        )
        .contentShape(Rectangle())
    }
}
