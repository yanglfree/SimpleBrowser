import SwiftUI

struct QuickSiteManagerView: View {
    @EnvironmentObject private var session: BrowserSession
    @State private var editor: QuickSiteEditorRequest?

    var body: some View {
        List {
            ForEach(session.quickSites) { site in
                Button {
                    editor = .edit(site)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(site.title).foregroundStyle(DesignTokens.textPrimary)
                        Text(site.url)
                            .font(.caption)
                            .foregroundStyle(DesignTokens.textSecondary)
                            .lineLimit(1)
                    }
                }
                .accessibilityIdentifier("manage-quick-site-\(site.id)")
            }
            .onDelete { offsets in
                offsets.compactMap { session.quickSites.indices.contains($0) ? session.quickSites[$0].id : nil }
                    .forEach(session.removeQuickSite)
            }
            .onMove(perform: session.moveQuickSites)
        }
        .navigationTitle("快捷站点")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                EditButton()
                Button("添加", systemImage: "plus") { editor = .add }
                    .disabled(session.quickSites.count >= QuickSitePolicy.maximumCount)
                    .accessibilityIdentifier("manage-quick-site-add")
            }
        }
        .sheet(item: $editor) { request in
            QuickSiteEditorSheet(
                request: request,
                savedItems: session.savedItems,
                history: session.history,
                onSave: session.saveQuickSite
            )
        }
    }
}
