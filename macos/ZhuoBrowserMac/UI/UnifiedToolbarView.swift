import SwiftUI

/// Unified minimalist macOS toolbar containing navigation, omnibox, and status indicators.
public struct UnifiedToolbarView: View {
    @ObservedObject var session: BrowserSession
    @State private var isEditingOmnibox: Bool = false
    @State private var inputDraft: String = ""
    @State private var isShowingSettings: Bool = false

    private var activeTab: BrowserTab? {
        session.activeTab
    }

    public var body: some View {
        HStack(spacing: 8) {
            // Navigation Buttons
            HStack(spacing: 4) {
                Button(action: { session.goBackActiveTab() }) {
                    Image(systemName: "chevron.backward")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.plain)
                .disabled(!(activeTab?.canGoBack ?? false))
                .foregroundColor((activeTab?.canGoBack ?? false) ? .primary : .secondary.opacity(0.4))
                .frame(width: 24, height: 24)
                .help("后退 (Cmd+[)")

                Button(action: { session.goForwardActiveTab() }) {
                    Image(systemName: "chevron.forward")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.plain)
                .disabled(!(activeTab?.canGoForward ?? false))
                .foregroundColor((activeTab?.canGoForward ?? false) ? .primary : .secondary.opacity(0.4))
                .frame(width: 24, height: 24)
                .help("前进 (Cmd+])")

                Button(action: { session.reloadActiveTab() }) {
                    Image(systemName: (activeTab?.isLoading ?? false) ? "xmark" : "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .disabled(activeTab?.isHome ?? true)
                .foregroundColor((activeTab?.isHome ?? true) ? .secondary.opacity(0.4) : .primary)
                .frame(width: 24, height: 24)
                .help("刷新 (Cmd+R)")
            }

            // Omnibox (Address & Search Bar)
            HStack(spacing: 6) {
                // Security / Status Icon
                if let tab = activeTab, !tab.isHome {
                    Image(systemName: tab.url.hasPrefix("https://") ? "lock.fill" : "globe")
                        .font(.system(size: 11))
                        .foregroundColor(tab.url.hasPrefix("https://") ? .secondary : .orange)
                } else {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                TextField("搜索或输入网址", text: isEditingOmnibox ? $inputDraft : $session.omniboxText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .onTapGesture {
                        if !isEditingOmnibox {
                            isEditingOmnibox = true
                            inputDraft = activeTab?.isHome == true ? "" : (activeTab?.url ?? "")
                        }
                    }
                    .onSubmit {
                        isEditingOmnibox = false
                        session.navigate(to: inputDraft)
                    }

                // Ad blocker shield indicator
                if session.settings.adBlockEnabled {
                    Image(systemName: "shield.checkered")
                        .font(.system(size: 12))
                        .foregroundColor(.accentColor)
                        .help("原生规则去广告与追踪保护已开启")
                }

                if isEditingOmnibox && !inputDraft.isEmpty {
                    Button(action: { inputDraft = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )

            // Memory Saver Badge
            MemorySaverBadge(session: session)

            // New Tab Button
            Button(action: { session.createTab() }) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("新建标签页 (Cmd+T)")

            // Preferences
            Button(action: { isShowingSettings.toggle() }) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 13))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("偏好设置")
            .sheet(isPresented: $isShowingSettings) {
                SettingsView(session: session, isPresented: $isShowingSettings)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
    }
}
