import SwiftUI

struct RootView: View {
    @StateObject private var kernel = BrowserWebViewController()
    @State private var addressText = WebKernel.homeURL

    var body: some View {
        VStack(spacing: 0) {
            addressBar
            ZStack {
                if WebKernel.isHomeURL(kernel.displayedURL) {
                    NativeHomeView { url in
                        addressText = url
                        kernel.open(url)
                    }
                } else {
                    BrowserWebView(webView: kernel.webView)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(DesignTokens.pageBackground)
        .onChange(of: kernel.displayedURL) { _, newValue in
            addressText = displayAddress(newValue)
        }
    }

    private var addressBar: some View {
        HStack(spacing: 8) {
            Button {
                kernel.goBack()
                addressText = displayAddress(kernel.displayedURL)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(kernel.canGoBack ? DesignTokens.textPrimary : DesignTokens.textSecondary)
                    .frame(width: 36, height: 36)
            }
            .disabled(!kernel.canGoBack)
            .accessibilityIdentifier("nav-back")

            TextField("搜索或输入网址", text: $addressText)
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
                    kernel.open(addressText)
                }

            Button {
                if kernel.isLoading {
                    kernel.stop()
                } else if WebKernel.isHomeURL(kernel.displayedURL) {
                    kernel.open(addressText)
                } else {
                    kernel.reload()
                }
            } label: {
                Image(systemName: kernel.isLoading ? "xmark" : "arrow.clockwise")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DesignTokens.textPrimary)
                    .frame(width: 36, height: 36)
            }
            .accessibilityIdentifier("nav-reload")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(DesignTokens.surfacePanel)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DesignTokens.border)
                .frame(height: 1)
        }
    }

    private func displayAddress(_ url: String) -> String {
        WebKernel.isHomeURL(url) ? "" : url
    }
}
