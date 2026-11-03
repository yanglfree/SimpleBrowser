import SwiftUI
import AppKit

/// Dedicated Security Settings sub-page for ZhuoBrowser Mac, replicating the Chrome standard
/// security settings interface (`chrome://settings/security`) with native macOS SwiftUI controls.
public struct SecuritySettingsView: View {
    @ObservedObject var session: BrowserSession
    var onBack: () -> Void
    var onDismiss: () -> Void

    @ObservedObject private var settings = BrowserSettings.shared
    @State private var isShowingHelpSheet: Bool = false
    @State private var isShowingTurnOffSafeBrowsingAlert: Bool = false
    @State private var isShowingJITSheet: Bool = false
    @State private var isShowingPasskeySheet: Bool = false
    @State private var isEnhancedExpanded: Bool = false

    public init(session: BrowserSession, onBack: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        self.session = session
        self.onBack = onBack
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header bar: [← 安全]  ...  [?]
            HStack(spacing: 12) {
                Button(action: onBack) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 13, weight: .semibold))
                        Text("安全")
                            .font(.system(size: 15, weight: .bold))
                    }
                    .foregroundColor(.primary)
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: { isShowingHelpSheet = true }) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("查看关于安全浏览与安全设置的说明")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 18) {
                    // 1. 安全浏览 (Safe Browsing)
                    safeBrowsingSection

                    Divider()

                    // 2. 安全连接 (Secure Connections)
                    secureConnectionsSection

                    Divider()

                    // 3. 高级 (Advanced)
                    advancedSection
                }
                .padding(20)
            }
            .frame(height: 520)

            Divider()

            // Footer
            HStack {
                Button("返回") {
                    onBack()
                }
                .controlSize(.regular)

                Spacer()

                Button("完成") {
                    onDismiss()
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.regular)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 560)
        .background(Color(nsColor: .controlBackgroundColor))
        .alert("确定要关闭安全浏览保护吗？", isPresented: $isShowingTurnOffSafeBrowsingAlert) {
            Button("关闭保护", role: .destructive) {
                settings.safeBrowsingLevel = .disabled
            }
            Button("保持开启", role: .cancel) {}
        } message: {
            Text("关闭后，系统将不会主动拦截危险网站、钓鱼链接和恶意下载内容。此操作不推荐。")
        }
        .sheet(isPresented: $isShowingHelpSheet) {
            helpSheet
        }
        .sheet(isPresented: $isShowingJITSheet) {
            javascriptOptimizationSheet
        }
        .sheet(isPresented: $isShowingPasskeySheet) {
            passkeyManagementSheet
        }
    }

    // MARK: - 1. 安全浏览 (Safe Browsing)

    private var safeBrowsingSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("安全浏览")
                .font(.system(size: 13, weight: .bold))

            // Option 1: 增强型保护
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    radioIndicator(isSelected: settings.safeBrowsingLevel == .enhanced)
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("增强型保护")
                            .font(.system(size: 13, weight: .medium))

                        Text("根据系统向安全云端发送的浏览数据，实时提供 AI 赋能的保护，防范危险的网站、下载内容和扩展程序")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            isEnhancedExpanded.toggle()
                        }
                    }) {
                        Image(systemName: isEnhancedExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .help(isEnhancedExpanded ? "收起功能详情" : "展开功能详情")
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    settings.safeBrowsingLevel = .enhanced
                }

                if isEnhancedExpanded {
                    VStack(alignment: .leading, spacing: 6) {
                        bulletPoint("实时比对已知恶意网站并提供前置主动拦截")
                        bulletPoint("针对新出现的未知网络钓鱼威胁由安全云端智能校验")
                        bulletPoint("在检测到可疑扩展程序或被篡改的文件下载时发出强提醒")
                    }
                    .padding(.leading, 26)
                    .padding(.top, 2)
                }
            }

            // Option 2: 标准保护 (Default)
            HStack(alignment: .top, spacing: 10) {
                radioIndicator(isSelected: settings.safeBrowsingLevel == .standard)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    Text("标准保护")
                        .font(.system(size: 13, weight: .medium))

                    Text("防范已知危险的网站、下载内容和扩展程序。当您访问某个网站时，浏览器会通过可能隐藏 IP 地址的隐私保护服务器将经过混淆处理的网址片段发送给云端。如果网站有可疑行为，系统也会发送完整网址和少量网页内容。")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                settings.safeBrowsingLevel = .standard
            }

            // Option 3: 不保护（不建议）
            HStack(alignment: .top, spacing: 10) {
                radioIndicator(isSelected: settings.safeBrowsingLevel == .disabled)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    Text("不保护（不建议）")
                        .font(.system(size: 13, weight: .medium))

                    Text("不会防范危险的网站、下载内容和扩展程序。您在其他安全产品中的设置不受影响。")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if settings.safeBrowsingLevel != .disabled {
                    isShowingTurnOffSafeBrowsingAlert = true
                }
            }
        }
    }

    private func radioIndicator(isSelected: Bool) -> some View {
        ZStack {
            Circle()
                .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.4), lineWidth: 1.5)
                .frame(width: 14, height: 14)
            if isSelected {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 8, height: 8)
            }
        }
        .frame(width: 16, height: 16)
    }

    private func bulletPoint(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 2. 安全连接 (Secure Connections)

    private var secureConnectionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("安全连接")
                .font(.system(size: 13, weight: .bold))

            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("一律使用安全连接")
                        .font(.system(size: 13, weight: .medium))

                    Text("在您访问不支持安全连接的网站前，系统会发出警告")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Toggle("", isOn: $settings.alwaysUseSecureConnections)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        }
    }

    // MARK: - 3. 高级 (Advanced)

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("高级")
                .font(.system(size: 13, weight: .bold))

            // 3.1 发现密码遭遇数据泄露时发出警告
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("发现密码遭遇数据泄露时向您发出警告")
                        .font(.system(size: 13, weight: .medium))

                    Text("如果浏览器发现您使用的某个密码已被发布到网上，就会发出警告。在这个过程中，您的密码和用户名始终加密，任何人/任何一方都无法读取。")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Toggle("", isOn: $settings.leakedPasswordDetectionEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            // 3.2 使用安全 DNS
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("使用安全 DNS")
                            .font(.system(size: 13, weight: .medium))

                        Text("让对您的互联网流量有访问权限的用户更难看到您访问的网站。浏览器会使用安全连接在 DNS（域名系统）中查找网站的 IP 地址。")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Toggle("", isOn: $settings.secureDNSEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                if settings.secureDNSEnabled {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("选择 DNS 提供商")
                                .font(.system(size: 12))
                                .foregroundColor(.primary)

                            Spacer()

                            Picker("", selection: $settings.secureDNSProvider) {
                                ForEach(SecureDNSProvider.allCases) { provider in
                                    Text(provider.displayName).tag(provider)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 220)
                        }

                        if settings.secureDNSProvider == .custom {
                            HStack {
                                Text("DoH URL:")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                TextField("https://example.com/dns-query", text: $settings.customSecureDNSURL)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 11))
                            }
                            .padding(.top, 2)
                        }
                    }
                    .padding(.leading, 12)
                    .padding(.vertical, 6)
                    .background(Color.secondary.opacity(0.04))
                    .cornerRadius(6)
                }
            }

            Divider()

            // 3.3 管理 JavaScript 优化和安全性
            navigationRow(
                title: "管理 JavaScript 优化和安全性",
                subtitle: settings.javascriptJITOptimizationEnabled
                    ? "使用高效 JIT 优化引擎加速网站，但在特定安全模式下可降低攻击面。此设置已开启。"
                    : "已关闭 JIT 优化引擎，采用严格安全沙箱模式。",
                trailingIcon: "chevron.right"
            ) {
                isShowingJITSheet = true
            }

            // 3.4 管理安全密钥
            navigationRow(
                title: "管理安全密钥",
                subtitle: "重置安全密钥并创建 PIN 码 · 支持 FIDO2 硬件密钥与 Passkey",
                trailingIcon: "chevron.right"
            ) {
                isShowingPasskeySheet = true
            }

            // 3.5 管理证书
            navigationRow(
                title: "管理证书",
                subtitle: "管理 HTTPS/SSL 证书和系统信任设置",
                trailingIcon: "arrow.up.forward.square"
            ) {
                openKeychainAccess()
            }

            // 3.6 Google 高级保护计划
            navigationRow(
                title: "Google 高级保护计划",
                subtitle: "为面临定向攻击风险的用户提供 Google 最强大的账号安全服务",
                trailingIcon: "arrow.up.forward.square"
            ) {
                onDismiss()
                _ = session.createTab(url: "https://landing.google.com/advanced-protection/")
            }
        }
    }

    private func navigationRow(
        title: String,
        subtitle: String,
        trailingIcon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)

                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Image(systemName: trailingIcon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - System Actions

    private func openKeychainAccess() {
        let candidatePaths = [
            "/System/Applications/Utilities/Keychain Access.app",
            "/Applications/Utilities/Keychain Access.app"
        ]
        for path in candidatePaths {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.path) {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
                return
            }
        }
        // Fallback: system command
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Keychain Access.app"))
    }

    private func openSystemPasskeysSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Passwords-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Sub-Sheets

    private var helpSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("安全设置帮助与说明")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                Button("关闭") {
                    isShowingHelpSheet = false
                }
                .controlSize(.small)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("• 安全浏览：防范网络欺诈、恶意软件与不安全下载。标准保护为大多数用户提供恰到好处的隐私与防护平衡；增强型保护实时分析最新未知网络威胁。")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text("• 安全连接 (HTTPS)：自动升级公网连接至加密协议，在明文 HTTP 握手或遭遇证书风险时发出预警。")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text("• 安全 DNS：通过加密通道查找域名，保护您的浏览目的地不被本地路由器或网络运营商窥探。")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text("• 硬件安全密钥与通行密钥：采用抗钓鱼的 WebAuthn / FIDO2 标准，直接结合 Mac 触控 ID 与实体安全密钥。")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(20)
        .frame(width: 440, height: 260)
    }

    private var javascriptOptimizationSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("管理 JavaScript 优化和安全性")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                Button("完成") {
                    isShowingJITSheet = false
                }
                .controlSize(.small)
            }

            VStack(alignment: .leading, spacing: 10) {
                Toggle("启用 V8 / JavaScriptCore JIT 即时编译优化", isOn: $settings.javascriptJITOptimizationEnabled)
                    .font(.system(size: 13, weight: .medium))

                Text("开启时（默认推荐）：使用引擎的 JIT 动态编译器执行复杂脚本与富媒体网页，提供极致的速度与响应度。")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Text("关闭时：完全禁用动态机器码编译，在对抗高危零日漏洞、内存破坏类攻击（JIT Spraying）时具有极高防御力，但重度网页交互速度会受影响。")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .background(Color.secondary.opacity(0.06))
            .cornerRadius(8)

            Spacer()
        }
        .padding(20)
        .frame(width: 440, height: 240)
    }

    private var passkeyManagementSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("管理安全密钥与通行密钥")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                Button("完成") {
                    isShowingPasskeySheet = false
                }
                .controlSize(.small)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "key.fill")
                        .foregroundColor(.accentColor)
                    Text("通行密钥 (Passkey) & FIDO2 硬件密钥")
                        .font(.system(size: 13, weight: .semibold))
                }

                Text("通行密钥基于 FIDO 联盟和 W3C WebAuthn 开放标准。在支持的网站上，您可以使用 Mac 触控 ID 或插入外部硬件密钥（如 YubiKey）直接登录，免去密码输入且天然抵御钓鱼攻击。")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Text("macOS 钥匙串集成状态")
                        .font(.system(size: 12))
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 11))
                        Text("系统已就绪")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.green)
                    }
                }
                .padding(.top, 4)
            }
            .padding(12)
            .background(Color.secondary.opacity(0.06))
            .cornerRadius(8)

            HStack {
                Spacer()
                Button("打开系统「密码与安全密钥」设置...") {
                    openSystemPasskeysSettings()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            Spacer()
        }
        .padding(20)
        .frame(width: 460, height: 260)
    }
}
