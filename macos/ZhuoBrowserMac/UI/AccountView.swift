import SwiftUI
import UniformTypeIdentifiers

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
    @State private var isUploadingAvatar: Bool = false
    @State private var isHoveringAvatar: Bool = false

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
                Button(action: { pickAndUploadAvatar() }) {
                    ZStack(alignment: .bottomTrailing) {
                        avatarImage(size: 68)
                            .overlay(
                                Circle()
                                    .fill(Color.black.opacity(isHoveringAvatar ? 0.35 : 0))
                                    .overlay(
                                        Image(systemName: "camera.fill")
                                            .foregroundColor(.white)
                                            .font(.system(size: 18))
                                            .opacity(isHoveringAvatar ? 1.0 : 0)
                                    )
                            )
                            .clipShape(Circle())

                        if isUploadingAvatar {
                            Circle()
                                .fill(Color.black.opacity(0.45))
                                .frame(width: 68, height: 68)
                                .overlay(
                                    ProgressView()
                                        .controlSize(.small)
                                )
                        }

                        // Badge edit icon
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
                .onHover { hovering in
                    isHoveringAvatar = hovering
                }
                .disabled(isUploadingAvatar)
                .help("点击更换头像")

                Button(action: { pickAndUploadAvatar() }) {
                    Text(isUploadingAvatar ? "正在上传头像..." : "更换头像")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .disabled(isUploadingAvatar)

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

    @ViewBuilder
    private func avatarImage(size: CGFloat) -> some View {
        if let avatarURL = accountManager.currentUser?.resolvedAvatarURL {
            AsyncImage(url: avatarURL) { phase in
                switch phase {
                case .success(let img):
                    img
                        .resizable()
                        .scaledToFill()
                        .frame(width: size, height: size)
                case .failure:
                    initialsAvatar(size: size)
                case .empty:
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.15))
                            .frame(width: size, height: size)
                        ProgressView()
                            .controlSize(.small)
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
            Circle()
                .fill(Color.accentColor.opacity(0.15))
                .frame(width: size, height: size)

            Text(accountManager.currentUser?.displayName.prefix(1).uppercased() ?? "U")
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundColor(.accentColor)
        }
    }

    private func pickAndUploadAvatar() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType.jpeg, UTType.png, UTType.image]
        panel.prompt = "选取"
        panel.message = "请选择用作头像的图片 (支持 JPG / PNG 等)"

        if panel.runModal() == .OK, let fileURL = panel.url {
            processAndUploadImage(at: fileURL)
        }
    }

    private func processAndUploadImage(at fileURL: URL) {
        isUploadingAvatar = true
        accountManager.errorMessage = nil

        Task {
            defer { isUploadingAvatar = false }
            guard let image = NSImage(contentsOf: fileURL) else {
                accountManager.errorMessage = "无法读取所选图片文件"
                return
            }

            // Downscale to max 512x512 to preserve bandwidth and Cloudflare storage
            let maxDimension: CGFloat = 512
            let originalSize = image.size
            guard originalSize.width > 0, originalSize.height > 0 else {
                accountManager.errorMessage = "图片尺寸无效"
                return
            }

            let targetSize: CGSize
            if originalSize.width > maxDimension || originalSize.height > maxDimension {
                let ratio = min(maxDimension / originalSize.width, maxDimension / originalSize.height)
                targetSize = CGSize(width: originalSize.width * ratio, height: originalSize.height * ratio)
            } else {
                targetSize = originalSize
            }

            guard let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(targetSize.width),
                pixelsHigh: Int(targetSize.height),
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .calibratedRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            ) else {
                accountManager.errorMessage = "图片位图解析失败"
                return
            }

            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            image.draw(in: NSRect(origin: .zero, size: targetSize))
            NSGraphicsContext.restoreGraphicsState()

            guard let jpegData = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else {
                accountManager.errorMessage = "图片格式转换失败"
                return
            }

            await accountManager.uploadAvatar(imageData: jpegData, mimeType: "image/jpeg")
        }
    }
}
