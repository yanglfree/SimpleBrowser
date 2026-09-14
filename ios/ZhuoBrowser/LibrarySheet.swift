import SwiftUI

enum LibraryTab: String, CaseIterable, Identifiable {
    case bookmarks = "书签"
    case history = "历史"

    var id: String { rawValue }
}

private struct HistoryGroup: Identifiable {
    let id: String
    let title: String
    let entries: [HistoryEntry]
}

private struct HistoryHostDeletionRequest: Identifiable {
    let host: String

    var id: String { host }
}

struct LibrarySheet: View {
    @EnvironmentObject private var session: BrowserSession
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var editingSavedItem: SavedItem?
    @State private var historyHostDeletion: HistoryHostDeletionRequest?

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
            .searchable(text: $query, prompt: "搜索标题或网址")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                        .accessibilityIdentifier("library-done")
                }
            }
        }
        .sheet(item: $editingSavedItem) { item in
            SavedItemEditSheet(item: item)
                .environmentObject(session)
                .presentationDetents([.medium])
        }
        .alert(item: $historyHostDeletion) { request in
            Alert(
                title: Text("删除该站点的历史记录？"),
                message: Text("将删除 \(request.host) 的全部历史记录。"),
                primaryButton: .cancel(Text("取消")),
                secondaryButton: .destructive(Text("删除")) {
                    session.removeHistory(forHost: request.host)
                }
            )
        }
        .onChange(of: session.libraryTab) { _, _ in
            query = ""
        }
        .accessibilityIdentifier("library-sheet")
    }

    @ViewBuilder
    private var bookmarkList: some View {
        let items = LibraryPolicy.filteredSavedItems(session.savedItems, query: query)
        if items.isEmpty {
            emptyState(query.isEmpty ? "还没有书签" : "没有匹配的书签")
        } else {
            List {
                ForEach(items) { item in
                    Button {
                        open(item.url)
                    } label: {
                        LibraryRow(
                            title: item.title,
                            subtitle: URLPolicy.displayHost(item.url),
                            trailing: item.isRead ? nil : "稍后读"
                        )
                    }
                    .accessibilityIdentifier("bookmark-row-\(item.id)")
                    .swipeActions(edge: .trailing) {
                        Button("删除", role: .destructive) {
                            session.removeSavedItem(item.id)
                        }
                        Button("编辑") {
                            editingSavedItem = item
                        }
                        .tint(DesignTokens.accent)
                    }
                    .contextMenu {
                        Button("编辑书签") {
                            editingSavedItem = item
                        }
                        Button("删除书签", role: .destructive) {
                            session.removeSavedItem(item.id)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder
    private var historyList: some View {
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            historySearchList
        } else if session.history.isEmpty {
            emptyState("还没有历史记录")
        } else {
            List {
                ForEach(historyGroups) { group in
                    Section(group.title) {
                        ForEach(group.entries) { entry in
                            historyRow(entry)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder
    private var historySearchList: some View {
        let results = LibraryPolicy.searchHistoryAndBookmarks(
            query: query,
            history: session.history,
            savedItems: session.savedItems
        )
        if results.isEmpty {
            emptyState("没有匹配的记录")
        } else {
            List(results) { entry in
                Button {
                    open(entry.url)
                } label: {
                    LibraryRow(
                        title: entry.title,
                        subtitle: URLPolicy.displayHost(entry.url),
                        trailing: entry.kind == .bookmark ? "书签" : nil
                    )
                }
                .accessibilityIdentifier("library-search-row-\(entry.id)")
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private func historyRow(_ entry: HistoryEntry) -> some View {
        Button {
            open(entry.url)
        } label: {
            LibraryRow(
                title: entry.title,
                subtitle: URLPolicy.displayHost(entry.url),
                trailing: timeLabel(entry.visitedAt)
            )
        }
        .accessibilityIdentifier("history-row-\(entry.id)")
        .swipeActions(edge: .trailing) {
            Button("删除", role: .destructive) {
                session.removeHistoryEntry(entry.id)
            }
        }
        .contextMenu {
            Button("删除这条记录", role: .destructive) {
                session.removeHistoryEntry(entry.id)
            }
            Button("删除此站点的历史记录", role: .destructive) {
                let host = URLPolicy.rawHost(entry.url)
                if !host.isEmpty {
                    historyHostDeletion = HistoryHostDeletionRequest(host: host)
                }
            }
        }
    }

    private var historyGroups: [HistoryGroup] {
        let calendar = Calendar.current
        var today: [HistoryEntry] = []
        var yesterday: [HistoryEntry] = []
        var earlier: [HistoryEntry] = []
        for entry in session.history.sorted(by: { $0.visitedAt > $1.visitedAt }) {
            let date = Date(timeIntervalSince1970: entry.visitedAt)
            if calendar.isDateInToday(date) {
                today.append(entry)
            } else if calendar.isDateInYesterday(date) {
                yesterday.append(entry)
            } else {
                earlier.append(entry)
            }
        }
        return [
            HistoryGroup(id: "today", title: "今天", entries: today),
            HistoryGroup(id: "yesterday", title: "昨天", entries: yesterday),
            HistoryGroup(id: "earlier", title: "更早", entries: earlier)
        ].filter { !$0.entries.isEmpty }
    }

    private func open(_ url: String) {
        session.openInActiveTab(url)
        dismiss()
    }

    private func timeLabel(_ timestamp: TimeInterval) -> String {
        Date(timeIntervalSince1970: timestamp).formatted(date: .omitted, time: .shortened)
    }

    private func emptyState(_ text: String) -> some View {
        ContentUnavailableView(
            text,
            systemImage: session.libraryTab == .bookmarks ? "bookmark" : "clock"
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct LibraryRow: View {
    let title: String
    let subtitle: String
    let trailing: String?

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title.isEmpty ? subtitle : title)
                    .foregroundStyle(DesignTokens.textPrimary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(DesignTokens.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(DesignTokens.textSecondary)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
    }
}
