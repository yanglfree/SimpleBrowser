import SwiftUI

struct NativeHomeView: View {
    let sites: [QuickSite]
    let settings: BrowserSettings
    let onOpen: (String) -> Void
    var onAdd: () -> Void = {}
    var onEdit: (QuickSite) -> Void = { _ in }
    var onRemove: (QuickSite) -> Void = { _ in }
    var onSettings: () -> Void = {}
    var onBookmarks: () -> Void = {}
    var onHistory: () -> Void = {}

    private let tileColors: [Color] = [
        Color(red: 0.15, green: 0.39, blue: 0.92),
        Color(red: 0.88, green: 0.11, blue: 0.28),
        Color(red: 0.02, green: 0.59, blue: 0.41),
        Color(red: 0.85, green: 0.47, blue: 0.02),
        Color(red: 0.49, green: 0.23, blue: 0.93),
        Color(red: 0.03, green: 0.57, blue: 0.70)
    ]

    var body: some View {
        ZStack {
            background
                .ignoresSafeArea()
            if settings.homeBackgroundStyle != .plain {
                Color.black.opacity(0.16).ignoresSafeArea()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    if settings.quickSitesEnabled {
                        siteGrid
                    }
                }
                .padding(.bottom, 32)
            }
        }
        .accessibilityIdentifier("native-home")
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text("卓阅")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(primaryText)
                Text("干净、克制的阅读浏览器")
                    .font(.system(size: 15))
                    .foregroundStyle(secondaryText)
            }
            Spacer()
            HStack(spacing: 4) {
                headerButton("bookmark", identifier: "home-bookmarks", action: onBookmarks)
                headerButton("clock", identifier: "home-history", action: onHistory)
                headerButton("gearshape", identifier: "home-settings", action: onSettings)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 32)
    }

    private var siteGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
            spacing: 16
        ) {
            ForEach(Array(sites.prefix(settings.quickSiteLimit))) { site in
                Button {
                    onOpen(site.url)
                } label: {
                    siteLabel(site)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("quick-site-\(site.id)")
                .contextMenu {
                    Button("编辑", systemImage: "pencil") { onEdit(site) }
                    Button("移除", systemImage: "trash", role: .destructive) { onRemove(site) }
                }
            }
            if sites.count < QuickSitePolicy.maximumCount {
                Button(action: onAdd) {
                    VStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(primaryText)
                            .frame(width: 48, height: 48)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        Text("添加")
                            .font(.system(size: 13))
                            .foregroundStyle(primaryText)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("quick-site-add")
            }
        }
        .padding(.horizontal, 24)
    }

    private func siteLabel(_ site: QuickSite) -> some View {
        let colorIndex = ((site.colorIndex % tileColors.count) + tileColors.count) % tileColors.count
        return VStack(spacing: 8) {
            Text(site.badge)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(tileColors[colorIndex], in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text(site.title)
                .font(.system(size: 13))
                .foregroundStyle(primaryText)
                .lineLimit(1)
        }
    }

    private func headerButton(_ image: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: image)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(primaryText)
                .frame(width: 44, height: 44)
        }
        .accessibilityIdentifier(identifier)
    }

    @ViewBuilder
    private var background: some View {
        switch settings.homeBackgroundStyle {
        case .plain:
            DesignTokens.pageBackground
        case .forest:
            LinearGradient(colors: [Color(hex: "#31584D"), Color(hex: "#91AA91")], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .dusk:
            LinearGradient(colors: [Color(hex: "#574765"), Color(hex: "#C48675")], startPoint: .top, endPoint: .bottomTrailing)
        case .ocean:
            LinearGradient(colors: [Color(hex: "#245A73"), Color(hex: "#86B8BE")], startPoint: .topLeading, endPoint: .bottom)
        }
    }

    private var primaryText: Color {
        settings.homeBackgroundStyle == .plain ? DesignTokens.textPrimary : .white
    }

    private var secondaryText: Color {
        settings.homeBackgroundStyle == .plain ? DesignTokens.textSecondary : .white.opacity(0.78)
    }
}
