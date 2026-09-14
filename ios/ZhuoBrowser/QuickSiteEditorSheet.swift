import SwiftUI

enum QuickSiteEditorRequest: Identifiable {
    case add
    case edit(QuickSite)

    var id: String {
        switch self {
        case .add: return "add"
        case .edit(let site): return site.id
        }
    }

    var site: QuickSite? {
        guard case .edit(let site) = self else { return nil }
        return site
    }
}

struct QuickSiteEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let request: QuickSiteEditorRequest
    let onSave: (String, String, QuickSite?) -> Bool

    @State private var title = ""
    @State private var url = ""
    @State private var showsValidationError = false

    var body: some View {
        NavigationStack {
            Form {
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
            .navigationTitle(request.site == nil ? "添加快捷站点" : "编辑快捷站点")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if onSave(title, url, request.site) {
                            dismiss()
                        } else {
                            showsValidationError = true
                        }
                    }
                    .accessibilityIdentifier("quick-site-save")
                }
            }
            .onAppear {
                title = request.site?.title ?? ""
                url = request.site?.url ?? ""
            }
        }
        .presentationDetents([.medium])
    }
}
