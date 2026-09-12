import SwiftUI

struct RootView: View {
    @StateObject private var session = BrowserSession()
    @State private var addressText = ""

    var body: some View {
        VStack(spacing: 0) {
            addressBar
            if session.showsFind {
                FindBar()
            }
            if session.activeTab?.isReader == true && !session.showsOverview {
                ReaderBar()
            }
            ZStack {
                pageBody
                if session.showsOverview {
                    TabOverview()
                }
                if let notice = session.notice {
                    VStack {
                        Text(notice)
                            .font(.system(size: 14))
                            .foregroundStyle(DesignTokens.textPrimary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(DesignTokens.surfacePanel, in: Capsule())
                            .shadow(color: Color.black.opacity(0.08), radius: 8, y: 2)
                            .padding(.top, 16)
                        Spacer()
                    }
                    .allowsHitTesting(false)
                    .accessibilityIdentifier("page-notice")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(pageBackground)
        .environmentObject(session)
        .onAppear {
            addressText = displayAddress(session.activeTab?.url ?? "")
        }
        .onChange(of: session.activeTabID) { _, _ in
            addressText = displayAddress(session.activeTab?.url ?? "")
        }
        .onChange(of: session.activeTab?.url) { _, newValue in
            addressText = displayAddress(newValue ?? "")
        }
    }

    private var pageBackground: Color {
        if session.activeTab?.isReader == true {
            return Color(hex: ReaderTheme.theme(for: session.readerSettings.paper).background)
        }
        return DesignTokens.pageBackground
    }

    @ViewBuilder
    private var pageBody: some View {
        if URLPolicy.isHomeURL(session.activeTab?.url ?? URLPolicy.homeURL) {
            NativeHomeView { url in
                session.openInActiveTab(url)
            }
        } else if let controller = session.activeController {
            BrowserWebView(webView: controller.webView)
        } else {
            pageBackground
        }
    }

    private var addressBar: some View {
        HStack(spacing: 6) {
            Button {
                session.goBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(canGoBack ? DesignTokens.textPrimary : DesignTokens.textSecondary)
                    .frame(width: 32, height: 36)
            }
            .disabled(!canGoBack)
            .accessibilityIdentifier("nav-back")

            TextField(session.activeTab?.isPrivate == true ? "无痕搜索或输入网址" : "搜索或输入网址", text: $addressText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .submitLabel(.go)
                .font(.system(size: 15))
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(DesignTokens.surfaceSubtle, in: Capsule())
                .accessibilityIdentifier("omni-field")
                .onSubmit {
                    session.openInActiveTab(addressText)
                }

            pageActions

            Button {
                session.reloadOrStop()
            } label: {
                Image(systemName: session.activeTab?.isLoading == true ? "xmark" : "arrow.clockwise")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DesignTokens.textPrimary)
                    .frame(width: 32, height: 36)
            }
            .accessibilityIdentifier("nav-reload")

            Button {
                session.showsOverview.toggle()
            } label: {
                Text("\(session.tabs.count)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DesignTokens.textPrimary)
                    .frame(minWidth: 32, minHeight: 36)
                    .background(DesignTokens.surfaceSubtle, in: Capsule())
            }
            .accessibilityIdentifier("tab-launcher")
            .accessibilityLabel("\(session.tabs.count) 个标签页")
            .onLongPressGesture {
                session.createTab(isPrivate: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(session.activeTab?.isPrivate == true ? DesignTokens.surfaceSubtle : DesignTokens.surfacePanel)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DesignTokens.border)
                .frame(height: 1)
        }
    }

    private var pageActions: some View {
        let browsing = !(session.activeTab.map { URLPolicy.isHomeURL($0.url) } ?? true)
        return Menu {
            Button(session.activeTab?.isReader == true ? "退出阅读模式" : "阅读模式") {
                session.toggleReader()
            }
            .disabled(!browsing)
            Button("在页面中查找") {
                session.beginFind()
            }
            .disabled(!browsing)
            Button(session.activeTab?.isDesktop == true ? "移动版网站" : "桌面版网站") {
                session.toggleDesktop()
            }
            .disabled(!browsing)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(browsing ? DesignTokens.textPrimary : DesignTokens.textSecondary)
                .frame(width: 32, height: 36)
        }
        .disabled(!browsing)
        .accessibilityIdentifier("page-actions")
    }

    private var canGoBack: Bool {
        guard let tab = session.activeTab else {
            return false
        }
        return !URLPolicy.isHomeURL(tab.url)
    }

    private func displayAddress(_ url: String) -> String {
        URLPolicy.isHomeURL(url) ? "" : url
    }
}
