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

private struct PrivacyConsentView: View {
    let onAccept: () -> Void
    @State private var agreed = false
    @State private var showsDeclineMessage = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Image(systemName: "checkmark.shield")
                        .font(.system(size: 38, weight: .medium))
                        .foregroundStyle(DesignTokens.accent)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("开始使用卓阅")
                            .font(.system(size: 28, weight: .bold))
                        Text("请先了解服务与隐私边界。卓阅默认将标签页、历史、书签和站点权限保存在本机。")
                            .foregroundStyle(DesignTokens.textSecondary)
                    }

                    legalRow(
                        title: "用户协议",
                        summary: "浏览服务、内容责任和付费能力边界",
                        url: AppInformation.termsURL
                    )
                    legalRow(
                        title: "隐私政策",
                        summary: "本地数据、无痕浏览、权限与数据删除",
                        url: AppInformation.privacyURL
                    )

                    Toggle(isOn: $agreed) {
                        Text("我已阅读并同意用户协议与隐私政策")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .tint(DesignTokens.accent)
                    .accessibilityIdentifier("privacy-consent-toggle")

                    Button("同意并继续", action: onAccept)
                        .buttonStyle(.borderedProminent)
                        .tint(DesignTokens.accent)
                        .frame(maxWidth: .infinity)
                        .controlSize(.large)
                        .disabled(!agreed)
                        .accessibilityIdentifier("privacy-consent-accept")

                    Button("不同意并停止使用", role: .destructive) {
                        showsDeclineMessage = true
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("privacy-consent-decline")

                    if showsDeclineMessage {
                        Text("不同意时不会进入浏览器。你可以关闭应用，或阅读政策后再决定。")
                            .font(.footnote)
                            .foregroundStyle(DesignTokens.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .accessibilityIdentifier("privacy-decline-message")
                    }
                }
                .padding(28)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .background(DesignTokens.pageBackground)
        }
        .accessibilityIdentifier("privacy-consent-screen")
    }

    private func legalRow(title: String, summary: String, url: URL) -> some View {
        Link(destination: url) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(DesignTokens.textPrimary)
                    Text(summary)
                        .font(.system(size: 13))
                        .foregroundStyle(DesignTokens.textSecondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .foregroundStyle(DesignTokens.accent)
            }
            .padding(16)
            .background(DesignTokens.surfacePanel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .accessibilityIdentifier(title == "用户协议" ? "privacy-terms-link" : "privacy-policy-link")
    }
}

private struct OnboardingView: View {
    let selectedEngine: SearchEngine
    let onEngineChange: (SearchEngine) -> Void
    let onFinish: () -> Void
    @State private var page = 0

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Label("卓阅", systemImage: "book.pages")
                    .font(.headline)
                Spacer()
                Button("跳过", action: onFinish)
                    .foregroundStyle(DesignTokens.textSecondary)
                    .accessibilityIdentifier("onboarding-skip")
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)

            TabView(selection: $page) {
                onboardingPage(
                    index: 0,
                    icon: "hand.tap",
                    title: "少打扰，多阅读",
                    message: "地址栏集中浏览操作，长按标签数可快速打开无痕标签页。"
                )
                onboardingPage(
                    index: 1,
                    icon: "shield.lefthalf.filled",
                    title: "隐私默认收紧",
                    message: "无痕标签不写入历史或恢复会话；站点权限先由卓阅确认，再交给系统。"
                )
                VStack(spacing: 24) {
                    onboardingCopy(
                        icon: "text.magnifyingglass",
                        title: "选择搜索引擎",
                        message: "以后可随时在设置中修改。"
                    )
                    Picker("搜索引擎", selection: Binding(
                        get: { selectedEngine },
                        set: onEngineChange
                    )) {
                        ForEach(SearchEngine.allCases) { engine in
                            Text(engine.label).tag(engine)
                        }
                    }
                    .pickerStyle(.inline)
                    .accessibilityIdentifier("onboarding-search-engine")
                }
                .padding(28)
                .tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            HStack(spacing: 12) {
                if page > 0 {
                    Button("上一步") { page -= 1 }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .accessibilityIdentifier("onboarding-back")
                }
                Button(page == 2 ? "开始使用" : "继续") {
                    if page == 2 { onFinish() } else { page += 1 }
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignTokens.accent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier(page == 2 ? "onboarding-finish" : "onboarding-next")
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(DesignTokens.pageBackground)
    }

    private func onboardingPage(index: Int, icon: String, title: String, message: String) -> some View {
        onboardingCopy(icon: icon, title: title, message: message)
            .padding(28)
            .tag(index)
    }

    private func onboardingCopy(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 18) {
            Image(systemName: icon)
                .font(.system(size: 54, weight: .light))
                .foregroundStyle(DesignTokens.accent)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 28, weight: .bold))
                .multilineTextAlignment(.center)
            Text(message)
                .font(.system(size: 16))
                .foregroundStyle(DesignTokens.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(5)
        }
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
