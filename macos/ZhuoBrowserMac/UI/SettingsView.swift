import SwiftUI

/// Preferences sheet for ZhuoBrowser Mac, prioritized to align with HarmonyOS settings categories.
public struct SettingsView: View {
    @ObservedObject var session: BrowserSession
    @Binding var isPresented: Bool

    @ObservedObject private var settings = BrowserSettings.shared
    @ObservedObject private var accountManager = AccountManager.shared
    @ObservedObject private var bgManager = HomeBackgroundManager.shared

    @State private var isShowingAccountSheet: Bool = false
    @State private var isShowingClearHistoryAlert: Bool = false
    @State private var isShowingClearDataAlert: Bool = false
    @State private var didClearDataNotice: Bool = false

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "gearshape.fill")
                        .foregroundColor(.accentColor)
                        .font(.system(size: 15))
                    Text("偏好设置")
                        .font(.system(size: 15, weight: .bold))
                }
                Spacer()
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 15))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 20) {
                    // 1. 常规与搜索 (General & Search)
                    generalSection

                    Divider()

                    // 2. 主页背景与壁纸 (Home Background - 参考 HarmonyOS 端)
                    wallpaperSection

                    Divider()

                    // 3. 安全防护与规则拦截 (Content Protection - 参考 HarmonyOS 端)
                    protectionSection

                    Divider()

                    // 4. 内存卫士与标签管理 (Memory Saver & Live Budget)
                    memorySection

                    Divider()

                    // 5. 账号与云端同步 (Account & Cloud Sync)
                    accountSection

                    Divider()

                    // 6. 清除浏览数据 (Clear Browsing Data - 参考 HarmonyOS 端)
                    clearDataSection

                    Divider()

                    // 7. 关于卓阅 (About)
                    aboutSection
                }
                .padding(20)
            }
            .frame(height: 520)

            Divider()

            // Footer
            HStack {
                Spacer()
                Button("完成") {
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 560)
        .background(Color(nsColor: .controlBackgroundColor))
        .sheet(isPresented: $isShowingAccountSheet) {
            AccountView(session: session, isPresented: $isShowingAccountSheet)
        }
        .alert("确定清空所有历史记录？", isPresented: $isShowingClearHistoryAlert) {
            Button("清空", role: .destructive) {
                session.clearHistory()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作将永久清空本机所有访问记录，无法撤销。")
        }
        .alert("确定清理网页缓存与 Cookie？", isPresented: $isShowingClearDataAlert) {
            Button("清理", role: .destructive) {
                session.clearWebsiteData {
                    didClearDataNotice = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        didClearDataNotice = false
                    }
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将清除所有网站的本地缓存、Cookie 及离线存储。已登录的网页状态可能需要重新登录。")
        }
    }

    // MARK: - Sections

    // 1. 常规与搜索
    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "常规与搜索", icon: "magnifyingglass")

            HStack {
                Text("默认搜索引擎")
                    .font(.system(size: 13))
                Spacer()
                Picker("", selection: $settings.searchEngine) {
                    ForEach(SearchEngine.allCases) { engine in
                        Text(engine.rawValue).tag(engine)
                    }
                }
                .labelsHidden()
                .frame(width: 160)
            }

            Toggle("在主页显示快捷访问站点卡片", isOn: $settings.quickSitesEnabled)
                .toggleStyle(.checkbox)
                .font(.system(size: 13))
        }
    }

    // 2. 主页背景与壁纸 (参考 HarmonyOS 端)
    private var wallpaperSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "主页背景 (参考 Harmony 端)", icon: "photo.on.rectangle.angled")

            HStack {
                Text("壁纸来源")
                    .font(.system(size: 13))
                Spacer()
                Picker("", selection: Binding(
                    get: { bgManager.source },
                    set: { bgManager.setSource($0) }
                )) {
                    Text("必应每日壁纸").tag(WallpaperSource.daily)
                    Text("精选壁纸").tag(WallpaperSource.preset)
                    Text("本地自定义图片").tag(WallpaperSource.custom)
                    Text("无背景 (纯色)").tag(WallpaperSource.none)
                }
                .labelsHidden()
                .frame(width: 160)
            }

            if bgManager.source == .preset {
                VStack(alignment: .leading, spacing: 6) {
                    Text("选择精选预设壁纸：")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(HomeBackgroundManager.presets) { preset in
                                Button(action: {
                                    bgManager.selectPreset(id: preset.id)
                                }) {
                                    VStack(spacing: 4) {
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color.secondary.opacity(0.15))
                                            .frame(width: 64, height: 42)
                                            .overlay(
                                                Text(preset.name.prefix(2))
                                                    .font(.system(size: 11, weight: .bold))
                                                    .foregroundColor(.secondary)
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .stroke(bgManager.selectedPresetId == preset.id ? Color.accentColor : Color.clear, lineWidth: 2)
                                            )

                                        Text(preset.name)
                                            .font(.system(size: 10))
                                            .foregroundColor(.primary)
                                            .lineLimit(1)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            } else if bgManager.source == .custom {
                HStack {
                    Text("自定义壁纸文件")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("从本地文件选择...") {
                        bgManager.chooseCustomImage()
                    }
                    .font(.system(size: 12))
                }
            } else if bgManager.source == .daily {
                Text("已开启必应每日壁纸：系统每日自动从微软必应抓取最新高清风光照片并本地缓存。")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
    }

    // 3. 内容安全与拦截 (参考 HarmonyOS 端)
    private var protectionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: "安全防护与去噪拦截", icon: "shield.lefthalf.filled")

            Toggle("启用原生广告与跟踪拦截 (基于 WebKit 原生字节码规则评估)", isOn: $settings.adBlockEnabled)
                .toggleStyle(.checkbox)
                .font(.system(size: 13))

            Toggle("启用页面元素去噪净化 (Cosmetic Cleanup 屏蔽冗余干扰项)", isOn: $settings.cosmeticCleanupEnabled)
                .toggleStyle(.checkbox)
                .font(.system(size: 13))
        }
    }

    // 4. 内存卫士与标签配额
    private var memorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(title: "内存卫士与活跃标签配额", icon: "leaf.fill")

            HStack {
                Text("活跃 WebKit 渲染进程配额")
                    .font(.system(size: 13))
                Spacer()
                Picker("", selection: $settings.liveWebViewBudget) {
                    Text("1 个 (极致省内存，后台立即休眠)").tag(1)
                    Text("2 个 (默认推荐，平衡切换速度与内存)").tag(2)
                    Text("3 个 (常驻 3 个活跃页面)").tag(3)
                    Text("4 个 (宽松配额)").tag(4)
                }
                .labelsHidden()
                .frame(width: 270)
                .onChange(of: settings.liveWebViewBudget) { _ in
                    session.enforceMemoryBudget()
                }
            }

            Text("超出配额的后台标签将自动销毁 WebKit 渲染进程以释放内存，点击标签时自动无损恢复。")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }

    // 5. 账号与云端同步
    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionHeader(title: "账号与云端同步 (Cloudflare D1)", icon: "icloud.fill")
                Spacer()
                Button(action: { isShowingAccountSheet = true }) {
                    Text(accountManager.isLoggedIn ? "账号中心" : "登录 / 注册")
                        .font(.system(size: 12))
                }
            }

            if accountManager.isLoggedIn {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("当前账号：\(accountManager.currentUser?.displayName ?? "用户") (\(accountManager.currentUser?.email ?? ""))")
                            .font(.system(size: 12, weight: .medium))
                        if let lastSync = accountManager.lastSyncTime {
                            Text("上次同步成功：\(lastSync, style: .time)")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        } else {
                            Text("尚未同步")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    Button(action: {
                        Task {
                            await accountManager.syncWithCloud(session: session)
                        }
                    }) {
                        HStack(spacing: 4) {
                            if accountManager.isSyncing {
                                ProgressView()
                                    .controlSize(.mini)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 11))
                            }
                            Text(accountManager.isSyncing ? "正在同步" : "立即同步")
                                .font(.system(size: 11))
                        }
                    }
                    .disabled(accountManager.isSyncing)
                }

                if let syncError = accountManager.syncErrorMessage {
                    Text(syncError)
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                }
            } else {
                Text("登录账号后可将书签与配置通过 Cloudflare D1 自动安全备份并跨端同步。")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
    }

    // 6. 清除浏览数据
    private var clearDataSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: "清除浏览数据", icon: "trash.fill")

            HStack {
                Text("历史记录 (\(session.history.count) 条)")
                    .font(.system(size: 13))
                Spacer()
                Button("清空所有历史记录...") {
                    isShowingClearHistoryAlert = true
                }
                .font(.system(size: 12))
                .disabled(session.history.isEmpty)
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("网页缓存与 Cookie")
                        .font(.system(size: 13))
                    Text("释放本地网页缓存与离线存储数据")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(didClearDataNotice ? "已清除" : "清理缓存与 Cookie...") {
                    isShowingClearDataAlert = true
                }
                .font(.system(size: 12))
            }
        }
    }

    // 7. 关于卓阅
    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader(title: "关于卓阅 (ZhuoBrowser)", icon: "info.circle.fill")

            HStack {
                Text("卓阅 Mac 原生轻量浏览器")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text("v1.0.0 (Build 2026.11)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Text("秉持极致省内存、极简抗干扰的纯粹浏览哲学。采用原生 macOS WebKit 与动态内存配额策略，打造安静高效的桌面网络视窗。")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func sectionHeader(title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundColor(.accentColor)
                .font(.system(size: 13))
            Text(title)
                .font(.system(size: 13, weight: .bold))
        }
    }
}
