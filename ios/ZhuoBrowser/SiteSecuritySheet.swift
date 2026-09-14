import SwiftUI

struct SiteSecuritySheet: View {
    @EnvironmentObject private var session: BrowserSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: iconName)
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(iconColor)
                            .frame(width: 42)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(title)
                                .font(.headline)
                            Text(message)
                                .font(.subheadline)
                                .foregroundStyle(DesignTokens.textSecondary)
                        }
                    }
                    .padding(.vertical, 6)
                    .accessibilityIdentifier("security-state")
                }

                Section("网站") {
                    LabeledContent("域名", value: host)
                    LabeledContent("连接", value: connectionLabel)
                }

                Section("证书") {
                    Text(certificateMessage)
                        .foregroundStyle(DesignTokens.textSecondary)
                }

                Section {
                    Button("清除该站点的数据", role: .destructive) {
                        session.clearCurrentSiteData()
                    }
                    .accessibilityIdentifier("security-clear-site-data")
                } footer: {
                    Text("将清除此站点的 Cookie、网站存储、缓存、历史、权限和内容拦截例外，然后重新载入页面。")
                }
            }
            .navigationTitle("网站安全")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .accessibilityIdentifier("security-sheet")
    }

    private var state: SiteSecurityState {
        session.activeTab?.securityState ?? .unknown
    }

    private var host: String {
        URLPolicy.displayHost(session.activeTab?.url ?? "")
    }

    private var iconName: String {
        switch state {
        case .secure: return "lock.shield.fill"
        case .insecure, .certificateError: return "exclamationmark.shield.fill"
        case .unknown: return "shield"
        }
    }

    private var iconColor: Color {
        state == .secure ? DesignTokens.accent : (state == .unknown ? DesignTokens.textSecondary : .orange)
    }

    private var title: String {
        switch state {
        case .secure: return "连接安全"
        case .insecure: return "连接不安全"
        case .certificateError: return "证书验证失败"
        case .unknown: return "安全状态未知"
        }
    }

    private var message: String {
        switch state {
        case .secure: return "与此网站的连接已通过 HTTPS 加密。"
        case .insecure: return "请勿在此页面输入密码、付款信息或其他敏感内容。"
        case .certificateError: return "iOS 无法验证此网站提供的证书，页面内容可能不可信。"
        case .unknown: return "当前页面没有可供检查的标准网页连接。"
        }
    }

    private var connectionLabel: String {
        switch state {
        case .secure: return "HTTPS"
        case .insecure: return "未加密或包含不安全内容"
        case .certificateError: return "TLS 错误"
        case .unknown: return "未知"
        }
    }

    private var certificateMessage: String {
        switch state {
        case .secure:
            return "证书链已由 iOS 系统验证。WKWebView 不公开成功连接的证书主体、签发者与有效期详情。"
        case .certificateError:
            return "系统证书验证未通过，卓阅不会绕过该错误继续加载。"
        default:
            return "当前连接没有可显示的已验证证书信息。"
        }
    }
}
