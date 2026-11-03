import SwiftUI

/// Preferences sheet for ZhuoBrowser Mac, prioritized to align with HarmonyOS settings categories.
public struct SettingsView: View {
    public enum SettingsSubpage {
        case main
        case security
    }

    @ObservedObject var session: BrowserSession
    @Binding var isPresented: Bool

    @ObservedObject private var settings = BrowserSettings.shared
    @ObservedObject private var defaultBrowserManager = DefaultBrowserManager.shared
    @ObservedObject private var accountManager = AccountManager.shared
    @ObservedObject private var bgManager = HomeBackgroundManager.shared
    @ObservedObject private var extensionManager = ExtensionManager.shared

    @State private var currentSubpage: SettingsSubpage
    @State private var isShowingAccountSheet: Bool = false
    @State private var isShowingClearHistoryAlert: Bool = false
    @State private var isShowingClearDataAlert: Bool = false
    @State private var didClearDataNotice: Bool = false

    public init(session: BrowserSession, isPresented: Binding<Bool>, initialSubpage: SettingsSubpage = .main) {
        self.session = session
        self._isPresented = isPresented
        self._currentSubpage = State(initialValue: initialSubpage)
    }

    public var body: some View {
        Group {
            if currentSubpage == .security {
                SecuritySettingsView(
                    session: session,
                    onBack: {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            currentSubpage = .main
                        }
                    },
                    onDismiss: {
                        isPresented = false
                    }
                )
            } else {
                mainSettingsContent
            }
        }
        .onDisappear {
            settings.flushSynchronously()
        }
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

    private var mainSettingsContent: some View {
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

                    // 3.5. 扩展程序与插件中心 (Chrome Extensions & UserScripts)
                    extensionsSection

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

                    // 7. 关于 Zhuo浏览器 (About)
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
    }

    // MARK: - Sections

    // 1. 常规与搜索
    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "常规与搜索", icon: "magnifyingglass")

            defaultBrowserRow

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
        .onAppear {
            defaultBrowserManager.refreshStatus()
        }
    }

    private var defaultBrowserRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("默认网页浏览器")
                            .font(.system(size: 13, weight: .medium))
                        if defaultBrowserManager.isDefaultBrowser {
                            HStack(spacing: 3) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 10))
                                Text("已设为默认")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .foregroundColor(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.12))
                            .cornerRadius(4)
                        }
                    }

                    Text(defaultBrowserManager.isDefaultBrowser
                         ? "Zhuo浏览器 当前是您的系统默认网页浏览器"
                         : "当前系统默认：\(defaultBrowserManager.currentDefaultBrowserName) · 设为默认后可直接打开所有网页链接与 HTML 文件")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                HStack(spacing: 8) {
                    if !defaultBrowserManager.isDefaultBrowser {
                        Button(action: {
                            defaultBrowserManager.setAsDefaultBrowser()
                        }) {
                            Text(defaultBrowserManager.isRequestingDefault ? "正在请求..." : "设为默认浏览器")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(defaultBrowserManager.isRequestingDefault)
                    }

                    Button("系统设置...") {
                        defaultBrowserManager.openSystemDefaultBrowserSettings()
                    }
                    .font(.system(size: 12))
                    .controlSize(.small)
                    .help("打开 macOS「系统设置 → 桌面与程序坞 → 默认网页浏览器」")
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(defaultBrowserManager.isDefaultBrowser
                          ? Color.green.opacity(0.06)
                          : Color.secondary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(defaultBrowserManager.isDefaultBrowser
                            ? Color.green.opacity(0.2)
                            : Color.secondary.opacity(0.15), lineWidth: 1)
            )

            if let statusMessage = defaultBrowserManager.statusMessage, !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.system(size: 11))
                    .foregroundColor(defaultBrowserManager.isDefaultBrowser ? .green : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
                                        ZStack {
                                            if let thumb = bgManager.presetThumbnails[preset.id] {
                                                Image(nsImage: thumb)
                                                    .resizable()
                                                    .scaledToFill()
                                                    .frame(width: 78, height: 48)
                                                    .clipped()
                                            } else {
                                                Color.secondary.opacity(0.15)
                                                Text(preset.name.prefix(2))
                                                    .font(.system(size: 11, weight: .bold))
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        .frame(width: 78, height: 48)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(bgManager.selectedPresetId == preset.id ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: bgManager.selectedPresetId == preset.id ? 2 : 1)
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
                bingDailyHistorySection
            }
        }
        .onAppear {
            bgManager.refreshBingHistoryIfNeeded()
        }
    }

    private var bingDailyHistorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let active = bgManager.activeBingWallpaper {
                    HStack(spacing: 4) {
                        Image(systemName: bgManager.selectedBingDate == nil ? "sparkles" : "calendar")
                            .font(.system(size: 11))
                            .foregroundColor(.accentColor)
                        Text(bgManager.selectedBingDate == nil
                             ? "今日自动更新：\(active.title) (\(active.formattedFullDate))"
                             : "已选历史壁纸：\(active.title) (\(active.formattedFullDate))")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                    }
                } else {
                    Text("正在从 Cloudflare 云端加载必应壁纸归档...")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()

                if bgManager.isLoading || bgManager.isLoadingHistory {
                    ProgressView()
                        .controlSize(.mini)
                }

                if bgManager.selectedBingDate != nil {
                    Button("跟随今日") {
                        bgManager.selectBingWallpaper(date: nil)
                    }
                    .font(.system(size: 11))
                    .controlSize(.small)
                    .help("恢复每日自动跟随最新必应壁纸")
                }

                HStack(spacing: 2) {
                    Button(action: { bgManager.stepBingWallpaper(offset: -1) }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .disabled(bgManager.bingHistory.isEmpty || (bgManager.selectedBingDate == nil || bgManager.selectedBingDate == bgManager.bingHistory.first?.date))
                    .help("切换到更新一天的壁纸")

                    Button(action: { bgManager.stepBingWallpaper(offset: 1) }) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .disabled(bgManager.bingHistory.isEmpty || bgManager.selectedBingDate == bgManager.bingHistory.last?.date)
                    .help("切换到更早一天的历史壁纸")

                    Button(action: { bgManager.refreshDaily() }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .help("同步最新必应壁纸归档")
                }
            }

            if !bgManager.bingHistory.isEmpty {
                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(spacing: 10) {
                        // Auto-daily option card
                        if let latest = bgManager.bingHistory.first {
                            bingWallpaperCard(
                                item: latest,
                                badgeText: "今日自动",
                                subtitleText: "每日更新",
                                isSelected: bgManager.selectedBingDate == nil
                            ) {
                                bgManager.selectBingWallpaper(date: nil)
                            }
                        }

                        // Historical archive cards
                        ForEach(bgManager.bingHistory) { item in
                            bingWallpaperCard(
                                item: item,
                                badgeText: item.formattedShortDate,
                                subtitleText: item.title,
                                isSelected: bgManager.selectedBingDate == item.date
                            ) {
                                bgManager.selectBingWallpaper(date: item.date)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            if let copyright = bgManager.activeBingWallpaper?.copyright, !copyright.isEmpty {
                Text(copyright)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            } else {
                Text("每日壁纸已自动持久化保存在 Cloudflare (D1 + R2) 云端归档，点击任意往期缩略图即可实时预览切换。")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
    }

    private func bingWallpaperCard(
        item: BingWallpaperItem,
        badgeText: String,
        subtitleText: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack(alignment: .bottomLeading) {
                    if let thumb = bgManager.bingThumbnails[item.date] {
                        Image(nsImage: thumb)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 86, height: 52)
                            .clipped()
                    } else {
                        Color.secondary.opacity(0.15)
                            .frame(width: 86, height: 52)
                            .overlay(
                                ProgressView()
                                    .controlSize(.mini)
                            )
                    }

                    LinearGradient(
                        colors: [Color.black.opacity(0.65), Color.clear],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                    .frame(height: 22)

                    HStack(spacing: 4) {
                        Text(badgeText)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                        Spacer(minLength: 0)
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.accentColor)
                                .background(Circle().fill(Color.white).frame(width: 9, height: 9))
                                .padding(.trailing, 4)
                        }
                    }
                    .padding(.bottom, 2)
                }
                .frame(width: 86, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: isSelected ? 2 : 1)
                )

                Text(subtitleText)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .accentColor : .primary)
                    .frame(width: 86)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .help("\(item.formattedFullDate) · \(item.title)\n\(item.copyright)")
    }

    // 3. 安全防护与去噪拦截
    private var protectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "安全设置与去噪拦截", icon: "shield.lefthalf.filled")

            // Security Hub Card
            Button(action: {
                withAnimation(.easeInOut(duration: 0.18)) {
                    currentSubpage = .security
                }
            }) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "lock.shield.fill")
                        .foregroundColor(.accentColor)
                        .font(.system(size: 20))

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text("安全设置中心")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.primary)

                            Text(settings.safeBrowsingLevel.title)
                                .font(.system(size: 10, weight: .medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.12))
                                .foregroundColor(.accentColor)
                                .cornerRadius(4)

                            if settings.alwaysUseSecureConnections {
                                Text("HTTPS 优先")
                                    .font(.system(size: 10, weight: .medium))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.green.opacity(0.12))
                                    .foregroundColor(.green)
                                    .cornerRadius(4)
                            }
                        }

                        Text("安全浏览、安全连接、安全 DNS、密码泄露预警及密钥证书管理")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .padding(10)
                .background(Color.secondary.opacity(0.06))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            Toggle("启用原生广告与跟踪拦截 (基于 WebKit 原生字节码规则评估)", isOn: $settings.adBlockEnabled)
                .toggleStyle(.checkbox)
                .font(.system(size: 13))
                .onChange(of: settings.adBlockEnabled) { _ in
                    session.applyContentProtectionSettingsToAllTabs(evaluateLiveScripts: false)
                }

            Toggle("启用页面元素去噪净化 (Cosmetic Cleanup 屏蔽冗余干扰项)", isOn: $settings.cosmeticCleanupEnabled)
                .toggleStyle(.checkbox)
                .font(.system(size: 13))
                .onChange(of: settings.cosmeticCleanupEnabled) { _ in
                    session.applyContentProtectionSettingsToAllTabs(evaluateLiveScripts: true)
                }
        }
    }

    // 3.5. 扩展程序与插件中心 (Extensions & UserScripts)
    private var extensionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionHeader(title: "扩展程序与插件系统 (Chrome Manifest V3 / UserScript)", icon: "puzzlepiece.extension.fill")
                Spacer()
                Button("管理扩展程序...") {
                    isPresented = false
                    session.openExtensionManager()
                }
                .font(.system(size: 12))
            }

            HStack(spacing: 12) {
                Text("已安装 \(extensionManager.extensions.count) 个扩展 · 已启用 \(extensionManager.enabledExtensions.count) 个 · 工具栏固定 \(extensionManager.pinnedToolbarExtensions.count) 个")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                Spacer()

                Button("加载已解压扩展...") {
                    extensionManager.promptLoadUnpackedExtension()
                }
                .font(.system(size: 11.5))
                .controlSize(.small)

                Button("导入 CRX / 脚本...") {
                    extensionManager.promptInstallExtensionPackage()
                }
                .font(.system(size: 11.5))
                .controlSize(.small)
            }

            Toggle("开启扩展开发者模式 (支持直接加载本地解包目录与热重载调试)", isOn: $extensionManager.isDeveloperMode)
                .toggleStyle(.checkbox)
                .font(.system(size: 13))
        }
    }

    // 4. 标签切换体验与内存
    private var memorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(title: "标签切换与内存", icon: "leaf.fill")

            // Baseline behaviour: always resident.
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.green)
                Text("当前模式：全部标签常驻 — 切换标签不重新加载，页面状态、滚动位置与表单内容完整保留。")
                    .font(.system(size: 12))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.green.opacity(0.08))
            .cornerRadius(6)

            Toggle("自动冻结后台标签以节省内存（会牺牲切换体验）", isOn: $settings.tabHibernationEnabled)
                .toggleStyle(.checkbox)
                .font(.system(size: 13))
                .onChange(of: settings.tabHibernationEnabled) { _ in
                    session.enforceMemoryBudget()
                }

            HStack {
                Text("常驻 WebKit 渲染进程上限")
                    .font(.system(size: 13))
                    .foregroundColor(settings.tabHibernationEnabled ? .primary : .secondary)
                Spacer()
                Picker("", selection: $settings.liveWebViewBudget) {
                    ForEach(MemoryBudgetPolicy.minLiveBudget...MemoryBudgetPolicy.maxLiveBudget, id: \.self) { value in
                        Text(budgetLabel(for: value)).tag(value)
                    }
                }
                .labelsHidden()
                .disabled(!settings.tabHibernationEnabled)
                .frame(width: 260)
                .onChange(of: settings.liveWebViewBudget) { newValue in
                    let clamped = max(MemoryBudgetPolicy.minLiveBudget, min(newValue, MemoryBudgetPolicy.maxLiveBudget))
                    if clamped != newValue {
                        settings.liveWebViewBudget = clamped
                    }
                    session.enforceMemoryBudget()
                }
            }

            Text("关闭时（默认）：每个标签始终持有自己的 WebView 与渲染进程，切换即时、页面不重载；代价是每标签约 80–250MB 内存，标签越多占用越高。\n开启后：超出上限的后台标签会被冻结以释放内存，切回时需要重建页面（滚动位置尽量还原，但表单输入与页面内临时状态可能丢失）。")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle("启动时恢复上次的标签页", isOn: $settings.restoreSessionOnLaunch)
                .toggleStyle(.checkbox)
                .font(.system(size: 13))
        }
    }

    private func budgetLabel(for value: Int) -> String {
        switch value {
        case MemoryBudgetPolicy.minLiveBudget:
            return "\(value) 个 (最省内存，切换需重建)"
        case MemoryBudgetPolicy.defaultLiveBudget:
            return "\(value) 个 (平衡)"
        default:
            return "\(value) 个 (更少重建)"
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

    // 7. 关于 Zhuo浏览器
    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader(title: "关于 Zhuo浏览器", icon: "info.circle.fill")

            HStack {
                Text("Zhuo浏览器 · Mac 原生轻量浏览器")
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
