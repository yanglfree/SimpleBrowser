import PhotosUI
import SwiftUI
import UIKit

struct HomeBackgroundPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: BrowserSession
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var cachedCustomImage: UIImage?
    @State private var cachedDailyImage: UIImage?

    var body: some View {
        GeometryReader { proxy in
            content(isLandscape: proxy.size.width > proxy.size.height)
        }
        .padding(.top, 20)
        .background(DesignTokens.pageBackground)
        .onAppear(perform: loadCachedImages)
        .onChange(of: selectedPhoto) { _, item in
            importPhoto(item)
        }
        .accessibilityIdentifier("home-background-picker")
    }

    private func content(isLandscape: Bool) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("首页背景")
                        .font(.title3.weight(.semibold))
                    Text(isLandscape ? "选择横屏背景" : "选择竖屏背景")
                        .font(.subheadline)
                        .foregroundStyle(DesignTokens.textSecondary)
                }
                Spacer()
                Button("完成", action: dismiss.callAsFunction)
            }
            .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    option(
                        title: "每日美图",
                        selected: session.settings.homeBackgroundStyle == .daily,
                        identifier: "home-background-daily",
                        action: {
                            session.setHomeBackgroundStyle(.daily)
                            dismiss()
                        }
                    ) {
                        imagePreview(cachedDailyImage, isLandscape: isLandscape)
                    }

                    ForEach(HomeBackgroundPresetChoice.choices(isLandscape: isLandscape)) { choice in
                        option(
                            title: choice.label,
                            selected: choice.isSelected(in: session.settings),
                            identifier: "home-background-\(choice.id)",
                            action: { select(choice) }
                        ) {
                            presetPreview(for: choice)
                        }
                    }

                    option(
                        title: "无背景",
                        selected: session.settings.homeBackgroundStyle == .plain,
                        identifier: "home-background-none",
                        action: {
                            session.setHomeBackgroundStyle(.plain)
                            dismiss()
                        }
                    ) {
                        DesignTokens.pageBackground
                    }

                    if cachedCustomImage == nil {
                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            optionLabel(
                                title: "自定义",
                                selected: false,
                                identifier: "home-background-custom"
                            ) {
                                Image(systemName: "plus")
                                    .font(.system(size: 28, weight: .medium))
                                    .foregroundStyle(DesignTokens.textSecondary)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .background(Color(uiColor: .secondarySystemBackground))
                            }
                        }
                        .buttonStyle(.plain)
                    } else {
                        option(
                            title: "自定义",
                            selected: session.settings.homeBackgroundStyle == .custom,
                            identifier: "home-background-custom",
                            action: {
                                session.setHomeBackgroundStyle(.custom)
                                dismiss()
                            }
                        ) {
                            imagePreview(cachedCustomImage, isLandscape: isLandscape)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }

            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                Label("选择自定义照片", systemImage: "photo")
                    .font(.body.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .accessibilityIdentifier("home-background-choose-photo")

            Spacer(minLength: 8)
        }
    }

    private func option<Preview: View>(
        title: String,
        selected: Bool,
        identifier: String,
        action: @escaping () -> Void,
        @ViewBuilder preview: () -> Preview
    ) -> some View {
        Button(action: action) {
            optionLabel(
                title: title,
                selected: selected,
                identifier: identifier,
                preview: preview
            )
        }
        .buttonStyle(.plain)
    }

    private func optionLabel<Preview: View>(
        title: String,
        selected: Bool,
        identifier: String,
        @ViewBuilder preview: () -> Preview
    ) -> some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                preview()
                    .frame(width: 84, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, DesignTokens.accent)
                        .padding(6)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        selected ? DesignTokens.accent : Color(uiColor: .separator),
                        lineWidth: selected ? 2 : 1
                    )
            }
            Text(title)
                .font(.caption)
                .foregroundStyle(DesignTokens.textPrimary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }

    @ViewBuilder
    private func imagePreview(_ image: UIImage?, isLandscape: Bool) -> some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            presetPreview(
                portrait: session.settings.homePortraitPreset,
                landscape: session.settings.homeLandscapePreset,
                isLandscape: isLandscape
            )
        }
    }

    @ViewBuilder
    private func presetPreview(for choice: HomeBackgroundPresetChoice) -> some View {
        switch choice {
        case let .portrait(preset):
            presetPreview(
                portrait: preset,
                landscape: session.settings.homeLandscapePreset,
                isLandscape: false
            )
        case let .landscape(preset):
            presetPreview(
                portrait: session.settings.homePortraitPreset,
                landscape: preset,
                isLandscape: true
            )
        }
    }

    @ViewBuilder
    private func presetPreview(
        portrait: HomePortraitBackgroundPreset,
        landscape: HomeLandscapeBackgroundPreset,
        isLandscape: Bool
    ) -> some View {
        if let image = HomeBackgroundPresetImageStore.image(
            portrait: portrait,
            landscape: landscape,
            isLandscape: isLandscape
        ) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            LinearGradient(
                colors: [Color(hex: "#31584D"), Color(hex: "#91AA91")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private func loadCachedImages() {
        cachedCustomImage = cachedImage(for: .custom)
        cachedDailyImage = cachedImage(for: .daily)
    }

    private func select(_ choice: HomeBackgroundPresetChoice) {
        switch choice {
        case let .portrait(preset): session.setHomePortraitPreset(preset)
        case let .landscape(preset): session.setHomeLandscapePreset(preset)
        }
        dismiss()
    }

    private func cachedImage(for style: HomeBackgroundStyle) -> UIImage? {
        if session.settings.homeBackgroundStyle == style,
           let image = session.homeBackgroundImage {
            return image
        }
        return HomeBackgroundService.cachedImageData(for: style).flatMap(UIImage.init(data:))
    }

    private func importPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            defer { selectedPhoto = nil }
            guard let data = try? await item.loadTransferable(type: Data.self) else {
                session.flash("无法读取这张图片")
                return
            }
            await session.importCustomHomeBackground(data)
            guard session.settings.homeBackgroundStyle == .custom else { return }
            cachedCustomImage = session.homeBackgroundImage
            dismiss()
        }
    }
}
