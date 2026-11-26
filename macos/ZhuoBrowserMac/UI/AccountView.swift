import SwiftUI
import UniformTypeIdentifiers

private enum MacAuthTab: String, CaseIterable {
    case otp = "验证码"
    case password = "密码"
}

/// View for user login, registration, multi-provider auth, and cloud sync status management.
public struct AccountView: View {
    @ObservedObject var session: BrowserSession
    @Binding var isPresented: Bool
    @ObservedObject private var accountManager = AccountManager.shared

    @State private var authTab: MacAuthTab = .otp
    @State private var isRegisterMode: Bool = false
    @State private var emailInput: String = ""
    @State private var otpCodeInput: String = ""
    @State private var otpSent: Bool = false
    @State private var otpCooldown: Int = 0
    @State private var passwordInput: String = ""
    @State private var displayNameInput: String = ""
    @State private var isSubmitting: Bool = false
    @State private var isUploadingAvatar: Bool = false
    @State private var isHoveringAvatar: Bool = false
    @State private var isShowingFilePicker: Bool = false
    @State private var isShowingDeleteAccountAlert: Bool = false
    @State private var isDeletingAccount: Bool = false

    public var body: some View {
        VStack(spacing: 0) {
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
        .frame(width: 380)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            if emailInput.isEmpty, let savedEmail = accountManager.currentUser?.email {
                emailInput = savedEmail
            }
            if displayNameInput.isEmpty, let savedName = accountManager.currentUser?.displayName {
                displayNameInput = savedName
            }
        }
        .fileImporter(
            isPresented: $isShowingFilePicker,
            allowedContentTypes: [UTType.image, UTType.jpeg, UTType.png],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                processAndUploadImage(at: url)
            case .failure(let error):
                accountManager.errorMessage = "选取图片失败: \(error.localizedDescription)"
            }
        }
    }

    private var loggedInContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 8) {
                    Button(action: { pickAndUploadAvatar() }) {
                        ZStack(alignment: .bottomTrailing) {
                            avatarImage(size: 64)
                                .overlay(
                                    Circle()
                                        .fill(Color.black.opacity(isHoveringAvatar ? 0.35 : 0))
                                        .overlay(
                                            Image(systemName: "camera.fill")
                                                .foregroundColor(.white)
                                                .font(.system(size: 16))
                                                .opacity(isHoveringAvatar ? 1.0 : 0)
                                        )
                                )
                                .clipShape(Circle())

                            if isUploadingAvatar {
                                Circle()
                                    .fill(Color.black.opacity(0.45))
                                    .frame(width: 64, height: 64)
                                    .overlay(ProgressView().controlSize(.small))
                            }

                            Circle()
                                .fill(Color(nsColor: .windowBackgroundColor))
                                .frame(width: 22, height: 22)
                                .overlay(
                                    Image(systemName: "pencil.circle.fill")
                                        .foregroundColor(.accentColor)
                                        .font(.system(size: 18))
                                )
                                .offset(x: 2, y: 2)
                        }
                    }
                    .buttonStyle(.plain)
                    .onHover { isHoveringAvatar = $0 }
                    .disabled(isUploadingAvatar)
                    .help("点击更换头像")

                    Text(accountManager.currentUser?.displayName ?? "用户")
                        .font(.system(size: 16, weight: .semibold))

                    Text(accountManager.currentUser?.email ?? "")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)

                    if let pro = accountManager.proEntitlement, pro.active {
                        Label("卓阅 Pro 跨端权益已激活", systemImage: "crown.fill")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 3)
                            .background(Color.orange.opacity(0.12))
                            .cornerRadius(999)
                    }

                    if let errorMsg = accountManager.errorMessage {
                        Text(errorMsg)
                            .font(.system(size: 11))
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.top, 12)

                // Cloud Sync Status Card
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "icloud.fill")
                            .foregroundColor(.blue)
                            .font(.system(size: 14))
                        Text("多端云同步 (书签 / 偏好 / 站点规则)")
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                        if accountManager.isSyncing {
                            ProgressView().controlSize(.mini)
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
                            Text(accountManager.isSyncing ? "正在同步..." : "立即同步全端数据")
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

                // Remote Device Tabs
                if !accountManager.remoteDeviceTabs.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("来自其他设备的标签页")
                            .font(.system(size: 12, weight: .semibold))
                        ForEach(accountManager.remoteDeviceTabs) { device in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(device.deviceName) (\(device.platform))")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.secondary)
                                ForEach(device.tabs.prefix(5)) { tab in
                                    Button(action: {
                                        _ = session.createTab(url: tab.url)
                                        isPresented = false
                                    }) {
                                        HStack {
                                            Image(systemName: "safari")
                                                .font(.system(size: 11))
                                                .foregroundColor(.accentColor)
                                            Text(tab.title)
                                                .font(.system(size: 11.5))
                                                .lineLimit(1)
                                            Spacer()
                                        }
                                        .padding(.vertical, 3)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(12)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(10)
                }

                // Linked Identities
                if !accountManager.linkedIdentities.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("已关联登录方式")
                            .font(.system(size: 12, weight: .semibold))
                        ForEach(accountManager.linkedIdentities) { identity in
                            HStack {
                                Text(identity.displayLabel)
                                    .font(.system(size: 11.5))
                                if let email = identity.email, !email.isEmpty {
                                    Text(email)
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                if accountManager.linkedIdentities.count > 1 {
                                    Button("解绑") {
                                        Task { await accountManager.unlinkIdentity(provider: identity.provider) }
                                    }
                                    .font(.system(size: 11))
                                    .buttonStyle(.plain)
                                    .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .padding(12)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(10)
                }

                HStack(spacing: 18) {
                    Button(action: { accountManager.logout() }) {
                        Text("退出登录")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .disabled(isDeletingAccount)

                    Text("·")
                        .foregroundColor(.secondary.opacity(0.5))

                    Button(action: { isShowingDeleteAccountAlert = true }) {
                        Text(isDeletingAccount ? "正在注销..." : "永久注销并删除账号...")
                            .font(.system(size: 12))
                            .foregroundColor(.red)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .disabled(isDeletingAccount)
                }
                .padding(.bottom, 16)
            }
            .padding(.horizontal, 20)
        }
        .frame(maxHeight: 520)
        .alert("确定永久注销并删除此账号？", isPresented: $isShowingDeleteAccountAlert) {
            Button("永久删除账号", role: .destructive) {
                isDeletingAccount = true
                Task {
                    let deleted = await accountManager.deleteAccount()
                    isDeletingAccount = false
                    if deleted {
                        isPresented = false
                    }
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作将永久删除您的云端账号、同步书签设置与头像数据，且无法恢复。本机当前打开的标签页与本地数据不会被清空。")
        }
    }

    private var authFormContent: some View {
        VStack(spacing: 14) {
            Picker("登录方式", selection: $authTab) {
                ForEach(MacAuthTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.top, 6)

            VStack(spacing: 10) {
                if authTab == .password && isRegisterMode {
                    TextField("昵称", text: $displayNameInput)
                        .textFieldStyle(.roundedBorder)
                }

                TextField("邮箱地址", text: $emailInput)
                    .textFieldStyle(.roundedBorder)

                if authTab == .otp {
                    HStack(spacing: 8) {
                        TextField("6 位邮箱验证码", text: $otpCodeInput)
                            .textFieldStyle(.roundedBorder)
                        Button(otpCooldown > 0 ? "\(otpCooldown)s" : (otpSent ? "重发" : "获取验证码")) {
                            sendOtp()
                        }
                        .disabled(isSubmitting || otpCooldown > 0 || emailInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                } else {
                    SecureField("密码 (至少 6 位)", text: $passwordInput)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            if canSubmit { submitAuth() }
                        }
                }
            }

            if let errorMsg = accountManager.errorMessage {
                Text(errorMsg)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
                    .lineLimit(2)
            }

            Button(action: { submitAuth() }) {
                HStack {
                    Spacer()
                    if isSubmitting {
                        ProgressView().controlSize(.mini).padding(.trailing, 4)
                    }
                    Text(authTab == .otp ? "验证码登录 / 注册" : (isRegisterMode ? "立即注册" : "登录"))
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                }
                .padding(.vertical, 8)
                .background(Color.accentColor)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .disabled(!canSubmit)

            if authTab == .password {
                Button(action: {
                    isRegisterMode.toggle()
                    accountManager.errorMessage = nil
                }) {
                    Text(isRegisterMode ? "已有账号？返回登录" : "没有账号？免费注册")
                        .font(.system(size: 11))
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
            }

            Divider()

            VStack(spacing: 8) {
                Button(action: {
                    isSubmitting = true
                    Task {
                        let ok = await accountManager.signInWithApple()
                        isSubmitting = false
                        if ok {
                            await accountManager.syncWithCloud(session: session)
                        }
                    }
                }) {
                    HStack {
                        Spacer()
                        Image(systemName: "apple.logo")
                        Text("通过 Apple 登录")
                            .font(.system(size: 12.5, weight: .medium))
                        Spacer()
                    }
                    .padding(.vertical, 7)
                    .background(Color.primary.opacity(0.08))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(isSubmitting)

                if RegionAuthPolicy.isGoogleSignInAvailable() {
                    Button(action: {
                        isSubmitting = true
                        Task {
                            let ok = await accountManager.signInWithGoogle()
                            isSubmitting = false
                            if ok {
                                await accountManager.syncWithCloud(session: session)
                            }
                        }
                    }) {
                        HStack {
                            Spacer()
                            Image(systemName: "globe")
                            Text("通过 Google 登录")
                                .font(.system(size: 12.5, weight: .medium))
                            Spacer()
                        }
                        .padding(.vertical, 7)
                        .background(Color.primary.opacity(0.08))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .disabled(isSubmitting)
                }
            }

            HStack(spacing: 4) {
                Text("使用账号服务即同意")
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
                Button("用户协议") {
                    isPresented = false
                    _ = session.createTab(url: "https://zhuobrowser.youdroid.top/terms.html")
                }
                .buttonStyle(.link)
                .font(.system(size: 10.5))
                Text("与")
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
                Button("隐私政策") {
                    isPresented = false
                    _ = session.createTab(url: "https://zhuobrowser.youdroid.top/privacy.html")
                }
                .buttonStyle(.link)
                .font(.system(size: 10.5))
            }
            .padding(.bottom, 14)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var canSubmit: Bool {
        guard !isSubmitting else { return false }
        let hasEmail = !emailInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if authTab == .otp {
            return hasEmail && otpCodeInput.trimmingCharacters(in: .whitespacesAndNewlines).count == 6
        }
        return hasEmail && !passwordInput.isEmpty && (!isRegisterMode || !displayNameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func sendOtp() {
        isSubmitting = true
        Task {
            let ok = await accountManager.sendEmailOTP(email: emailInput)
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
            let success: Bool
            if authTab == .otp {
                success = await accountManager.verifyEmailOTP(email: emailInput, code: otpCodeInput, displayName: displayNameInput)
            } else if isRegisterMode {
                success = await accountManager.register(email: emailInput, password: passwordInput, displayName: displayNameInput)
            } else {
                success = await accountManager.login(email: emailInput, password: passwordInput)
            }
            isSubmitting = false
            if success {
                await accountManager.syncWithCloud(session: session)
            }
        }
    }

    @ViewBuilder
    private func avatarImage(size: CGFloat) -> some View {
        if let cachedImage = accountManager.avatarImage {
            Image(nsImage: cachedImage)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
        } else if let avatarURL = accountManager.currentUser?.resolvedAvatarURL {
            AsyncImage(url: avatarURL) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill().frame(width: size, height: size)
                case .failure:
                    initialsAvatar(size: size)
                case .empty:
                    ZStack {
                        Circle().fill(Color.accentColor.opacity(0.15)).frame(width: size, height: size)
                        ProgressView().controlSize(.small)
                    }
                @unknown default:
                    initialsAvatar(size: size)
                }
            }
            .frame(width: size, height: size)
        } else {
            initialsAvatar(size: size)
        }
    }

    private func initialsAvatar(size: CGFloat) -> some View {
        ZStack {
            Circle().fill(Color.accentColor.opacity(0.15)).frame(width: size, height: size)
            Text(accountManager.currentUser?.displayName.prefix(1).uppercased() ?? "U")
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundColor(.accentColor)
        }
    }

    private func pickAndUploadAvatar() {
        accountManager.errorMessage = nil
        isShowingFilePicker = true
    }

    private func processAndUploadImage(at fileURL: URL) {
        accountManager.errorMessage = nil
        isUploadingAvatar = true

        let isScoped = fileURL.startAccessingSecurityScopedResource()
        let rawData = try? Data(contentsOf: fileURL)
        if isScoped {
            fileURL.stopAccessingSecurityScopedResource()
        }

        guard let data = rawData, let image = NSImage(data: data) else {
            isUploadingAvatar = false
            accountManager.errorMessage = "无法读取所选图片文件"
            return
        }

        Task {
            defer { isUploadingAvatar = false }
            guard let jpegData = AccountManager.compressAvatarImage(image) else {
                accountManager.errorMessage = "图片压缩转换失败"
                return
            }
            await accountManager.uploadAvatar(imageData: jpegData, mimeType: "image/jpeg")
        }
    }
}
