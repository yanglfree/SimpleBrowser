import SwiftUI

/// Minimalist, distraction-free home view for ZhuoBrowser Mac.
/// Replaces heavy web portals with zero-network, zero-DOM local UI.
public struct MinimalStartView: View {
    @ObservedObject var session: BrowserSession
    @State private var searchInput: String = ""

    private let quickSites: [(name: String, url: String, icon: String)] = [
        ("GitHub", "https://github.com", "chevron.left.forwardslash.chevron.right"),
        ("Bing", "https://www.bing.com", "magnifyingglass"),
        ("Wikipedia", "https://zh.wikipedia.org", "character.book.closed"),
        ("V2EX", "https://www.v2ex.com", "bubble.left.and.bubble.right"),
        ("Hacker News", "https://news.ycombinator.com", "newspaper"),
        ("Bilibili", "https://www.bilibili.com", "play.tv")
    ]

    public var body: some View {
        VStack(spacing: 28) {
            Spacer()

            // Header & Brand
            VStack(spacing: 8) {
                Image(systemName: "safari")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 56, height: 56)
                    .foregroundColor(.accentColor)

                Text("卓阅")
                    .font(.system(size: 28, weight: .bold))

                Text("极简 · 极速 · 极致节省内存")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
            }

            // Minimalist Search Bar
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)

                TextField("输入网址或搜索内容...", text: $searchInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .onSubmit {
                        performSearch()
                    }

                if !searchInput.isEmpty {
                    Button(action: { searchInput = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Button(action: performSearch) {
                    Text("前往")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.15))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
            .frame(maxWidth: 480)

            // Quick Sites Grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 80, maximum: 110), spacing: 16), count: 6), spacing: 16) {
                ForEach(quickSites, id: \.url) { site in
                    Button(action: {
                        session.navigate(to: site.url)
                    }) {
                        VStack(spacing: 8) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color(NSColor.controlBackgroundColor))
                                    .frame(width: 44, height: 44)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                                    )

                                Image(systemName: site.icon)
                                    .font(.system(size: 20))
                                    .foregroundColor(.primary)
                            }

                            Text(site.name)
                                .font(.system(size: 12))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: 580)
            .padding(.top, 8)

            Spacer()

            // Footer Memory Saver info
            HStack(spacing: 6) {
                Image(systemName: "leaf.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 11))
                Text("内存卫士运行中：后台标签自动休眠，常驻内存仅需 ~50MB")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func performSearch() {
        guard !searchInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        session.navigate(to: searchInput)
    }
}
