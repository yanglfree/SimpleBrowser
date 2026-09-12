import SwiftUI

struct QuickSite: Identifiable {
    let id: String
    let title: String
    let url: String
    let badge: String
    let color: Color
}

struct NativeHomeView: View {
    let onOpen: (String) -> Void
    var onSettings: () -> Void = {}

    private let sites: [QuickSite] = [
        QuickSite(id: "zhihu", title: "知乎", url: "https://www.zhihu.com", badge: "知", color: Color(red: 0.15, green: 0.39, blue: 0.92)),
        QuickSite(id: "bilibili", title: "哔哩哔哩", url: "https://www.bilibili.com", badge: "哔", color: Color(red: 0.88, green: 0.11, blue: 0.28)),
        QuickSite(id: "sspai", title: "少数派", url: "https://sspai.com", badge: "派", color: Color(red: 0.02, green: 0.59, blue: 0.41)),
        QuickSite(id: "weibo", title: "微博", url: "https://weibo.com", badge: "微", color: Color(red: 0.85, green: 0.47, blue: 0.02)),
        QuickSite(id: "douban", title: "豆瓣", url: "https://www.douban.com", badge: "豆", color: Color(red: 0.49, green: 0.23, blue: 0.93)),
        QuickSite(id: "36kr", title: "36氪", url: "https://36kr.com", badge: "氪", color: Color(red: 0.03, green: 0.57, blue: 0.70))
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("卓阅")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(DesignTokens.textPrimary)
                    Text("干净、克制的阅读浏览器")
                        .font(.system(size: 15))
                        .foregroundStyle(DesignTokens.textSecondary)
                }
                Spacer()
                Button(action: onSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(DesignTokens.textPrimary)
                        .frame(width: 44, height: 44)
                }
                .accessibilityIdentifier("home-settings")
            }
            .padding(.horizontal, 24)
            .padding(.top, 32)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                ForEach(sites) { site in
                    Button {
                        onOpen(site.url)
                    } label: {
                        VStack(spacing: 8) {
                            Text(site.badge)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 48, height: 48)
                                .background(site.color, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            Text(site.title)
                                .font(.system(size: 13))
                                .foregroundStyle(DesignTokens.textPrimary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("quick-site-\(site.id)")
                }
            }
            .padding(.horizontal, 24)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.pageBackground)
    }
}
