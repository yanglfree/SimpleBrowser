import SwiftUI
import UIKit

struct NativeHomeView: View {
    let sites: [QuickSite]
    let settings: BrowserSettings
    let backgroundImage: UIImage?
    let siteIcons: [String: UIImage]
    let onOpen: (String) -> Void
    var onAdd: () -> Void = {}
    var onEdit: (QuickSite) -> Void = { _ in }
    var onRemove: (QuickSite) -> Void = { _ in }
    var onMove: (String, String) -> Void = { _, _ in }
    var onSettings: () -> Void = {}
    var onOpenBackgroundPicker: () -> Void = {}
    var onBookmarks: () -> Void = {}
    var onHistory: () -> Void = {}
    @State private var isEditingQuickSites = false

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
            GeometryReader { proxy in
                background(isLandscape: proxy.size.width > proxy.size.height)
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .ignoresSafeArea()
            if settings.homeBackgroundEnabled {
                Color.black.opacity(0.16)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
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
        .onLongPressGesture(minimumDuration: 0.5) {
            guard !isEditingQuickSites else { return }
            onOpenBackgroundPicker()
        }
        .onChange(of: settings.quickSitesEnabled) { _, enabled in
            if !enabled {
                isEditingQuickSites = false
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
        VStack(alignment: .trailing, spacing: 8) {
            if isEditingQuickSites {
                Button("完成") {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isEditingQuickSites = false
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(primaryText)
                .accessibilityIdentifier("quick-site-edit-done")
            }

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                spacing: 16
            ) {
                ForEach(visibleSites) { site in
                    quickSiteTile(site)
                }

                if sites.count < QuickSitePolicy.maximumCount {
                    Button(action: onAdd) {
                        VStack(spacing: 8) {
                            Image(systemName: "plus")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(primaryText)
                                .frame(width: 48, height: 48)
                                .background(
                                    .ultraThinMaterial,
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                                )
                            Text("添加")
                                .font(.system(size: 13))
                                .foregroundStyle(primaryText)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isEditingQuickSites)
                    .opacity(isEditingQuickSites ? 0.45 : 1)
                    .accessibilityIdentifier("quick-site-add")
                }
            }
        }
        .padding(.horizontal, 24)
    }

    private var visibleSites: [QuickSite] {
        Array(sites.prefix(settings.quickSiteLimit))
    }

    @ViewBuilder
    private func quickSiteTile(_ site: QuickSite) -> some View {
        if isEditingQuickSites {
            quickSiteTileContent(site)
                .draggable(site.id) {
                    siteLabel(site)
                        .frame(width: 88)
                        .padding(10)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
                .dropDestination(for: String.self) { ids, _ in
                    guard let sourceID = ids.first, sourceID != site.id else { return false }
                    onMove(sourceID, site.id)
                    return true
                }
        } else {
            quickSiteTileContent(site)
                .highPriorityGesture(
                    LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                        withAnimation(.easeInOut(duration: 0.18)) {
                            isEditingQuickSites = true
                        }
                    }
                )
        }
    }

    private func quickSiteTileContent(_ site: QuickSite) -> some View {
        ZStack(alignment: .topTrailing) {
            Button {
                if isEditingQuickSites {
                    onEdit(site)
                } else {
                    onOpen(site.url)
                }
            } label: {
                siteLabel(site)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("quick-site-\(site.id)")

            if isEditingQuickSites {
                Button(role: .destructive) {
                    onRemove(site)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(.red, in: Circle())
                }
                .offset(x: 4, y: -4)
                .accessibilityLabel("移除 \(site.title)")
                .accessibilityIdentifier("quick-site-remove-\(site.id)")
            }
        }
        .accessibilityAction(named: "编辑") { onEdit(site) }
        .accessibilityAction(named: "移除") { onRemove(site) }
    }

    private func siteLabel(_ site: QuickSite) -> some View {
        let colorIndex = ((site.colorIndex % tileColors.count) + tileColors.count) % tileColors.count
        return VStack(spacing: 8) {
            if let image = siteIcons[URLPolicy.rawHost(site.url)] {
                SiteIconThumbnail(image: image, size: 48, cornerRadius: 14)
            } else if let theme = QuickSiteSemanticPolicy.theme(title: site.title, url: site.url) {
                Image(systemName: theme.systemImageName)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(
                        Color(hex: theme.backgroundHex),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
            } else {
                Text(site.badge)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(tileColors[colorIndex], in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
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
    private func background(isLandscape: Bool) -> some View {
        if !settings.homeBackgroundEnabled {
            DesignTokens.pageBackground
        } else {
            enabledBackground(isLandscape: isLandscape)
        }
    }

    @ViewBuilder
    private func enabledBackground(isLandscape: Bool) -> some View {
        switch settings.homeBackgroundStyle {
        case .plain:
            DesignTokens.pageBackground
        case .forest, .dusk, .ocean:
            if let image = HomeBackgroundPresetImageStore.image(
                portrait: settings.homePortraitPreset,
                landscape: settings.homeLandscapePreset,
                isLandscape: isLandscape
            ) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .clipped()
            } else {
                LinearGradient(
                    colors: [Color(hex: "#31584D"), Color(hex: "#91AA91")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        case .daily, .custom:
            if let backgroundImage {
                Image(uiImage: backgroundImage)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(colors: [Color(hex: "#31584D"), Color(hex: "#91AA91")], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
    }

    private var primaryText: Color {
        settings.homeBackgroundEnabled ? .white : DesignTokens.textPrimary
    }

    private var secondaryText: Color {
        settings.homeBackgroundEnabled ? .white.opacity(0.78) : DesignTokens.textSecondary
    }
}
