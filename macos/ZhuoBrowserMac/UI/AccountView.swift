import SwiftUI

/// View for user login, registration, and cloud sync status management.
public struct AccountView: View {
    @ObservedObject var session: BrowserSession
    @Binding var isPresented: Bool
    @ObservedObject private var accountManager = AccountManager.shared

    @State private var isRegisterMode: Bool = false
    @State private var emailInput: String = ""
    @State private var passwordInput: String = ""
    @State private var displayNameInput: String = ""
    @State private var isSubmitting: Bool = false

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.accentColor)
                    Text(accountManager.isLoggedIn ? "账号中心" : (isRegisterMode ? "注册账号" : "登录账号"))
                        .font(.system(size: 14, weight: .bold))
                }

                Spacer()

                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 15))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            if accountManager.isLoggedIn {
                loggedInContent
            } else {
                authFormContent
            }
        }
        .frame(width: 360)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // Logged In State View
    private var loggedInContent: some View {
        VStack(spacing: 20) {
            // Avatar & Profile
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: 64, height: 64)

                    Text(accountManager.currentUser?.displayName.prefix(1).uppercased() ?? "U")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.accentColor)
                }

                Text(accountManager.currentUser?.displayName ?? "用户")
                    .font(.system(size: 16, weight: .semibold))

                Text(accountManager.currentUser?.email ?? "")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .padding(.top, 12)

            // Cloud Sync Status Card
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "icloud.fill")
                        .foregroundColor(.blue)
                        .font(.system(size: 14))

                    Text("云端同步 (Cloudflare D1)")
                        .font(.system(size: 12, weight: .semibold))

                    Spacer()

                    if accountManager.isSyncing {
                        ProgressView()
                            .controlSize(.mini)
                    }
                }

                HStack {
                    Text("上次同步时间：")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    if let syncTime = accountManager.lastSyncTime {
                        Text(syncTime, style: .time)
                            .font(.system(size: 11, weight: .medium))
                    } else {
                        Text("尚未同步")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }

                if let syncError = accountManager.syncErrorMessage {
                    Text(syncError)
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                        .lineLimit(2)
                }

                Button(action: {
                    Task {
                        await accountManager.syncWithCloud(session: session)
                    }
                }) {
                    HStack {
                        Spacer()
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 11))
                        Text(accountManager.isSyncing ? "正在同步..." : "立即同步书签与偏好")
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                    }
                    .padding(.vertical, 7)
                    .background(Color.accentColor.opacity(0.15))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(accountManager.isSyncing)
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
            )

            Spacer()

            // Logout Button
            Button(action: {
                accountManager.logout()
            }) {
                Text("退出登录")
                    .font(.system(size: 12))
                    .foregroundColor(.red)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 16)
        }
        .padding(.horizontal, 20)
    }

    // Login & Register Form
    private var authFormContent: some View {
        VStack(spacing: 16) {
            VStack(spacing: 12) {
                if isRegisterMode {
                    TextField("昵称", text: $displayNameInput)
                        .textFieldStyle(.roundedBorder)
                }

                TextField("邮箱地址", text: $emailInput)
                    .textFieldStyle(.roundedBorder)

                SecureField("密码 (至少 6 位)", text: $passwordInput)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.top, 10)

            if let errorMsg = accountManager.errorMessage {
                Text(errorMsg)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
                    .lineLimit(2)
            }

            // Submit Button
            Button(action: {
                submitAuth()
            }) {
                HStack {
                    Spacer()
                    if isSubmitting {
                        ProgressView()
                            .controlSize(.mini)
                            .padding(.trailing, 4)
                    }
                    Text(isRegisterMode ? "立即注册" : "登录")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                }
                .padding(.vertical, 8)
                .background(Color.accentColor)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .disabled(isSubmitting || emailInput.isEmpty || passwordInput.isEmpty)

            // Switch Mode Button
            Button(action: {
                isRegisterMode.toggle()
                accountManager.errorMessage = nil
            }) {
                Text(isRegisterMode ? "已有账号？返回登录" : "没有账号？免费注册")
                    .font(.system(size: 11))
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }

    private func submitAuth() {
        isSubmitting = true
        Task {
            if isRegisterMode {
                let success = await accountManager.register(
                    email: emailInput,
                    password: passwordInput,
                    displayName: displayNameInput
                )
                isSubmitting = false
                if success {
                    await accountManager.syncWithCloud(session: session)
                }
            } else {
                let success = await accountManager.login(
                    email: emailInput,
                    password: passwordInput
                )
                isSubmitting = false
                if success {
                    await accountManager.syncWithCloud(session: session)
                }
            }
        }
    }
}
