import AppKit
import SwiftUI

/// Circular badge rendering a profile's theme color and SF Symbol icon.
public struct ProfileAvatarBadge: View {
    public let profile: BrowserProfile
    public var size: CGFloat = 24
    public var showBorder: Bool = false

    public init(profile: BrowserProfile, size: CGFloat = 24, showBorder: Bool = false) {
        self.profile = profile
        self.size = size
        self.showBorder = showBorder
    }

    public var body: some View {
        ZStack {
            Circle()
                .fill(profile.tintColor.gradient)
                .frame(width: size, height: size)

            Image(systemName: profile.avatarSymbol)
                .font(.system(size: max(9, size * 0.48), weight: .semibold))
                .foregroundColor(.white)
        }
        .overlay {
            if showBorder {
                Circle()
                    .stroke(Color(nsColor: .windowBackgroundColor), lineWidth: max(1.5, size * 0.08))
            }
        }
    }
}

/// Chrome-style popover anchored to the toolbar's Profile button.
/// Lets users inspect the active profile, jump to or open other profile windows
/// side-by-side (for simultaneous Google account sessions), create/edit profiles,
/// and access Zhuo Cloud Sync (`AccountView`).
public struct ProfileSwitcherPopoverView: View {
    @ObservedObject var session: BrowserSession
    @ObservedObject var profileManager: ProfileManager
    @ObservedObject private var accountManager = AccountManager.shared
    @Binding var isPresented: Bool
    var onOpenProfile: (UUID) -> Void

    public init(
        session: BrowserSession,
        profileManager: ProfileManager = .shared,
        isPresented: Binding<Bool>,
        onOpenProfile: @escaping (UUID) -> Void
    ) {
        self.session = session
        self.profileManager = profileManager
        self._isPresented = isPresented
        self.onOpenProfile = onOpenProfile
    }

    private var currentProfile: BrowserProfile {
        profileManager.profile(for: session.profileID)
    }

    private var otherProfiles: [BrowserProfile] {
        profileManager.profiles.filter { $0.id != currentProfile.id }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Current Profile Hero Card
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    ProfileAvatarBadge(profile: currentProfile, size: 42)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(currentProfile.displayName)
                                .font(.system(size: 14, weight: .bold))
                                .lineLimit(1)

                            if currentProfile.isDefault {
                                Text("默认")
                                    .font(.system(size: 9.5, weight: .semibold))
                                    .foregroundColor(currentProfile.tintColor)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(currentProfile.tintColor.opacity(0.14))
                                    .cornerRadius(4)
                            }
                        }

                        Text("独立 Cookie 与登录会话")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button(action: {
                        isPresented = false
                        session.isShowingProfileEditor = true
                    }) {
                        Image(systemName: "pencil")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 26, height: 26)
                            .background(Color.secondary.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("编辑当前个人资料")
                }

                // Quick actions row
                HStack(spacing: 8) {
                    Button(action: {
                        isPresented = false
                        session.createTab(isPrivate: true)
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "lock.shield")
                                .font(.system(size: 11))
                            Text("无痕标签页")
                                .font(.system(size: 11.5, weight: .medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(7)
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        isPresented = false
                        session.isShowingAccountSheet = true
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: accountManager.isLoggedIn ? "icloud.fill" : "person.crop.circle")
                                .font(.system(size: 11))
                                .foregroundColor(accountManager.isLoggedIn ? .blue : .primary)
                            Text(accountManager.isLoggedIn ? "云端同步" : "同步账号")
                                .font(.system(size: 11.5, weight: .medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(7)
                    }
                    .buttonStyle(.plain)
                    .help(accountManager.isLoggedIn
                          ? "已登录 Zhuo 云端同步 (\(accountManager.currentUser?.displayName ?? ""))"
                          : "登录 Zhuo 云端同步书签与偏好")
                }
            }
            .padding(14)
            .background(currentProfile.tintColor.opacity(0.06))

            Divider()

            // Other Profiles Section
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("其他个人资料")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("可同时打开多个窗口")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.8))
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)

                if otherProfiles.isEmpty {
                    Text("点击下方“添加个人资料”，即可创建独立会话同时登录多个 Google 账号。")
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                } else {
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(spacing: 3) {
                            ForEach(otherProfiles) { profile in
                                OtherProfileRow(
                                    profile: profile,
                                    isWindowOpen: profileManager.openProfileIDs.contains(profile.id)
                                ) {
                                    isPresented = false
                                    onOpenProfile(profile.id)
                                }
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.bottom, 6)
                    }
                    .frame(maxHeight: 200)
                }
            }

            Divider()

            // Footer: Add Profile & Manage Profiles
            HStack(spacing: 8) {
                Button(action: {
                    isPresented = false
                    session.isShowingCreateProfile = true
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 13))
                        Text("添加个人资料")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.accentColor)
                    .padding(.vertical, 5)
                    .padding(.horizontal, 8)
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: {
                    isPresented = false
                    session.isShowingProfileManager = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 11))
                        Text("管理")
                            .font(.system(size: 12))
                    }
                    .foregroundColor(.secondary)
                    .padding(.vertical, 5)
                    .padding(.horizontal, 8)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
        .frame(width: 300)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct OtherProfileRow: View {
    let profile: BrowserProfile
    let isWindowOpen: Bool
    let action: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ProfileAvatarBadge(profile: profile, size: 26)

                Text(profile.displayName)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Spacer()

                if isWindowOpen {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        Text("已打开")
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary)
                    }
                } else {
                    Image(systemName: "arrow.up.forward.square")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(isHovered ? 0.9 : 0.45))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isHovered ? Color.secondary.opacity(0.12) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

/// Sheet for creating a new profile or editing an existing profile's name, color, and icon.
public struct ProfileEditorSheetView: View {
    public enum Mode: Equatable {
        case create
        case edit(BrowserProfile)
    }

    @ObservedObject var profileManager: ProfileManager
    let mode: Mode
    @Binding var isPresented: Bool
    var onCreatedAndOpen: ((UUID) -> Void)?

    @State private var nameInput: String = ""
    @State private var selectedColorHex: String = ProfilePalette.defaultColorHex
    @State private var selectedSymbol: String = ProfilePalette.defaultSymbol

    public init(
        profileManager: ProfileManager = .shared,
        mode: Mode,
        isPresented: Binding<Bool>,
        onCreatedAndOpen: ((UUID) -> Void)? = nil
    ) {
        self.profileManager = profileManager
        self.mode = mode
        self._isPresented = isPresented
        self.onCreatedAndOpen = onCreatedAndOpen
    }

    private var isCreateMode: Bool {
        if case .create = mode { return true }
        return false
    }

    private var previewProfile: BrowserProfile {
        BrowserProfile(
            name: nameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? (isCreateMode ? profileManager.suggestedNextProfileName() : "个人资料")
                : nameInput,
            avatarSymbol: selectedSymbol,
            colorHex: selectedColorHex
        )
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(isCreateMode ? "添加个人资料" : "自定义个人资料")
                    .font(.system(size: 15, weight: .bold))
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

            Divider()

            VStack(alignment: .leading, spacing: 18) {
                // Live Avatar + Name Preview
                HStack(spacing: 14) {
                    ProfileAvatarBadge(profile: previewProfile, size: 52)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("个人资料名称")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundColor(.secondary)
                        TextField("例如：工作、Google 账号 2", text: $nameInput)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit {
                                submit()
                            }
                    }
                }

                // Theme Color Picker
                VStack(alignment: .leading, spacing: 8) {
                    Text("主题标识色")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(.secondary)

                    HStack(spacing: 10) {
                        ForEach(ProfilePalette.colorOptions, id: \.hex) { option in
                            let isSelected = selectedColorHex.caseInsensitiveCompare(option.hex) == .orderedSame
                            Button(action: { selectedColorHex = option.hex }) {
                                ZStack {
                                    Circle()
                                        .fill(ProfilePalette.color(fromHex: option.hex))
                                        .frame(width: 26, height: 26)
                                    if isSelected {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundColor(.white)
                                    }
                                }
                                .overlay(
                                    Circle()
                                        .stroke(isSelected ? Color.primary.opacity(0.6) : Color.clear, lineWidth: 2)
                                        .padding(-2)
                                )
                            }
                            .buttonStyle(.plain)
                            .help(option.name)
                        }
                    }
                }

                // Icon Picker
                VStack(alignment: .leading, spacing: 8) {
                    Text("头像图标")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(.secondary)

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                        ForEach(ProfilePalette.symbolOptions, id: \.symbol) { option in
                            let isSelected = selectedSymbol == option.symbol
                            Button(action: { selectedSymbol = option.symbol }) {
                                VStack(spacing: 3) {
                                    Image(systemName: option.symbol)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(isSelected ? .white : .primary)
                                        .frame(width: 36, height: 32)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(isSelected
                                                      ? ProfilePalette.color(fromHex: selectedColorHex)
                                                      : Color.secondary.opacity(0.1))
                                        )
                                }
                            }
                            .buttonStyle(.plain)
                            .help(option.name)
                        }
                    }
                }

                if isCreateMode {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "shield.lefthalf.filled")
                            .font(.system(size: 13))
                            .foregroundColor(.accentColor)
                            .padding(.top, 1)
                        Text("每个个人资料拥有完全独立的 Cookie、LocalStorage 与登录会话，可同时打开多个窗口分别登录不同 Google 账号，互不干扰。")
                            .font(.system(size: 11.5))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(10)
                    .background(Color.accentColor.opacity(0.08))
                    .cornerRadius(8)
                }
            }
            .padding(20)

            Divider()

            HStack {
                Button("取消") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(isCreateMode ? "创建并打开窗口" : "保存更改") {
                    submit()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 400)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            switch mode {
            case .create:
                nameInput = profileManager.suggestedNextProfileName()
                let count = profileManager.profiles.count
                selectedColorHex = ProfilePalette.nextSuggestedColorHex(existingCount: count)
                selectedSymbol = ProfilePalette.nextSuggestedSymbol(existingCount: count)
            case .edit(let profile):
                nameInput = profile.displayName
                selectedColorHex = profile.colorHex
                selectedSymbol = profile.avatarSymbol
            }
        }
    }

    private func submit() {
        switch mode {
        case .create:
            let created = profileManager.createProfile(
                name: nameInput,
                avatarSymbol: selectedSymbol,
                colorHex: selectedColorHex
            )
            isPresented = false
            onCreatedAndOpen?(created.id)
        case .edit(let existing):
            profileManager.updateProfile(
                id: existing.id,
                name: nameInput,
                avatarSymbol: selectedSymbol,
                colorHex: selectedColorHex
            )
            isPresented = false
        }
    }
}

/// Management sheet listing all profiles with options to open, create, customize, or delete.
public struct ProfileManagerSheetView: View {
    @ObservedObject var session: BrowserSession
    @ObservedObject var profileManager: ProfileManager
    @Binding var isPresented: Bool
    var onOpenProfile: (UUID) -> Void

    @State private var editingTarget: BrowserProfile? = nil
    @State private var isShowingCreate: Bool = false
    @State private var pendingDeleteProfile: BrowserProfile? = nil

    public init(
        session: BrowserSession,
        profileManager: ProfileManager = .shared,
        isPresented: Binding<Bool>,
        onOpenProfile: @escaping (UUID) -> Void
    ) {
        self.session = session
        self.profileManager = profileManager
        self._isPresented = isPresented
        self.onOpenProfile = onOpenProfile
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "person.2.circle.fill")
                        .font(.system(size: 17))
                        .foregroundColor(.accentColor)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("管理个人资料")
                            .font(.system(size: 15, weight: .bold))
                        Text("每个个人资料拥有独立的 Cookie、网页存储与 Google 登录态")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
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

            Divider()

            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 10) {
                    ForEach(profileManager.profiles) { profile in
                        profileRowCard(profile)
                    }
                }
                .padding(20)
            }
            .frame(height: 360)

            Divider()

            HStack {
                Button(action: { isShowingCreate = true }) {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                        Text("添加个人资料")
                    }
                }
                .buttonStyle(.borderedProminent)

                Spacer()

                Button("完成") {
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 520)
        .background(Color(nsColor: .controlBackgroundColor))
        .sheet(isPresented: $isShowingCreate) {
            ProfileEditorSheetView(
                profileManager: profileManager,
                mode: .create,
                isPresented: $isShowingCreate
            ) { newProfileID in
                isPresented = false
                onOpenProfile(newProfileID)
            }
        }
        .sheet(item: $editingTarget) { profile in
            ProfileEditorSheetView(
                profileManager: profileManager,
                mode: .edit(profile),
                isPresented: Binding(
                    get: { editingTarget != nil },
                    set: { if !$0 { editingTarget = nil } }
                )
            )
        }
        .alert(
            "确定删除个人资料“\(pendingDeleteProfile?.displayName ?? "")”？",
            isPresented: Binding(
                get: { pendingDeleteProfile != nil },
                set: { if !$0 { pendingDeleteProfile = nil } }
            )
        ) {
            Button("删除资料与数据", role: .destructive) {
                if let target = pendingDeleteProfile {
                    profileManager.deleteProfile(id: target.id)
                    pendingDeleteProfile = nil
                }
            }
            Button("取消", role: .cancel) {
                pendingDeleteProfile = nil
            }
        } message: {
            Text("该个人资料下的独立 Cookie、Google 登录状态、历史记录与书签将被永久清除，无法恢复；其他个人资料不受影响。")
        }
    }

    private func profileRowCard(_ profile: BrowserProfile) -> some View {
        let isCurrent = profile.id == session.profileID
        let isOpen = profileManager.openProfileIDs.contains(profile.id)
        let tabCount = profileManager.loadedSession(for: profile.id)?.tabs.count

        return HStack(spacing: 12) {
            ProfileAvatarBadge(profile: profile, size: 38)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(profile.displayName)
                        .font(.system(size: 13.5, weight: .semibold))

                    if profile.isDefault {
                        badge("默认", color: .secondary)
                    }
                    if isCurrent {
                        badge("当前窗口", color: profile.tintColor)
                    } else if isOpen {
                        badge("已打开", color: .green)
                    }
                }

                Text(tabCount.map { "已打开 \($0) 个标签页 · 独立数据容器" } ?? "独立 WebKit 数据容器")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            HStack(spacing: 6) {
                if !isCurrent {
                    Button(isOpen ? "切换到窗口" : "打开窗口") {
                        isPresented = false
                        onOpenProfile(profile.id)
                    }
                    .controlSize(.small)
                }

                Button("编辑") {
                    editingTarget = profile
                }
                .controlSize(.small)

                if !profile.isDefault {
                    Button(role: .destructive) {
                        pendingDeleteProfile = profile
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 11.5))
                    }
                    .controlSize(.small)
                    .help("删除此个人资料")
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isCurrent ? profile.tintColor.opacity(0.45) : Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }

    private func badge(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 1.5)
            .background(color.opacity(0.13))
            .cornerRadius(4)
    }
}
