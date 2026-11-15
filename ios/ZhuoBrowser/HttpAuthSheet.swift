import SwiftUI

struct HttpAuthSheet: View {
    let challenge: PendingHttpAuth
    let onFinish: () -> Void

    @State private var username = ""
    @State private var password = ""
    @FocusState private var isUserFocused: Bool

    var body: some View {
        ZStack {
            DesignTokens.scrim
                .ignoresSafeArea()
                .onTapGesture {
                    challenge.cancel()
                    onFinish()
                }

            VStack(alignment: .leading, spacing: 14) {
                Text("需要身份验证")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(DesignTokens.textPrimary)

                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(DesignTokens.textSecondary)
                    .lineLimit(2)

                if challenge.isRetry {
                    Text("用户名或密码错误，请重新输入")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DesignTokens.danger)
                }

                TextField("用户名", text: $username)
                    .textFieldStyle(.plain)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($isUserFocused)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        DesignTokens.surfaceSubtle,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .foregroundStyle(DesignTokens.textPrimary)
                    .accessibilityIdentifier("http-auth-username")

                SecureField("密码", text: $password)
                    .textFieldStyle(.plain)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        DesignTokens.surfaceSubtle,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .foregroundStyle(DesignTokens.textPrimary)
                    .accessibilityIdentifier("http-auth-password")

                HStack(spacing: 10) {
                    Button {
                        challenge.cancel()
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
                    .accessibilityIdentifier("http-auth-cancel")

                    Button {
                        challenge.submit(username: username, password: password)
                        onFinish()
                    } label: {
                        Text("登录")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(DesignTokens.accentForeground)
                            .frame(maxWidth: .infinity, minHeight: 42)
                            .background(
                                DesignTokens.accentFill,
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                    }
                    .accessibilityIdentifier("http-auth-submit")
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
        .accessibilityIdentifier("http-auth-sheet")
        .onAppear {
            isUserFocused = true
        }
    }

    private var subtitle: String {
        let host = challenge.host.isEmpty ? "当前网站" : challenge.host
        if challenge.realm.isEmpty {
            return "\(host) 请求您的凭据。"
        }
        return "\(host)（\(challenge.realm)）请求您的凭据。"
    }
}
