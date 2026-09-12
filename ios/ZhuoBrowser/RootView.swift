import SwiftUI

struct RootView: View {
    @StateObject private var session = BrowserSession()
    @State private var addressText = ""

    var body: some View {
        VStack(spacing: 0) {
            addressBar
            ZStack {
                pageBody
                if session.showsOverview {
                    TabOverview()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(DesignTokens.pageBackground)
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

    @ViewBuilder
    private var pageBody: some View {
        if URLPolicy.isHomeURL(session.activeTab?.url ?? URLPolicy.homeURL) {
            NativeHomeView { url in
                session.openInActiveTab(url)
            }
        } else if let controller = session.activeController {
            BrowserWebView(webView: controller.webView)
        } else {
            DesignTokens.pageBackground
        }
    }

    private var addressBar: some View {
        HStack(spacing: 8) {
            Button {
                session.goBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(canGoBack ? DesignTokens.textPrimary : DesignTokens.textSecondary)
                    .frame(width: 36, height: 36)
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

            Button {
                session.reloadOrStop()
            } label: {
                Image(systemName: session.activeTab?.isLoading == true ? "xmark" : "arrow.clockwise")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DesignTokens.textPrimary)
                    .frame(width: 36, height: 36)
            }
            .accessibilityIdentifier("nav-reload")

            Button {
                session.showsOverview.toggle()
            } label: {
                Text("\(session.tabs.count)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DesignTokens.textPrimary)
                    .frame(minWidth: 36, minHeight: 36)
                    .background(DesignTokens.surfaceSubtle, in: Capsule())
            }
            .accessibilityIdentifier("tab-launcher")
            .accessibilityLabel("\(session.tabs.count) 个标签页")
            .onLongPressGesture {
                session.createTab(isPrivate: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(session.activeTab?.isPrivate == true ? DesignTokens.surfaceSubtle : DesignTokens.surfacePanel)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DesignTokens.border)
                .frame(height: 1)
        }
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
