import SwiftUI

/// Minimalist, distraction-free home view for ZhuoBrowser Mac.
/// Replaces heavy web portals with zero-network, zero-DOM local UI,
/// with dynamic wallpaper support and polished spring interactions.
public struct MinimalStartView: View {
    @ObservedObject var session: BrowserSession
    @ObservedObject private var bgManager = HomeBackgroundManager.shared

    @State private var searchInput: String = ""
    @State private var isShowingWallpaperPicker: Bool = false
    @State private var isSearchFocused: Bool = false
    @State private var startSuggestions: [OmniboxSuggestion] = []
    @State private var selectedStartSuggestionIndex: Int = -1
    @State private var isShowingStartSuggestions: Bool = false

    private var hasWallpaper: Bool {
        bgManager.source != .none && bgManager.currentImage != nil
    }

    public var body: some View {
        ZStack {
            // Background Layer (constrained via GeometryReader to strictly fill viewport without pushing siblings)
            GeometryReader { geo in
                if let image = bgManager.currentImage, bgManager.source != .none {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .overlay(
                            Color.black.opacity(0.38)
                        )
                        .transition(.opacity.animation(.easeInOut(duration: 0.35)))
                } else {
                    Color(NSColor.windowBackgroundColor)
                }
            }
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture {
                dismissFocus()
            }

            // Main Content Area
            GeometryReader { contentGeo in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 24) {
                        Spacer(minLength: 24)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                dismissFocus()
                            }

                        // Header & Brand
                        VStack(spacing: 10) {
                            Image("ZhuoMark")
                                .resizable()
                                .renderingMode(.template)
                                .scaledToFit()
                                .frame(width: 58, height: 58)
                                .foregroundColor(hasWallpaper ? .white : .accentColor)
                                .shadow(color: hasWallpaper ? Color.black.opacity(0.4) : SwiftUI.Color.clear, radius: 8, y: 3)
                                .accessibilityHidden(true)

                            Text("Zhuo浏览器")
                                .font(.system(size: 30, weight: .bold))
                                .foregroundColor(hasWallpaper ? .white : .primary)
                                .shadow(color: hasWallpaper ? Color.black.opacity(0.4) : SwiftUI.Color.clear, radius: 4, y: 2)

                            Text("极简 · 极速 · 极致节省内存")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(hasWallpaper ? Color.white.opacity(0.85) : .secondary)
                                .shadow(color: hasWallpaper ? Color.black.opacity(0.4) : SwiftUI.Color.clear, radius: 2, y: 1)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            dismissFocus()
                        }

                        // Minimalist Search Bar with Focus animation & URL Autocomplete
                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(hasWallpaper ? Color.white.opacity(0.8) : .secondary)

                            MacOmniboxTextField(
                                text: $searchInput,
                                isFocused: $isSearchFocused,
                                placeholder: "输入网址或搜索内容...",
                                font: .systemFont(ofSize: 14),
                                textColor: hasWallpaper ? .white : .labelColor,
                                inlineCompletionProvider: { query in
                                    session.inlineCompletion(for: query)
                                },
                                onUserInput: { query in
                                    updateStartSuggestions(for: query)
                                },
                                onMoveSelection: { delta in
                                    handleMoveStartSuggestionSelection(delta: delta)
                                },
                                onAcceptSuggestion: {
                                    handleAcceptSelectedStartSuggestion()
                                },
                                onCancelSuggestions: {
                                    if isShowingStartSuggestions {
                                        dismissStartSuggestions()
                                        return true
                                    }
                                    return false
                                },
                                onSubmit: { committed in
                                    performSearch(with: committed)
                                }
                            )
                            .frame(maxWidth: .infinity, minHeight: 20)

                            if !searchInput.isEmpty {
                                Button(action: {
                                    searchInput = ""
                                    dismissStartSuggestions()
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(hasWallpaper ? Color.white.opacity(0.7) : .secondary)
                                }
                                .buttonStyle(.plain)
                            }

                            Button(action: { performSearch() }) {
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
                            .background(
                                OmniboxDropdownAnchorView(
                                    session: session,
                                    suggestions: startSuggestions,
                                    selectedIndex: selectedStartSuggestionIndex,
                                    isPresented: (session.activeTab?.isHome ?? true) && isSearchFocused && isShowingStartSuggestions && !startSuggestions.isEmpty,
                                    onSelect: { suggestion in
                                        commitStartSuggestion(suggestion)
                                    },
                                    onDismiss: {
                                        dismissStartSuggestions()
                                        isSearchFocused = false
                                    }
                                )
                            )
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
                        .onChange(of: isSearchFocused) { focused in
                            if focused {
                                session.dismissOmniboxSuggestions()
                            } else {
                                dismissStartSuggestions()
                            }
                        }

                        // Favorites Section ("个人收藏", toggled via settings)
                        if session.settings.quickSitesEnabled {
                            FavoritesSectionView(session: session, hasWallpaper: hasWallpaper)
                                .padding(.top, 4)
                        }

                        Spacer(minLength: 24)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                dismissFocus()
                            }

                        // Footer tab residency info
                        HStack(spacing: 6) {
                            Image(systemName: "square.stack.3d.up.fill")
                                .foregroundColor(.green)
                                .font(.system(size: 11))
                            Text("标签全部常驻：切换即可瞬时恢复，不重新加载页面")
                                .font(.system(size: 11))
                                .foregroundColor(hasWallpaper ? Color.white.opacity(0.85) : .secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(hasWallpaper ? Color.black.opacity(0.28) : SwiftUI.Color.clear)
                        .cornerRadius(12)
                        .padding(.bottom, 16)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            dismissFocus()
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: contentGeo.size.height)
                    .padding(.horizontal, 24)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Top-Right Action Controls: Wallpaper & Settings (matching HarmonyOS StartPage)
            VStack {
                HStack(spacing: 10) {
                    Spacer()

                    // Background Wallpaper Button
                    Button(action: {
                        isShowingWallpaperPicker.toggle()
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 12))
                            Text("背景")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(hasWallpaper ? .white : .primary)
                        .padding(.horizontal, 11)
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

                    // Settings Button
                    Button(action: {
                        session.isShowingSettings = true
                    }) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(hasWallpaper ? .white : .primary)
                            .frame(width: 28, height: 28)
                            .background(
                                Group {
                                    if hasWallpaper {
                                        Circle().fill(.ultraThinMaterial)
                                    } else {
                                        Circle().fill(Color(nsColor: .controlBackgroundColor))
                                    }
                                }
                            )
                            .overlay(
                                Circle()
                                    .stroke(hasWallpaper ? Color.white.opacity(0.3) : Color.secondary.opacity(0.2), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("偏好设置 (Cmd+,)")
                }
                .padding(.top, 14)
                .padding(.trailing, 18)

                Spacer()
            }
        }
        .contextMenu {
            Button("更换主页背景壁纸...") {
                isShowingWallpaperPicker = true
            }
            Divider()
            Button("必应每日壁纸") {
                bgManager.setSource(.daily)
            }
            Menu("精选壁纸") {
                ForEach(HomeBackgroundManager.presets) { preset in
                    Button(preset.name) {
                        bgManager.selectPreset(id: preset.id)
                    }
                }
            }
            Button("选择本地图片...") {
                bgManager.chooseCustomImage()
            }
            Button("无背景 (纯色)") {
                bgManager.setSource(.none)
            }
            Divider()
            Button("偏好设置...") {
                session.isShowingSettings = true
            }
        }
        .onChange(of: session.activeTabID) { _ in
            if !searchInput.isEmpty {
                searchInput = ""
            }
            dismissStartSuggestions()
            if isSearchFocused {
                isSearchFocused = false
            }
        }
    }

    private func dismissFocus() {
        dismissStartSuggestions()
        if isSearchFocused {
            isSearchFocused = false
        }
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    private func updateStartSuggestions(for query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            dismissStartSuggestions()
            return
        }
        let next = session.suggestions(for: trimmed, includeSearchSuggestion: false)
        startSuggestions = next
        selectedStartSuggestionIndex = -1
        isShowingStartSuggestions = !next.isEmpty
    }

    private func dismissStartSuggestions() {
        if isShowingStartSuggestions {
            isShowingStartSuggestions = false
        }
        if selectedStartSuggestionIndex != -1 {
            selectedStartSuggestionIndex = -1
        }
        if !startSuggestions.isEmpty {
            startSuggestions = []
        }
    }

    private func handleMoveStartSuggestionSelection(delta: Int) -> Bool {
        if !isShowingStartSuggestions {
            let trimmed = searchInput.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return false }
            updateStartSuggestions(for: trimmed)
            return isShowingStartSuggestions
        }

        let count = startSuggestions.count
        guard count > 0 else { return false }

        let nextIndex: Int
        if selectedStartSuggestionIndex < 0 {
            nextIndex = delta > 0 ? 0 : (count - 1)
        } else {
            nextIndex = (selectedStartSuggestionIndex + delta + count) % count
        }

        selectedStartSuggestionIndex = nextIndex
        searchInput = startSuggestions[nextIndex].completionText
        return true
    }

    private func handleAcceptSelectedStartSuggestion() -> Bool {
        guard isShowingStartSuggestions,
              selectedStartSuggestionIndex >= 0,
              selectedStartSuggestionIndex < startSuggestions.count else {
            return false
        }
        let chosen = startSuggestions[selectedStartSuggestionIndex]
        searchInput = chosen.completionText
        updateStartSuggestions(for: chosen.completionText)
        return true
    }

    private func commitStartSuggestion(_ suggestion: OmniboxSuggestion) {
        dismissStartSuggestions()
        isSearchFocused = false
        session.navigate(to: suggestion.url)
    }

    private func performSearch(with committedText: String? = nil) {
        let rawInput = (committedText ?? searchInput).trimmingCharacters(in: .whitespacesAndNewlines)
        let target = OmniboxSuggestionPolicy.resolveSubmissionTarget(
            for: rawInput,
            suggestions: isShowingStartSuggestions ? startSuggestions : [],
            selectedIndex: selectedStartSuggestionIndex
        )
        dismissStartSuggestions()
        isSearchFocused = false
        guard !target.isEmpty else { return }
        session.navigate(to: target)
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
                // Bing Daily option & history gallery
                VStack(alignment: .leading, spacing: 8) {
                    Button(action: {
                        bgManager.selectBingWallpaper(date: nil)
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
                                if let active = bgManager.activeBingWallpaper, bgManager.source == .daily {
                                    Text("\(active.formattedFullDate) · \(active.title)")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                } else {
                                    Text("每日自动获取官方高清风光，支持切换往期壁纸")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                            }

                            Spacer()

                            if bgManager.source == .daily && bgManager.selectedBingDate == nil {
                                Text("自动更新")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(.accentColor)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.12))
                                    .cornerRadius(4)
                            } else if bgManager.source == .daily {
                                Text("往期锁定")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(.orange)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.14))
                                    .cornerRadius(4)
                            }
                        }
                        .padding(8)
                        .background(bgManager.source == .daily ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.06))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)

                    if !bgManager.bingHistory.isEmpty {
                        HStack {
                            Text("往期必应壁纸 (Cloudflare 云端归档)")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                            Spacer()
                            if bgManager.source == .daily && bgManager.selectedBingDate != nil {
                                Button("恢复今日自动") {
                                    bgManager.selectBingWallpaper(date: nil)
                                }
                                .font(.system(size: 10))
                                .buttonStyle(.plain)
                                .foregroundColor(.accentColor)
                            }
                        }

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(bgManager.bingHistory) { item in
                                    let isItemSelected = bgManager.source == .daily &&
                                        (bgManager.selectedBingDate == item.date ||
                                         (bgManager.selectedBingDate == nil && item.date == bgManager.bingHistory.first?.date))
                                    Button(action: {
                                        if item.date == bgManager.bingHistory.first?.date && bgManager.selectedBingDate == nil {
                                            bgManager.selectBingWallpaper(date: nil)
                                        } else {
                                            bgManager.selectBingWallpaper(date: item.date)
                                        }
                                    }) {
                                        VStack(spacing: 3) {
                                            ZStack(alignment: .bottomLeading) {
                                                if let thumb = bgManager.bingThumbnails[item.date] {
                                                    Image(nsImage: thumb)
                                                        .resizable()
                                                        .scaledToFill()
                                                        .frame(width: 68, height: 42)
                                                        .clipped()
                                                } else {
                                                    Color.secondary.opacity(0.15)
                                                        .frame(width: 68, height: 42)
                                                }
                                                LinearGradient(
                                                    colors: [Color.black.opacity(0.6), Color.clear],
                                                    startPoint: .bottom,
                                                    endPoint: .top
                                                )
                                                .frame(height: 16)
                                                Text(item.formattedShortDate)
                                                    .font(.system(size: 8, weight: .semibold))
                                                    .foregroundColor(.white)
                                                    .padding(.leading, 4)
                                                    .padding(.bottom, 2)
                                            }
                                            .frame(width: 68, height: 42)
                                            .clipShape(RoundedRectangle(cornerRadius: 6))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .stroke(isItemSelected ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: isItemSelected ? 2 : 1)
                                            )

                                            Text(item.title)
                                                .font(.system(size: 9))
                                                .foregroundColor(isItemSelected ? .accentColor : .primary)
                                                .frame(width: 68)
                                                .lineLimit(1)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .help("\(item.formattedFullDate) · \(item.title)")
                                }
                            }
                        }
                    }
                }

                // Presets list
                VStack(alignment: .leading, spacing: 6) {
                    Text("精选壁纸")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(HomeBackgroundManager.presets) { preset in
                                Button(action: {
                                    bgManager.selectPreset(id: preset.id)
                                }) {
                                    VStack(spacing: 4) {
                                        ZStack {
                                            if let thumb = bgManager.presetThumbnails[preset.id] {
                                                Image(nsImage: thumb)
                                                    .resizable()
                                                    .scaledToFill()
                                                    .frame(width: 58, height: 38)
                                                    .clipped()
                                            } else {
                                                Color.secondary.opacity(0.15)
                                                Text(preset.name.prefix(2))
                                                    .font(.system(size: 11, weight: .bold))
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        .frame(width: 58, height: 38)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
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
        .frame(width: 370)
        .onAppear {
            bgManager.refreshBingHistoryIfNeeded()
        }
    }
}
