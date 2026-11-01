import AppKit
import SwiftUI

/// Full Chrome-style Extensions Manager (`chrome://extensions` / `zhuo://extensions`),
/// supporting Developer Mode, unpacked extension loading, CRX/ZIP/UserScript installation,
/// custom script creation, permission inspection, and storage debugging.
public struct ExtensionManagerView: View {
    @ObservedObject var session: BrowserSession
    @ObservedObject var extensionManager: ExtensionManager
    @Binding var isPresented: Bool

    public enum FilterCategory: String, CaseIterable, Identifiable {
        case all = "全部扩展"
        case enabled = "已启用"
        case builtIn = "内置精选"
        case custom = "第三方与脚本"

        public var id: String { rawValue }
    }

    @State private var searchQuery: String = ""
    @State private var selectedCategory: FilterCategory = .all

    public init(
        session: BrowserSession,
        extensionManager: ExtensionManager = .shared,
        isPresented: Binding<Bool>
    ) {
        self.session = session
        self.extensionManager = extensionManager
        self._isPresented = isPresented
    }

    private var filteredExtensions: [InstalledExtension] {
        extensionManager.extensions.filter { ext in
            switch selectedCategory {
            case .all:
                break
            case .enabled:
                if !ext.isEnabled { return false }
            case .builtIn:
                if ext.sourceKind != .builtIn { return false }
            case .custom:
                if ext.sourceKind == .builtIn { return false }
            }

            let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !trimmed.isEmpty else { return true }
            return ext.manifest.name.lowercased().contains(trimmed)
                || (ext.manifest.description?.lowercased().contains(trimmed) ?? false)
                || ext.id.lowercased().contains(trimmed)
        }
    }

    private var inspectingBinding: Binding<InstalledExtension?> {
        Binding(
            get: {
                guard let id = extensionManager.inspectingExtensionID else { return nil }
                return extensionManager.extensionItem(forID: id)
            },
            set: { newValue in
                extensionManager.inspectingExtensionID = newValue?.id
            }
        )
    }

    public var body: some View {
        VStack(spacing: 0) {
            // 1. Top Header Bar
            headerBar

            Divider()

            // 2. Developer Mode Action Bar + Filter/Search Bar
            toolbarAndFilterBar

            if let banner = extensionManager.lastOperationBanner {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 12))
                    Text(banner)
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(Color.green.opacity(0.1))
                .transition(.opacity)
            }

            Divider()

            // 3. Extension Cards Grid / List
            ScrollView(.vertical, showsIndicators: true) {
                if filteredExtensions.isEmpty {
                    emptyStateView
                } else {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(minimum: 340), spacing: 14),
                            GridItem(.flexible(minimum: 340), spacing: 14)
                        ],
                        spacing: 14
                    ) {
                        ForEach(filteredExtensions) { ext in
                            extensionCard(ext)
                        }
                    }
                    .padding(20)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // 4. Footer
            HStack {
                Text("支持 Chrome Manifest V3 / V2 扩展目录、.crx / .zip 扩展包及 Tampermonkey .user.js 脚本")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Spacer()

                Button("完成") {
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 780, idealWidth: 820, minHeight: 560, idealHeight: 600)
        .sheet(item: inspectingBinding) { ext in
            ExtensionDetailSheet(
                session: session,
                extensionManager: extensionManager,
                extensionItem: ext
            )
        }
        .sheet(isPresented: $extensionManager.isShowingCreatorSheet) {
            ExtensionCreatorSheet(
                extensionManager: extensionManager,
                isPresented: $extensionManager.isShowingCreatorSheet
            )
        }
    }

    // MARK: - Header & Toolbar Sections

    private var headerBar: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: "puzzlepiece.extension.fill")
                    .foregroundColor(.accentColor)
                    .font(.system(size: 15, weight: .semibold))
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("扩展程序与插件中心")
                        .font(.system(size: 15, weight: .bold))
                    Text("zhuo://extensions")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12))
                        .cornerRadius(4)
                }
                Text("已安装 \(extensionManager.extensions.count) 个扩展 · \(extensionManager.enabledExtensions.count) 个正在运行 · \(extensionManager.pinnedToolbarExtensions.count) 个已固定至工具栏")
                    .font(.system(size: 11.5))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Chrome-style Developer Mode Toggle
            HStack(spacing: 6) {
                Text("开发者模式")
                    .font(.system(size: 12, weight: .medium))
                Toggle("", isOn: $extensionManager.isDeveloperMode)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(extensionManager.isDeveloperMode ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08))
            )

            Button(action: { isPresented = false }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var toolbarAndFilterBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                // Category Filter Pills
                HStack(spacing: 4) {
                    ForEach(FilterCategory.allCases) { category in
                        Button(action: { selectedCategory = category }) {
                            Text(category.rawValue)
                                .font(.system(size: 11.5, weight: selectedCategory == category ? .semibold : .regular))
                                .foregroundColor(selectedCategory == category ? .white : .primary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(selectedCategory == category ? Color.accentColor : Color.secondary.opacity(0.1))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer()

                // Search Input
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    TextField("搜索扩展名称、ID 或功能...", text: $searchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                    if !searchQuery.isEmpty {
                        Button(action: { searchQuery = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .frame(width: 240)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(7)
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
            }

            // Action Buttons Row (Always shows quick install + expanded developer tools in Developer Mode)
            HStack(spacing: 8) {
                Button(action: {
                    extensionManager.promptLoadUnpackedExtension()
                }) {
                    Label("加载已解压的扩展程序...", systemImage: "folder.badge.plus")
                        .font(.system(size: 11.5, weight: .medium))
                }
                .controlSize(.small)

                Button(action: {
                    extensionManager.promptInstallExtensionPackage()
                }) {
                    Label("安装 CRX / ZIP / .user.js...", systemImage: "square.and.arrow.down")
                        .font(.system(size: 11.5, weight: .medium))
                }
                .controlSize(.small)

                Button(action: {
                    extensionManager.isShowingCreatorSheet = true
                }) {
                    Label("新建自定义脚本 / 扩展...", systemImage: "sparkles.rectangle.stack")
                        .font(.system(size: 11.5, weight: .medium))
                }
                .controlSize(.small)

                Spacer()

                if extensionManager.isDeveloperMode {
                    Button(action: {
                        extensionManager.reloadAllExtensions()
                    }) {
                        Label("重新加载全部", systemImage: "arrow.clockwise")
                            .font(.system(size: 11.5))
                    }
                    .controlSize(.small)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Extension Card

    @ViewBuilder
    private func extensionCard(_ ext: InstalledExtension) -> some View {
        let accent = ExtensionColorHelper.color(fromHex: ext.accentColorHex) ?? Color.accentColor

        VStack(alignment: .leading, spacing: 10) {
            // Top Row: Icon + Name + Version + Switch
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(accent.opacity(ext.isEnabled ? 0.16 : 0.08))
                        .frame(width: 40, height: 40)

                    if let customIcon = extensionManager.icon(for: ext) {
                        Image(nsImage: customIcon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 26, height: 26)
                    } else {
                        Image(systemName: ext.sfSymbolFallback)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(ext.isEnabled ? accent : .secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(ext.manifest.name)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(ext.isEnabled ? .primary : .secondary)
                            .lineLimit(1)

                        Text("v\(ext.manifest.version)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.12))
                            .cornerRadius(4)

                        Text("MV\(ext.manifest.manifestVersion)")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundColor(accent)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(accent.opacity(0.12))
                            .cornerRadius(4)
                    }

                    HStack(spacing: 6) {
                        Text(ext.sourceKind.displayName)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundColor(.secondary)

                        Text("·")
                            .foregroundColor(.secondary)

                        Text(ext.hostAccessMode.shortLabel)
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { ext.isEnabled },
                    set: { extensionManager.setExtensionEnabled(id: ext.id, enabled: $0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
            }

            // Description
            Text(ext.manifest.description ?? "暂无描述")
                .font(.system(size: 11.5))
                .foregroundColor(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .topLeading)

            // Developer Mode Metadata
            if extensionManager.isDeveloperMode {
                HStack(spacing: 6) {
                    Text("ID: \(ext.id)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(ext.id, forType: .string)
                    }) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 9.5))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("拷贝扩展 ID")

                    Spacer()

                    if !ext.manifest.contentScripts.isEmpty {
                        Text("注入脚本: \(ext.manifest.contentScripts.count) 组")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.06))
                .cornerRadius(5)
            }

            if let loadError = ext.lastLoadError {
                Text("⚠️ \(loadError)")
                    .font(.system(size: 10.5))
                    .foregroundColor(.red)
            }

            Divider()

            // Card Bottom Action Bar
            HStack(spacing: 8) {
                Button("详情与权限") {
                    extensionManager.inspectingExtensionID = ext.id
                }
                .font(.system(size: 11, weight: .medium))
                .controlSize(.small)

                if ext.manifest.optionsPage != nil {
                    Button("选项") {
                        extensionManager.openOptionsPage(forExtensionID: ext.id, in: session)
                    }
                    .font(.system(size: 11))
                    .controlSize(.small)
                }

                Button(action: {
                    extensionManager.togglePinToToolbar(id: ext.id)
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: ext.isPinnedToToolbar ? "pin.fill" : "pin")
                            .font(.system(size: 10))
                        Text(ext.isPinnedToToolbar ? "已固定" : "固定到工具栏")
                            .font(.system(size: 11))
                    }
                }
                .controlSize(.small)

                Spacer()

                Button(action: {
                    _ = extensionManager.reloadExtension(id: ext.id)
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .help("重新加载此扩展")

                if extensionManager.isDeveloperMode {
                    Button(action: {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: ext.directoryPath)
                    }) {
                        Image(systemName: "folder")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .help("在 Finder 中查看扩展目录")
                }

                if ext.sourceKind != .builtIn {
                    Button(role: .destructive, action: {
                        extensionManager.uninstallExtension(id: ext.id)
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundColor(.red.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                    .help("卸载此扩展")
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(ext.isEnabled ? accent.opacity(0.3) : Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "puzzlepiece.extension")
                .font(.system(size: 36))
                .foregroundColor(.secondary.opacity(0.5))
            Text("没有找到匹配的扩展程序")
                .font(.system(size: 14, weight: .semibold))
            Text("您可以点击上方按钮加载已解压的 Chrome 扩展目录、导入 .crx/.zip/.user.js，或直接新建自定义脚本。")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
    }
}

// MARK: - Extension Detail & Permissions Inspector Sheet

public struct ExtensionDetailSheet: View {
    @ObservedObject var session: BrowserSession
    @ObservedObject var extensionManager: ExtensionManager
    let extensionItem: InstalledExtension

    @Environment(\.dismiss) private var dismiss
    @State private var newAllowedHost: String = ""
    @State private var storagePreviewJSON: String = "{}"

    private var liveItem: InstalledExtension {
        extensionManager.extensionItem(forID: extensionItem.id) ?? extensionItem
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: liveItem.sfSymbolFallback)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(ExtensionColorHelper.color(fromHex: liveItem.accentColorHex) ?? .accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(liveItem.manifest.name) · 权限与详情")
                        .font(.system(size: 14, weight: .bold))
                    Text("ID: \(liveItem.id) · 版本 \(liveItem.manifest.version) · Manifest V\(liveItem.manifest.manifestVersion)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("关闭") { dismiss() }
            }
            .padding(16)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 16) {
                    // 1. Permissions Summary
                    VStack(alignment: .leading, spacing: 6) {
                        Text("已声明的权限范围")
                            .font(.system(size: 12.5, weight: .bold))
                        ForEach(liveItem.manifest.humanReadablePermissions, id: \.self) { perm in
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.shield.fill")
                                    .foregroundColor(.accentColor)
                                    .font(.system(size: 11))
                                Text(perm)
                                    .font(.system(size: 12))
                            }
                        }
                    }

                    Divider()

                    // 2. Site Access Policy
                    VStack(alignment: .leading, spacing: 8) {
                        Text("网站访问控制 (Host Access)")
                            .font(.system(size: 12.5, weight: .bold))

                        Picker("访问模式", selection: Binding(
                            get: { liveItem.hostAccessMode },
                            set: { extensionManager.setHostAccessMode(id: liveItem.id, mode: $0) }
                        )) {
                            ForEach(ExtensionHostAccessMode.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.radioGroup)
                        .font(.system(size: 12))

                        if liveItem.hostAccessMode == .onSpecificSites {
                            HStack(spacing: 8) {
                                TextField("添加允许的域名，例如 github.com", text: $newAllowedHost)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 12))
                                Button("添加域名") {
                                    extensionManager.addAllowedHost(id: liveItem.id, host: newAllowedHost)
                                    newAllowedHost = ""
                                }
                                .disabled(newAllowedHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }

                            if !liveItem.customAllowedHosts.isEmpty {
                                HStack(spacing: 6) {
                                    ForEach(liveItem.customAllowedHosts, id: \.self) { host in
                                        HStack(spacing: 4) {
                                            Text(host)
                                                .font(.system(size: 11))
                                            Button(action: {
                                                extensionManager.removeAllowedHost(id: liveItem.id, host: host)
                                            }) {
                                                Image(systemName: "xmark.circle.fill")
                                                    .font(.system(size: 10))
                                            }
                                            .buttonStyle(.plain)
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Color.accentColor.opacity(0.14))
                                        .cornerRadius(5)
                                    }
                                }
                            }
                        }

                        Toggle("允许在无痕浏览模式下运行", isOn: Binding(
                            get: { liveItem.allowInPrivateBrowsing },
                            set: { extensionManager.setAllowInPrivateBrowsing(id: liveItem.id, allowed: $0) }
                        ))
                        .toggleStyle(.checkbox)
                        .font(.system(size: 12))
                        .padding(.top, 4)
                    }

                    Divider()

                    // 3. Content Scripts & Match Patterns
                    if !liveItem.manifest.contentScripts.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("内容脚本注入规则 (Content Scripts)")
                                .font(.system(size: 12.5, weight: .bold))
                            ForEach(Array(liveItem.manifest.contentScripts.enumerated()), id: \.offset) { idx, spec in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("规则 #\(idx + 1) · 注入时机: \(spec.runAt.rawValue) · 匹配: \(spec.matches.joined(separator: ", "))")
                                        .font(.system(size: 11, weight: .medium))
                                    if !spec.js.isEmpty {
                                        Text("JS: \(spec.js.joined(separator: ", "))")
                                            .font(.system(size: 10.5, design: .monospaced))
                                            .foregroundColor(.secondary)
                                    }
                                    if !spec.css.isEmpty {
                                        Text("CSS: \(spec.css.joined(separator: ", "))")
                                            .font(.system(size: 10.5, design: .monospaced))
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.secondary.opacity(0.07))
                                .cornerRadius(6)
                            }
                        }

                        Divider()
                    }

                    // 4. Storage Inspector (`chrome.storage.local`)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("本地存储数据调试 (chrome.storage.local)")
                                .font(.system(size: 12.5, weight: .bold))
                            Spacer()
                            Button("清空存储数据") {
                                extensionManager.clearStorage(forExtensionID: liveItem.id, area: "local")
                                refreshStoragePreview()
                            }
                            .controlSize(.small)
                        }

                        Text(storagePreviewJSON)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(nsColor: .textBackgroundColor))
                            .cornerRadius(6)
                    }
                }
                .padding(18)
            }
        }
        .frame(width: 540, height: 480)
        .onAppear {
            refreshStoragePreview()
        }
    }

    private func refreshStoragePreview() {
        let store = extensionManager.storageSnapshot(forExtensionID: liveItem.id, area: "local")
        if let data = try? JSONSerialization.data(withJSONObject: store, options: [.prettyPrinted, .sortedKeys]),
           let str = String(data: data, encoding: .utf8) {
            storagePreviewJSON = str
        } else {
            storagePreviewJSON = "{}"
        }
    }
}

// MARK: - Custom Extension / UserScript Creator Sheet

public struct ExtensionCreatorSheet: View {
    @ObservedObject var extensionManager: ExtensionManager
    @Binding var isPresented: Bool

    @State private var name: String = ""
    @State private var version: String = "1.0.0"
    @State private var descriptionText: String = ""
    @State private var matchPatternText: String = "<all_urls>"
    @State private var runAt: ExtensionRunAt = .documentEnd
    @State private var jsCode: String = """
    // 在此编写注入页面的 JavaScript (支持 chrome.* 与 GM_* API)
    console.log("[Custom Extension] Running on:", location.href);
    """
    @State private var cssCode: String = """
    /* 在此编写注入页面的自定义 CSS 样式 */
    """
    @State private var errorMessage: String? = nil

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles.rectangle.stack.fill")
                        .foregroundColor(.accentColor)
                    Text("新建自定义 Chrome 扩展 / 用户脚本")
                        .font(.system(size: 14, weight: .bold))
                }
                Spacer()
                Button("取消") { isPresented = false }
            }
            .padding(16)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("扩展名称 *")
                                .font(.system(size: 11.5, weight: .semibold))
                            TextField("例如：GitHub 宽屏阅读增强", text: $name)
                                .textFieldStyle(.roundedBorder)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("版本号")
                                .font(.system(size: 11.5, weight: .semibold))
                            TextField("1.0.0", text: $version)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 90)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("功能描述")
                            .font(.system(size: 11.5, weight: .semibold))
                        TextField("简要说明此扩展或脚本的作用...", text: $descriptionText)
                            .textFieldStyle(.roundedBorder)
                    }

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("生效网址匹配规则 (Chrome Match Pattern，多个用逗号分隔)")
                                .font(.system(size: 11.5, weight: .semibold))
                            TextField("<all_urls>, *://*.github.com/*", text: $matchPatternText)
                                .textFieldStyle(.roundedBorder)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("注入时机 (run_at)")
                                .font(.system(size: 11.5, weight: .semibold))
                            Picker("", selection: $runAt) {
                                Text("document_start").tag(ExtensionRunAt.documentStart)
                                Text("document_end").tag(ExtensionRunAt.documentEnd)
                                Text("document_idle").tag(ExtensionRunAt.documentIdle)
                            }
                            .labelsHidden()
                            .frame(width: 150)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Content Script (JavaScript)")
                            .font(.system(size: 11.5, weight: .semibold))
                        TextEditor(text: $jsCode)
                            .font(.system(size: 11.5, design: .monospaced))
                            .frame(height: 130)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                            )
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Content Stylesheet (CSS)")
                            .font(.system(size: 11.5, weight: .semibold))
                        TextEditor(text: $cssCode)
                            .font(.system(size: 11.5, design: .monospaced))
                            .frame(height: 90)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                            )
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 11.5))
                            .foregroundColor(.red)
                    }
                }
                .padding(18)
            }

            Divider()

            HStack {
                Spacer()
                Button("取消") {
                    isPresented = false
                }
                Button("创建并启用扩展") {
                    createExtension()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(14)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 560, height: 530)
    }

    private func createExtension() {
        let patterns = matchPatternText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        do {
            _ = try extensionManager.createCustomExtension(
                name: name,
                version: version,
                description: descriptionText,
                matches: patterns.isEmpty ? ["<all_urls>"] : patterns,
                runAt: runAt,
                jsCode: jsCode,
                cssCode: cssCode
            )
            isPresented = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
