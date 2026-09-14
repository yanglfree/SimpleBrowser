import SwiftUI

enum QuickSiteEditorRequest: Identifiable {
    case add
    case edit(QuickSite)

    var id: String {
        switch self {
        case .add: return "add"
        case let .edit(site): return site.id
        }
    }

    var site: QuickSite? {
        guard case let .edit(site) = self else { return nil }
        return site
    }
}

struct QuickSiteEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let request: QuickSiteEditorRequest
    let savedItems: [SavedItem]
    let history: [HistoryEntry]
    let onSave: (String, String, QuickSite?) -> Bool

    @State private var source: QuickSiteEditorSource = .custom
    @State private var title = ""
    @State private var url = ""
    @State private var showsValidationError = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("来源", selection: $source) {
                        ForEach(QuickSiteEditorSource.allCases) { item in
                            Text(item.label).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("quick-site-source")
                }

                if source == .custom {
                    customSection
                } else {
                    sourceSection
                }
            }
            .scrollContentBackground(.hidden)
            .background(DesignTokens.pageBackground)
            .navigationTitle(request.site == nil ? "添加快捷站点" : "编辑快捷站点")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                if source == .custom {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存", action: saveCustom)
                            .accessibilityIdentifier("quick-site-save")
                    }
                }
            }
            .onAppear {
                title = request.site?.title ?? ""
                url = request.site?.url ?? ""
                source = .custom
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var customSection: some View {
        Section {
            TextField("名称", text: $title)
                .textInputAutocapitalization(.never)
                .accessibilityIdentifier("quick-site-title")
            TextField("网址", text: $url)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .accessibilityIdentifier("quick-site-url")
        } footer: {
            Text(showsValidationError ? "请输入有效且未重复的网址。" : "同一站点只能添加一次。")
                .foregroundStyle(showsValidationError ? Color.red : DesignTokens.textSecondary)
        }
    }

    @ViewBuilder
    private var sourceSection: some View {
        let entries = QuickSiteSourcePolicy.entries(
            for: source,
            savedItems: savedItems,
            history: history
        )
        Section(source.label) {
            if entries.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: source.systemImage)
                        .font(.title2)
                    Text(source == .favorites ? "暂无收藏" : "暂无历史记录")
                }
                .foregroundStyle(DesignTokens.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 120)
                .accessibilityIdentifier("quick-site-source-empty")
            } else {
                ForEach(entries) { entry in
                    Button {
                        select(entry)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: source.systemImage)
                                .foregroundStyle(DesignTokens.textSecondary)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(entry.displayTitle)
                                    .foregroundStyle(DesignTokens.textPrimary)
                                    .lineLimit(1)
                                Text(URLPolicy.displayHost(entry.url))
                                    .font(.caption)
                                    .foregroundStyle(DesignTokens.textSecondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "plus")
                                .foregroundStyle(DesignTokens.accent)
                        }
                    }
                    .accessibilityIdentifier("quick-site-source-\(entry.id)")
                }
            }
        }
    }

    private func saveCustom() {
        if onSave(title, url, request.site) {
            dismiss()
        } else {
            showsValidationError = true
        }
    }

    private func select(_ entry: QuickSiteSourceEntry) {
        if onSave(entry.title, entry.url, request.site) {
            dismiss()
            return
        }
        title = entry.title
        url = entry.url
        showsValidationError = true
        source = .custom
    }
}
