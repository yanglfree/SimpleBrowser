import SwiftUI

private enum IosAuthMode: String, CaseIterable, Identifiable {
    case otp = "邮箱验证码"
    case password = "密码"
    var id: String { rawValue }
}

struct AccountSheet: View {
    @EnvironmentObject private var session: BrowserSession
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var account = AccountService.shared

    @State private var authMode: IosAuthMode = .otp
    @State private var isRegisterMode = false
    @State private var email = ""
    @State private var otpCode = ""
    @State private var otpSent = false
    @State private var otpCooldown = 0
    @State private var password = ""
    @State private var displayName = ""
    @State private var isSubmitting = false
    @State private var showsDeleteAlert = false

    var body: some View {
        NavigationStack {
            Group {
                if account.isLoggedIn {
                    loggedInBody
                } else {
                    loginBody
                }
            }
            .navigationTitle(account.isLoggedIn ? "账号中心" : "登录与多端同步")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .alert("确定永久注销并删除此账号？", isPresented: $showsDeleteAlert) {
                Button("永久删除", role: .destructive) {
                    Task {
                        let ok = await account.deleteAccount()
                        if ok { dismiss() }
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("此操作将永久删除云端账号、同步书签、离线文章同步副本和头像，且无法恢复。本机浏览数据不会被清空。")
            }
        }
    }

    private var loggedInBody: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(account.currentUser?.displayName ?? "卓阅用户")
                        .font(.headline)
                    Text(account.currentUser?.email ?? "")
                        .font(.subheadline)
                        .foregroundStyle(DesignTokens.textSecondary)
                    if session.pro.isPro || account.cloudProEntitlement?.active == true {
                        Label("卓阅 Pro 跨端权益已激活", systemImage: "crown.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("云端同步") {
                HStack {
                    Text("上次同步")
                    Spacer()
                    if let last = account.lastSyncTime {
                        Text(last, style: .time)
                            .foregroundStyle(DesignTokens.textSecondary)
                    } else {
                        Text("尚未同步")
                            .foregroundStyle(DesignTokens.textSecondary)
                    }
                }
                if let err = account.syncErrorMessage {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Button {
                    Task { await CloudSyncService.shared.sync(session: session) }
                } label: {
                    HStack {
                        Text(account.isSyncing ? "正在同步..." : "立即同步")
                        Spacer()
                        if account.isSyncing { ProgressView() }
                    }
                }
                .disabled(account.isSyncing)
            }

            if !account.remoteDeviceTabs.isEmpty {
                Section("其他设备打开的标签页") {
                    ForEach(account.remoteDeviceTabs) { device in
                        ForEach(device.tabs.prefix(5)) { tab in
                            Button {
                                _ = session.createTab(isPrivate: false)
                                session.openInActiveTab(tab.url)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(tab.title).lineLimit(1)
                                    Text("\(device.deviceName) · \(URLPolicy.displayHost(tab.url))")
                                        .font(.caption)
                                        .foregroundStyle(DesignTokens.textSecondary)
                                }
                            }
                        }
                    }
                }
            }

            if !account.linkedIdentities.isEmpty {
                Section("已关联登录方式") {
                    ForEach(account.linkedIdentities) { identity in
                        HStack {
                            Text(identity.displayLabel)
                            Spacer()
                            if let email = identity.email, !email.isEmpty {
                                Text(email)
                                    .font(.caption)
                                    .foregroundStyle(DesignTokens.textSecondary)
                            }
                        }
                    }
                }
            }

            Section {
                Button("退出登录") {
                    account.logout()
                }
                Button("永久注销并删除账号", role: .destructive) {
                    showsDeleteAlert = true
                }
            }
        }
    }

    private var loginBody: some View {
        Form {
            Section {
                Picker("登录方式", selection: $authMode) {
                    ForEach(IosAuthMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                TextField("邮箱地址", text: $email)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)

                if authMode == .otp {
                    HStack {
                        TextField("6 位验证码", text: $otpCode)
                            .keyboardType(.numberPad)
                        Button(otpCooldown > 0 ? "\(otpCooldown)s" : (otpSent ? "重发" : "获取验证码")) {
                            sendOtp()
                        }
                        .disabled(isSubmitting || otpCooldown > 0 || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                } else {
                    if isRegisterMode {
                        TextField("昵称", text: $displayName)
                    }
                    SecureField("密码 (至少 6 位)", text: $password)
                }

                if let err = account.errorMessage {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Button {
                    submitAuth()
                } label: {
                    HStack {
                        Spacer()
                        Text(authMode == .otp ? "验证码登录 / 注册" : (isRegisterMode ? "注册并登录" : "登录"))
                        Spacer()
                    }
                }
                .disabled(!canSubmit)

                if authMode == .password {
                    Button(isRegisterMode ? "已有账号？切换登录" : "没有账号？注册新账号") {
                        isRegisterMode.toggle()
                        account.errorMessage = nil
                    }
                    .font(.caption)
                }
            }

            Section("快捷登录") {
                Button {
                    isSubmitting = true
                    Task {
                        let ok = await account.signInWithApple()
                        isSubmitting = false
                        if ok { await CloudSyncService.shared.sync(session: session) }
                    }
                } label: {
                    Label("通过 Apple 登录", systemImage: "apple.logo")
                }
                .disabled(isSubmitting)

                if RegionAuthPolicy.isGoogleSignInAvailable() {
                    Button {
                        isSubmitting = true
                        Task {
                            let ok = await account.signInWithGoogle()
                            isSubmitting = false
                            if ok { await CloudSyncService.shared.sync(session: session) }
                        }
                    } label: {
                        Label("通过 Google 登录", systemImage: "globe")
                    }
                    .disabled(isSubmitting)
                }
            }
        }
    }

    private var canSubmit: Bool {
        guard !isSubmitting else { return false }
        let hasEmail = !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if authMode == .otp {
            return hasEmail && otpCode.trimmingCharacters(in: .whitespacesAndNewlines).count == 6
        }
        return hasEmail && !password.isEmpty
    }

    private func sendOtp() {
        isSubmitting = true
        Task {
            let ok = await account.sendEmailOTP(email: email)
            isSubmitting = false
            if ok {
                otpSent = true
                otpCooldown = 60
                Task {
                    while otpCooldown > 0 {
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                        if otpCooldown > 0 { otpCooldown -= 1 }
                    }
                }
            }
        }
    }

    private func submitAuth() {
        guard canSubmit else { return }
        isSubmitting = true
        Task {
            let ok: Bool
            if authMode == .otp {
                ok = await account.verifyEmailOTP(email: email, code: otpCode, displayName: displayName)
            } else if isRegisterMode {
                ok = await account.register(email: email, password: password, displayName: displayName)
            } else {
                ok = await account.login(email: email, password: password)
            }
            isSubmitting = false
            if ok {
                await CloudSyncService.shared.sync(session: session)
            }
        }
    }
}
