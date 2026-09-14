import SwiftUI

struct ClearBrowsingDataSheet: View {
    @EnvironmentObject private var session: BrowserSession
    @Environment(\.dismiss) private var dismiss
    @State private var selection = BrowsingDataSelection()

    var body: some View {
        NavigationStack {
            Form {
                Section("要清除的内容") {
                    Toggle("浏览历史", isOn: $selection.history)
                        .accessibilityIdentifier("clear-data-history")
                    Toggle("Cookie 与网站存储", isOn: $selection.cookies)
                        .accessibilityIdentifier("clear-data-cookies")
                    Toggle("网页缓存", isOn: $selection.cache)
                        .accessibilityIdentifier("clear-data-cache")
                    Toggle("站点权限与拦截例外", isOn: $selection.permissions)
                        .accessibilityIdentifier("clear-data-permissions")
                }

                Section {
                    Picker("历史时间范围", selection: $selection.range) {
                        ForEach(BrowsingDataRange.allCases) { range in
                            Text(range.label).tag(range)
                        }
                    }
                    .accessibilityIdentifier("clear-data-range")
                } footer: {
                    Text("时间范围仅应用于浏览历史；Cookie、网站存储、缓存和站点权限会全部清除。书签、下载与离线文章不会受影响。")
                }
            }
            .navigationTitle("清除浏览数据")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("清除", role: .destructive) {
                        session.clearBrowsingData(selection)
                        dismiss()
                    }
                    .disabled(!selection.hasSelection)
                    .accessibilityIdentifier("clear-data-confirm")
                }
            }
        }
        .presentationDetents([.large])
        .accessibilityIdentifier("clear-data-sheet")
    }
}
