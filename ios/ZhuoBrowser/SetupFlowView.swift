import SwiftUI

struct SetupFlowView: View {
    @EnvironmentObject private var session: BrowserSession

    var body: some View {
        Group {
            if !session.settings.privacyConsentAccepted {
                PrivacyConsentView(onAccept: session.acceptPrivacyConsent)
            } else {
                OnboardingView(
                    selectedEngine: session.settings.searchEngine,
                    onEngineChange: session.setSearchEngine,
                    onFinish: session.finishOnboarding
                )
            }
        }
        .interactiveDismissDisabled()
    }
}

private enum ConsentDocTab: Int, CaseIterable {
    case terms
    case privacy

    var title: String {
        switch self {
        case .terms: return "用户协议"
        case .privacy: return "隐私政策"
        }
    }

    var url: URL {
        switch self {
        case .terms: return AppInformation.termsURL
        case .privacy: return AppInformation.privacyURL
        }
    }

    var sections: [(heading: String, body: String)] {
        switch self {
        case .terms:
            return [
                ("1. 服务定位", "卓阅是一款以简洁阅读与本地浏览为主的客户端工具，网页内容及第三方服务由对应站点提供与负责。"),
                ("2. 合规与使用边界", "请勿利用本应用从事违法违规访问或传播受限内容；对于广告拦截与页面显示增强，应用仅对当前设备渲染结果生效。"),
                ("3. Pro 会员说明", "如您选购高级能力，订单与订阅均通过 Apple App Store 结算并遵循系统订阅管理规则。")
            ]
        case .privacy:
            return [
                ("1. 本地优先存储", "默认情况下，标签页、浏览历史、书签、站点权限、拦截规则与离线文章均仅保存在您的设备本地。"),
                ("2. 无痕模式", "无痕标签页不写入历史记录或本地持久化会话，并在全部无痕标签关闭时清理非持久网站数据。"),
                ("3. 权限与网络请求", "涉及相机、麦克风或定位请求时，卓阅会在系统弹窗前先向您二次确认；除必要的规则更新、搜索引擎与您主动访问的网页外，不收集个人浏览画像。")
            ]
        }
    }
}

private struct PrivacyConsentView: View {
    let onAccept: () -> Void
    @State private var selectedTab: ConsentDocTab = .privacy
    @State private var agreed = false
    @State private var showsDeclineMessage = false

    var body: some View {
        ZStack {
            DesignTokens.pageBackground
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(DesignTokens.accentStrong.opacity(0.14))
                            .frame(width: 44, height: 44)
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(DesignTokens.accentStrong)
                    }
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("开始使用卓阅")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(DesignTokens.textPrimary)
                        Text("请先阅读服务条款与本地隐私说明")
                            .font(.system(size: 13))
                            .foregroundStyle(DesignTokens.textSecondary)
                    }
                }

                Picker("协议内容", selection: $selectedTab) {
                    ForEach(ConsentDocTab.allCases, id: \.self) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(selectedTab.sections, id: \.heading) { section in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(section.heading)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(DesignTokens.textPrimary)
                                Text(section.body)
                                    .font(.system(size: 13))
                                    .foregroundStyle(DesignTokens.textSecondary)
                                    .lineSpacing(4)
                            }
                        }

                        HStack(spacing: 14) {
                            Link("查看用户协议原文", destination: AppInformation.termsURL)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(DesignTokens.accentStrong)
                                .accessibilityIdentifier("privacy-terms-link")

                            Link("查看隐私政策原文", destination: AppInformation.privacyURL)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(DesignTokens.accentStrong)
                                .accessibilityIdentifier("privacy-policy-link")
                        }
                        .padding(.top, 4)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 190, maxHeight: 280)
                .background(DesignTokens.surfaceSubtle, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                Toggle(isOn: $agreed) {
                    Text("我已阅读并同意《用户协议》与《隐私政策》")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DesignTokens.textPrimary)
                }
                .tint(DesignTokens.accentFill)
                .accessibilityIdentifier("privacy-consent-toggle")

                HStack(spacing: 10) {
                    Button {
                        showsDeclineMessage = true
                    } label: {
                        Text("暂不同意")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(DesignTokens.textPrimary)
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background(DesignTokens.surfaceSubtle, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .accessibilityIdentifier("privacy-consent-decline")

                    Button {
                        onAccept()
                    } label: {
                        Text("同意并继续")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(DesignTokens.accentForeground)
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background(
                                agreed ? DesignTokens.accentFill : DesignTokens.accentFill.opacity(0.35),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                            )
                    }
                    .disabled(!agreed)
                    .accessibilityIdentifier("privacy-consent-accept")
                }

                if showsDeclineMessage {
                    Text("不同意时不会进入浏览器。您可以关闭应用，或查看政策后再继续。")
                        .font(.footnote)
                        .foregroundStyle(DesignTokens.danger)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .accessibilityIdentifier("privacy-decline-message")
                }
            }
            .padding(22)
            .frame(maxWidth: 460)
            .background(DesignTokens.surfacePanel, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(DesignTokens.border, lineWidth: 1)
            )
            .padding(.horizontal, 20)
        }
        .accessibilityIdentifier("privacy-consent-screen")
    }
}

private struct OnboardingView: View {
    let selectedEngine: SearchEngine
    let onEngineChange: (SearchEngine) -> Void
    let onFinish: () -> Void
    @State private var page = 0

    private let stepCount = 4

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Label("卓阅", systemImage: "book.pages.fill")
                    .font(.headline)
                    .foregroundStyle(DesignTokens.textPrimary)
                Spacer()
                Button("跳过", action: onFinish)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(DesignTokens.textSecondary)
                    .accessibilityIdentifier("onboarding-skip")
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)

            TabView(selection: $page) {
                onboardingStepView(
                    tag: 0,
                    title: "顺手克制的手势交互",
                    message: "底部工具栏左右滑动切换或新建标签，上滑快速呼出页面工具，专注阅读正文。"
                ) {
                    dockGestureIllustration
                }

                onboardingStepView(
                    tag: 1,
                    title: "隐私与拦截默认收紧",
                    message: "内置广告拦截、无痕标签与权限二次确认，浏览记录和文章默认留在本地。"
                ) {
                    privacyIllustration
                }

                onboardingStepView(
                    tag: 2,
                    title: "挑选默认搜索引擎",
                    message: "随时可在设置中切换或配置自定义搜索模板。"
                ) {
                    enginePickerGrid
                }

                onboardingStepView(
                    tag: 3,
                    title: "离线文章与文档图书馆",
                    message: "一键将网页正文存为排版清晰的离线文章，支持标签整理与随时回看。"
                ) {
                    articleLibraryIllustration
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            HStack(spacing: 6) {
                ForEach(0..<stepCount, id: \.self) { index in
                    Capsule()
                        .fill(index == page ? DesignTokens.accentStrong : DesignTokens.handle)
                        .frame(width: index == page ? 18 : 6, height: 6)
                        .animation(.easeInOut(duration: 0.2), value: page)
                }
            }

            HStack(spacing: 12) {
                if page > 0 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            page -= 1
                        }
                    } label: {
                        Text("上一步")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(DesignTokens.textPrimary)
                            .frame(width: 96, height: 48)
                            .background(DesignTokens.surfaceSubtle, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .accessibilityIdentifier("onboarding-back")
                }

                Button {
                    if page == stepCount - 1 {
                        onFinish()
                    } else {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            page += 1
                        }
                    }
                } label: {
                    Text(page == stepCount - 1 ? "开始使用" : "继续")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DesignTokens.accentForeground)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(DesignTokens.accentFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .accessibilityIdentifier(page == stepCount - 1 ? "onboarding-finish" : "onboarding-next")
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(DesignTokens.pageBackground)
    }

    private func onboardingStepView<Content: View>(
        tag: Int,
        title: String,
        message: String,
        @ViewBuilder illustration: () -> Content
    ) -> some View {
        VStack(spacing: 22) {
            Spacer(minLength: 8)
            illustration()
                .frame(maxWidth: 320, minHeight: 168)
            VStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(DesignTokens.textPrimary)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.system(size: 15))
                    .foregroundStyle(DesignTokens.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            .padding(.horizontal, 12)
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: 520)
        .tag(tag)
    }

    private var dockGestureIllustration: some View {
        VStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(DesignTokens.surfacePanel)
                .frame(height: 96)
                .overlay(
                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(DesignTokens.surfaceSubtle)
                            .frame(width: 140, height: 10)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(DesignTokens.surfaceSubtle)
                            .frame(width: 210, height: 8)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(DesignTokens.surfaceSubtle)
                            .frame(width: 180, height: 8)
                    }
                    .padding(16),
                    alignment: .leading
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(DesignTokens.border, lineWidth: 1)
                )

            HStack(spacing: 8) {
                Image(systemName: "chevron.left")
                Image(systemName: "chevron.right")
                RoundedRectangle(cornerRadius: 12)
                    .fill(DesignTokens.surfaceSubtle)
                    .frame(height: 28)
                    .overlay(
                        HStack(spacing: 4) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(DesignTokens.accentStrong)
                            Text("example.com")
                                .font(.system(size: 11))
                                .foregroundStyle(DesignTokens.textSecondary)
                        }
                    )
                Text("2")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 18, height: 18)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(DesignTokens.dockIcon, lineWidth: 1.5))
                Image(systemName: "ellipsis")
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(DesignTokens.dockIcon)
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(DesignTokens.surfacePanel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(DesignTokens.border, lineWidth: 1)
            )
        }
    }

    private var privacyIllustration: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(DesignTokens.accentStrong.opacity(0.14))
                    .frame(width: 88, height: 88)
                Image(systemName: "shield.lefthook.filled")
                    .font(.system(size: 38, weight: .medium))
                    .foregroundStyle(DesignTokens.accentStrong)
            }
            VStack(alignment: .leading, spacing: 8) {
                Label("内容拦截", systemImage: "checkmark.circle.fill")
                Label("无痕不留痕", systemImage: "eye.slash.fill")
                Label("权限二次确认", systemImage: "hand.raised.fill")
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(DesignTokens.textPrimary)
        }
        .padding(20)
        .background(DesignTokens.surfacePanel, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(DesignTokens.border, lineWidth: 1)
        )
    }

    private var enginePickerGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 2)
        return LazyVGrid(columns: columns, spacing: 10) {
            ForEach(SearchEngine.allCases) { engine in
                let isSelected = engine == selectedEngine
                Button {
                    onEngineChange(engine)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(isSelected ? DesignTokens.accentStrong : DesignTokens.textSecondary)
                        Text(engine.label)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(DesignTokens.textPrimary)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 46)
                    .background(
                        isSelected ? DesignTokens.accentStrong.opacity(0.12) : DesignTokens.surfacePanel,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(isSelected ? DesignTokens.accentStrong : DesignTokens.border, lineWidth: isSelected ? 1.5 : 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding-search-engine")
    }

    private var articleLibraryIllustration: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "doc.text.fill")
                    .foregroundStyle(DesignTokens.accentStrong)
                Text("离线深度阅读")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DesignTokens.textPrimary)
                Spacer()
                Text("已离线")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DesignTokens.accentStrong)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(DesignTokens.accentStrong.opacity(0.14), in: Capsule())
            }
            RoundedRectangle(cornerRadius: 4)
                .fill(DesignTokens.surfaceSubtle)
                .frame(width: 220, height: 10)
            RoundedRectangle(cornerRadius: 4)
                .fill(DesignTokens.surfaceSubtle)
                .frame(width: 190, height: 8)
            RoundedRectangle(cornerRadius: 4)
                .fill(DesignTokens.surfaceSubtle)
                .frame(width: 160, height: 8)
        }
        .padding(18)
        .background(DesignTokens.surfacePanel, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(DesignTokens.border, lineWidth: 1)
        )
    }
}
