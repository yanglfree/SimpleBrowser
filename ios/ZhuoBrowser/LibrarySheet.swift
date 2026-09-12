import SwiftUI

enum LibraryTab: String, CaseIterable, Identifiable {
    case bookmarks = "书签"
    case history = "历史"

    var id: String { rawValue }
}

struct LibrarySheet: View {
    @EnvironmentObject private var session: BrowserSession
    @Environment(\.dismiss) private var dismiss
    // Uses session.libraryTab so home 书签/历史 open the matching segment.

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("资料库", selection: $session.libraryTab) {
                    ForEach(LibraryTab.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .padding(16)
                .accessibilityIdentifier("library-tab")

                if session.libraryTab == .bookmarks {
                    bookmarkList
                } else {
                    historyList
                }
            }
            .background(DesignTokens.pageBackground)
            .navigationTitle("书签与历史")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                        .accessibilityIdentifier("library-done")
                }
            }
        }
        .accessibilityIdentifier("library-sheet")
    }

    @ViewBuilder
    private var bookmarkList: some View {
        if session.savedItems.isEmpty {
            emptyState("还没有书签")
        } else {
            List {
                ForEach(session.savedItems) { item in
                    Button {
                        session.openInActiveTab(item.url)
                        dismiss()
                    } label: {
                        row(title: item.title, subtitle: URLPolicy.displayHost(item.url))
                    }
                    .accessibilityIdentifier("bookmark-row-\(item.id)")
                }
                .onDelete { offsets in
                    session.removeSavedItems(at: offsets)
                }
            }
            .listStyle(.plain)
        }
    }

    @ViewBuilder
    private var historyList: some View {
        if session.history.isEmpty {
            emptyState("还没有历史记录")
        } else {
            List {
                ForEach(session.history) { entry in
                    Button {
                        session.openInActiveTab(entry.url)
                        dismiss()
                    } label: {
                        row(title: entry.title, subtitle: URLPolicy.displayHost(entry.url))
                    }
                    .accessibilityIdentifier("history-row-\(entry.id)")
                }
                .onDelete { offsets in
                    session.removeHistory(at: offsets)
                }
            }
            .listStyle(.plain)
        }
    }

    private func row(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.isEmpty ? subtitle : title)
                .foregroundStyle(DesignTokens.textPrimary)
                .lineLimit(1)
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(DesignTokens.textSecondary)
                .lineLimit(1)
        }
    }

    private func emptyState(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15))
            .foregroundStyle(DesignTokens.textSecondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
