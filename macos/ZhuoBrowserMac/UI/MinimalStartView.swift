import SwiftUI

/// Minimalist, distraction-free home view for ZhuoBrowser Mac.
/// Replaces heavy web portals with zero-network, zero-DOM local UI,
/// with dynamic wallpaper support and polished spring interactions.
public struct MinimalStartView: View {
    @ObservedObject var session: BrowserSession
    @ObservedObject private var bgManager = HomeBackgroundManager.shared

    @State private var searchInput: String = ""
    @State private var isShowingWallpaperPicker: Bool = false
    @FocusState private var isSearchFocused: Bool

    private let quickSites: [(name: String, url: String, icon: String)] = [
        ("GitHub", "https://github.com", "chevron.left.forwardslash.chevron.right"),
        ("Bing", "https://www.bing.com", "magnifyingglass"),
        ("Wikipedia", "https://zh.wikipedia.org", "character.book.closed"),
        ("V2EX", "https://www.v2ex.com", "bubble.left.and.bubble.right"),
        ("Hacker News", "https://news.ycombinator.com", "newspaper"),
        ("Bilibili", "https://www.bilibili.com", "play.tv")
    ]

    private var hasWallpaper: Bool {
        bgManager.source != .none && bgManager.currentImage != nil
    }

    public var body: some View {
        ZStack {
            // Background Layer
            if let image = bgManager.currentImage, bgManager.source != .none {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .overlay(
                        Color.black.opacity(0.38)
                    )
                    .transition(.opacity.animation(.easeInOut(duration: 0.35)))
            } else {
                Color(NSColor.windowBackgroundColor)
            }

            // Main Content Area
            VStack(spacing: 28) {
                Spacer()

                // Header & Brand
                VStack(spacing: 10) {
                    Image(systemName: "safari")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 58, height: 58)
                        .foregroundColor(hasWallpaper ? .white : .accentColor)
                        .shadow(color: hasWallpaper ? Color.black.opacity(0.4) : SwiftUI.Color.clear, radius: 8, y: 3)

                    Text("卓阅")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(hasWallpaper ? .white : .primary)
                        .shadow(color: hasWallpaper ? Color.black.opacity(0.4) : SwiftUI.Color.clear, radius: 4, y: 2)

                    Text("极简 · 极速 · 极致节省内存")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(hasWallpaper ? Color.white.opacity(0.85) : .secondary)
                        .shadow(color: hasWallpaper ? Color.black.opacity(0.4) : SwiftUI.Color.clear, radius: 2, y: 1)
                }

                // Minimalist Search Bar with Focus animation
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(hasWallpaper ? Color.white.opacity(0.8) : .secondary)

                    TextField("输入网址或搜索内容...", text: $searchInput)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .foregroundColor(hasWallpaper ? .white : .primary)
                        .focused($isSearchFocused)
                        .onSubmit {
                            performSearch()
                        }

                    if !searchInput.isEmpty {
                        Button(action: { searchInput = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(hasWallpaper ? Color.white.opacity(0.7) : .secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    Button(action: performSearch) {
                        Text("前往")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(hasWallpaper ? .white : .primary)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 5)
                            .background(Color.accentColor.opacity(hasWallpaper ? 0.85 : 0.18))
                            .cornerRadius(7)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    Group {
                        if hasWallpaper {
                            RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial)
                        } else {
                            RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor))
                        }
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            isSearchFocused ? Color.accentColor : (hasWallpaper ? Color.white.opacity(0.25) : Color.secondary.opacity(0.2)),
                            lineWidth: isSearchFocused ? 1.5 : 1
                        )
                )
                .shadow(color: Color.black.opacity(hasWallpaper ? 0.25 : 0.05), radius: 10, y: 4)
                .frame(maxWidth: 480)
                .scaleEffect(isSearchFocused ? 1.01 : 1.0)
                .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isSearchFocused)

                // Quick Sites Grid with spring motion
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 80, maximum: 110), spacing: 16), count: 6), spacing: 16) {
                    ForEach(quickSites, id: \.url) { site in
                        QuickSiteItemView(
                            site: site,
                            hasWallpaper: hasWallpaper,
                            onTap: {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    session.navigate(to: site.url)
                                }
                            }
                        )
                    }
                }
                .frame(maxWidth: 580)
                .padding(.top, 8)

                Spacer()

                // Footer Memory Saver Info
                HStack(spacing: 6) {
                    Image(systemName: "leaf.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 11))
                    Text("内存卫士运行中：后台标签自动休眠，常驻内存仅需 ~50MB")
                        .font(.system(size: 11))
                        .foregroundColor(hasWallpaper ? Color.white.opacity(0.85) : .secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(hasWallpaper ? Color.black.opacity(0.28) : SwiftUI.Color.clear)
                .cornerRadius(12)
                .padding(.bottom, 20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Wallpaper Switcher Button (Bottom Right)
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button(action: {
                        isShowingWallpaperPicker.toggle()
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 12))
                            Text("背景")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(hasWallpaper ? .white : .primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Group {
                                if hasWallpaper {
                                    Capsule().fill(.ultraThinMaterial)
                                } else {
                                    Capsule().fill(Color(nsColor: .controlBackgroundColor))
                                }
                            }
                        )
                        .overlay(
                            Capsule()
                                .stroke(hasWallpaper ? Color.white.opacity(0.3) : Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .help("更换主页背景壁纸")
                    .popover(isPresented: $isShowingWallpaperPicker, arrowEdge: .bottom) {
                        WallpaperPickerPopover(bgManager: bgManager)
                    }
                    .padding(.trailing, 22)
                    .padding(.bottom, 18)
                }
            }
        }
    }

    private func performSearch() {
        guard !searchInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        session.navigate(to: searchInput)
    }
}

/// Animated Quick Site item button with hover and press feedback.
private struct QuickSiteItemView: View {
    let site: (name: String, url: String, icon: String)
    let hasWallpaper: Bool
    let onTap: () -> Void

    @State private var isHovered: Bool = false
    @State private var isPressed: Bool = false

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                ZStack {
                    Group {
                        if hasWallpaper {
                            RoundedRectangle(cornerRadius: 11)
                                .fill(.ultraThinMaterial)
                        } else {
                            RoundedRectangle(cornerRadius: 11)
                                .fill(Color(nsColor: .controlBackgroundColor))
                        }
                    }
                    .frame(width: 46, height: 46)
                        .overlay(
                            RoundedRectangle(cornerRadius: 11)
                                .stroke(
                                    isHovered ? Color.accentColor : (hasWallpaper ? Color.white.opacity(0.3) : Color.secondary.opacity(0.18)),
                                    lineWidth: isHovered ? 1.5 : 1
                                )
                        )
                        .shadow(color: Color.black.opacity(isHovered ? 0.2 : (hasWallpaper ? 0.15 : 0.04)), radius: isHovered ? 6 : 3, y: 2)

                    Image(systemName: site.icon)
                        .font(.system(size: 20))
                        .foregroundColor(hasWallpaper ? .white : .primary)
                }
                .scaleEffect(isPressed ? 0.94 : (isHovered ? 1.08 : 1.0))

                Text(site.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(hasWallpaper ? .white : .primary)
                    .shadow(color: hasWallpaper ? Color.black.opacity(0.4) : SwiftUI.Color.clear, radius: 2, y: 1)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                isHovered = hovering
            }
        }
    }
}

/// Popover sheet for picking start page wallpapers (Daily Bing, Presets, Custom, None).
private struct WallpaperPickerPopover: View {
    @ObservedObject var bgManager: HomeBackgroundManager

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("主页背景")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                if bgManager.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            // Options Row
            VStack(alignment: .leading, spacing: 10) {
                // Bing Daily option
                Button(action: {
                    bgManager.setSource(.daily)
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: "sun.max.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.orange)
                            .frame(width: 24, height: 24)
                            .background(Color.orange.opacity(0.15))
                            .cornerRadius(6)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("必应每日壁纸")
                                .font(.system(size: 12, weight: .medium))
                            Text("每日自动获取官方高清风光")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        if bgManager.source == .daily {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.accentColor)
                        }
                    }
                    .padding(8)
                    .background(bgManager.source == .daily ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.06))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)

                // Presets list
                VStack(alignment: .leading, spacing: 6) {
                    Text("精选壁纸")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(HomeBackgroundManager.presets) { preset in
                                Button(action: {
                                    bgManager.selectPreset(id: preset.id)
                                }) {
                                    VStack(spacing: 4) {
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color.secondary.opacity(0.15))
                                            .frame(width: 60, height: 40)
                                            .overlay(
                                                Text(preset.name.prefix(2))
                                                    .font(.system(size: 11, weight: .bold))
                                                    .foregroundColor(.secondary)
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .stroke(
                                                        bgManager.source == .preset && bgManager.selectedPresetId == preset.id ? Color.accentColor : SwiftUI.Color.clear,
                                                        lineWidth: 2
                                                    )
                                            )

                                        Text(preset.name)
                                            .font(.system(size: 10))
                                            .foregroundColor(.primary)
                                            .lineLimit(1)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                Divider()

                // Custom Image & None buttons
                HStack(spacing: 8) {
                    Button(action: {
                        bgManager.chooseCustomImage()
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "folder")
                                .font(.system(size: 11))
                            Text("本地图片...")
                                .font(.system(size: 11))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(bgManager.source == .custom ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button(action: {
                        bgManager.setSource(.none)
                    }) {
                        Text("无背景 (纯色)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(bgManager.source == .none ? Color.accentColor.opacity(0.12) : SwiftUI.Color.clear)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .frame(width: 320)
    }
}
