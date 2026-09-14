import SwiftUI

struct SavedItemEditSheet: View {
    @EnvironmentObject private var session: BrowserSession
    @Environment(\.dismiss) private var dismiss
    let item: SavedItem
    @State private var title: String

    init(item: SavedItem) {
        self.item = item
        _title = State(initialValue: item.title)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(URLPolicy.displayHost(item.url))
                        .foregroundStyle(DesignTokens.textSecondary)
                    TextField("书签名称", text: $title)
                        .accessibilityIdentifier("bookmark-name-input")
                }

                Section {
                    Button("删除书签", role: .destructive) {
                        session.removeSavedItem(item.id)
                        dismiss()
                    }
                    .accessibilityIdentifier("bookmark-delete")
                }
            }
            .scrollContentBackground(.hidden)
            .background(DesignTokens.pageBackground)
            .navigationTitle("编辑书签")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        session.renameSavedItem(item.id, title: title)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("bookmark-save")
                }
            }
        }
        .accessibilityIdentifier("bookmark-edit-sheet")
    }
}
