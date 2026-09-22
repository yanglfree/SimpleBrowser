import SwiftUI

struct ArticleLibrarySheet: View {
    @EnvironmentObject private var session: BrowserSession
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var scope: ArticleFilterScope = .all
    @State private var selectedTag: String = ""
    @State private var selectedTopic: String = ""
    @State private var isImportExpanded = false
    @State private var importURL = ""
    @State private var importErrorMessage: String?
    @State private var deletion: SavedArticle?
    @State private var path: [String] = []

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                if isImportExpanded {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            TextField("输入文章网址 (http/https)", text: $importURL)
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.URL)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .accessibilityIdentifier("article-import-url-input")
                            Button("导入") {
                                submitImport()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(DesignTokens.accent)
                            .disabled(importURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityIdentifier("article-import-submit-button")
                        }
                        if let error = importErrorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(DesignTokens.surfaceSubtle)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                Picker("筛选", selection: $scope) {
                    ForEach(ArticleFilterScope.allCases) { item in
                        Text(item.label).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 6)
                .accessibilityIdentifier("article-scope-filter")

                if !allTags.isEmpty || !allTopics.isEmpty {
                    HStack(spacing: 10) {
                        if !allTags.isEmpty {
                            Menu {
                                Button("所有标签") { selectedTag = "" }
                                ForEach(allTags, id: \.self) { tag in
                                    Button(tag) { selectedTag = tag }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(selectedTag.isEmpty ? "标签" : selectedTag)
                                    Image(systemName: "chevron.down").font(.caption2)
                                }
                                .font(.subheadline)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(selectedTag.isEmpty ? DesignTokens.surfaceSubtle : DesignTokens.accent.opacity(0.15), in: Capsule())
                                .foregroundStyle(selectedTag.isEmpty ? DesignTokens.textPrimary : DesignTokens.accent)
                            }
                            .accessibilityIdentifier("article-tag-filter")
                        }

                        if !allTopics.isEmpty {
                            Menu {
                                Button("所有主题") { selectedTopic = "" }
                                ForEach(allTopics, id: \.self) { topic in
                                    Button(topic) { selectedTopic = topic }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(selectedTopic.isEmpty ? "主题" : selectedTopic)
                                    Image(systemName: "chevron.down").font(.caption2)
                                }
                                .font(.subheadline)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(selectedTopic.isEmpty ? DesignTokens.surfaceSubtle : DesignTokens.accent.opacity(0.15), in: Capsule())
                                .foregroundStyle(selectedTopic.isEmpty ? DesignTokens.textPrimary : DesignTokens.accent)
                            }
                            .accessibilityIdentifier("article-topic-filter")
                        }

                        Spacer()

                        if !selectedTag.isEmpty || !selectedTopic.isEmpty {
                            Button("重置") {
                                selectedTag = ""
                                selectedTopic = ""
                            }
                            .font(.caption)
                            .foregroundStyle(DesignTokens.textSecondary)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
                }

                Divider()

                Group {
                    if articles.isEmpty {
                        let empty = emptyStateInfo
                        ContentUnavailableView(
                            empty.title,
                            systemImage: empty.systemImage,
                            description: Text(empty.description)
                        )
                    } else {
                        List(articles) { article in
                            NavigationLink(value: article.id) {
                                ArticleRow(article: article)
                            }
                            .accessibilityIdentifier("article-row-\(article.id)")
                            .swipeActions(edge: .trailing) {
                                Button("删除", role: .destructive) { deletion = article }
                                if article.isFailed {
                                    Button("重试") {
                                        session.retryArticleCapture(article)
                                    }
                                    .tint(DesignTokens.accent)
                                    Button("原网页") {
                                        session.openArticleSource(article)
                                    }
                                } else {
                                    Button(article.archived ? "恢复" : "归档") {
                                        session.articles.setArchived(article.id, archived: !article.archived)
                                    }
                                    .tint(DesignTokens.accent)
                                    Button("原网页") {
                                        session.openArticleSource(article)
                                    }
                                    if article.quality == .partial {
                                        Button("重试图片") {
                                            session.retryArticleCapture(article)
                                        }
                                        .tint(DesignTokens.accent)
                                    }
                                }
                            }
                        }
                        .listStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: 720, maxHeight: .infinity)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DesignTokens.pageBackground)
            .navigationTitle("离线文章")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "搜索正文、笔记或标签")
            .navigationDestination(for: String.self) { id in
                ArticleDetailView(articleID: id)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isImportExpanded.toggle()
                            if isImportExpanded {
                                importErrorMessage = nil
                            }
                        }
                    } label: {
                        Image(systemName: isImportExpanded ? "link.badge.plus" : "plus")
                    }
                    .accessibilityLabel("导入网址")
                    .accessibilityIdentifier("article-add-link")
                }
            }
        }
        .alert("删除离线文章？", isPresented: Binding(
            get: { deletion != nil },
            set: { if !$0 { deletion = nil } }
        )) {
            Button("取消", role: .cancel) { deletion = nil }
            Button("删除", role: .destructive) {
                if let deletion { session.articles.remove(deletion.id) }
                deletion = nil
            }
        } message: {
            Text("正文、图片、笔记和高亮将一并删除。")
        }
        .onAppear { consumePendingSelection() }
        .onChange(of: session.pendingArticleSelectionID) { _, _ in
            consumePendingSelection()
        }
        .accessibilityIdentifier("article-library-sheet")
    }

    private var allTags: [String] {
        session.articles.allTags
    }

    private var allTopics: [String] {
        session.articles.allTopics
    }

    private var articles: [SavedArticle] {
        ArticlePolicy.filtered(
            session.articles.articles,
            query: query,
            scope: scope,
            tag: selectedTag,
            topic: selectedTopic
        )
    }

    private var emptyStateInfo: (title: String, systemImage: String, description: String) {
        if !query.isEmpty || !selectedTag.isEmpty || !selectedTopic.isEmpty {
            return ("没有匹配的文章", "magnifyingglass", "请尝试调整搜索词或标签筛选条件。")
        }
        switch scope {
        case .all:
            return ("还没有离线文章", "doc.richtext", "在网页菜单中选择“保存离线文章”，或点击右上角“+”导入网址。")
        case .active:
            return ("没有未归档文章", "tray", "已保存的所有文章均处于归档状态。")
        case .archived:
            return ("没有归档文章", "archivebox", "在文章列表中左滑即可归档文章。")
        case .failed:
            return ("没有保存失败的记录", "checkmark.circle", "所有文章提取与离线保存均已顺利完成。")
        }
    }

    private func submitImport() {
        let trimmed = importURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard URLPolicy.looksLikeURL(trimmed) else {
            importErrorMessage = "请输入有效的网址"
            return
        }
        let normalized = URLPolicy.normalizeAddress(trimmed, engine: session.settings.searchEngine)
        guard let url = URL(string: normalized), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            importErrorMessage = "仅支持导入 http 或 https 网页"
            return
        }
        importErrorMessage = nil
        session.importArticleURL(trimmed)
        importURL = ""
        withAnimation(.easeInOut(duration: 0.2)) {
            isImportExpanded = false
        }
    }

    private func consumePendingSelection() {
        guard let id = session.pendingArticleSelectionID,
              session.articles.articles.contains(where: { $0.id == id }) else { return }
        path = [id]
        session.pendingArticleSelectionID = nil
    }
}

private struct ArticleRow: View {
    let article: SavedArticle

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                if article.isFailed {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.subheadline)
                }
                Text(article.title.isEmpty ? URLPolicy.displayHost(article.sourceUrl) : article.title)
                    .font(.headline)
                    .foregroundStyle(article.isFailed ? DesignTokens.textSecondary : DesignTokens.textPrimary)
                    .lineLimit(2)
                Spacer(minLength: 8)
                if article.quality == .partial {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundStyle(DesignTokens.textSecondary)
                        .accessibilityLabel("部分内容")
                }
            }
            if article.isFailed {
                Text(article.failureMessage.isEmpty ? article.failure.displayName : article.failureMessage)
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            } else {
                Text(article.excerpt)
                    .font(.subheadline)
                    .foregroundStyle(DesignTokens.textSecondary)
                    .lineLimit(2)
            }
            HStack(spacing: 8) {
                Text(URLPolicy.displayHost(article.sourceUrl))
                if !article.tags.isEmpty { Text(article.tags.prefix(2).joined(separator: " · ")) }
                if !article.topics.isEmpty { Text(article.topics.prefix(2).joined(separator: " · ")) }
                if article.archived {
                    Text("已归档")
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(DesignTokens.surfaceSubtle, in: RoundedRectangle(cornerRadius: 3))
                }
                Spacer()
                Text(article.updatedAt.formattedRelative)
            }
            .font(.caption)
            .foregroundStyle(DesignTokens.textSecondary)
        }
        .padding(.vertical, 4)
    }
}

struct ArticleDetailView: View {
    @EnvironmentObject private var session: BrowserSession
    @Environment(\.dismiss) private var dismiss
    let articleID: String
    @State private var selection: ArticleHighlightSelection?
    @State private var editorArticle: SavedArticle?
    @State private var shareFile: ArticleShareFile?
    @State private var exportError = ""
    @State private var inspectorRequested = false

    var body: some View {
        GeometryReader { proxy in
            Group {
                if let article, !article.isFailed, let fileURL = session.articles.htmlURL(for: article) {
                    detailSurface(article: article, fileURL: fileURL, width: proxy.size.width)
                        .navigationTitle(article.title)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar { detailToolbar(article, width: proxy.size.width) }
                } else if let article {
                    failedSurface(article: article)
                        .navigationTitle(article.title.isEmpty ? URLPolicy.displayHost(article.sourceUrl) : article.title)
                        .navigationBarTitleDisplayMode(.inline)
                } else {
                    ContentUnavailableView("文章文件不可用", systemImage: "doc.badge.ellipsis")
                }
            }
        }
        .sheet(item: $editorArticle) { article in
            ArticleEditorSheet(article: article)
                .environmentObject(session)
        }
        .sheet(item: $shareFile) { file in
            ShareSheet(items: [file.url])
        }
        .alert("无法导出", isPresented: Binding(
            get: { !exportError.isEmpty },
            set: { if !$0 { exportError = "" } }
        )) { Button("好", role: .cancel) {} } message: { Text(exportError) }
    }

    private func detailSurface(article: SavedArticle, fileURL: URL, width: CGFloat) -> some View {
        let showsInspector = AdaptiveWorkspacePolicy.showsArticleInspector(
            width: Double(width),
            requested: inspectorRequested
        )
        let readerMaximum = AdaptiveWorkspacePolicy.articleReaderMaximumWidth(
            availableWidth: Double(width),
            inspectorVisible: showsInspector
        )
        return HStack(spacing: 0) {
            OfflineArticleReader(
                article: article,
                fileURL: fileURL,
                onSelection: { selection = $0 },
                onPositionChange: { session.articles.updateReadingPosition(article.id, position: $0) },
                onOpenExternal: {
                    session.openInActiveTab($0)
                    session.showsArticles = false
                }
            )
            .frame(maxWidth: CGFloat(readerMaximum))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(edges: .bottom)
            .safeAreaInset(edge: .bottom) {
                if selection != nil {
                    Button {
                        guard let selection else { return }
                        session.articles.addHighlight(article.id, selection: selection)
                        self.selection = nil
                    } label: {
                        Label("高亮所选内容", systemImage: "highlighter")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DesignTokens.accent)
                    .padding(12)
                    .background(.ultraThinMaterial)
                    .accessibilityIdentifier("article-add-highlight")
                }
            }

            if showsInspector {
                Divider()
                ArticleInspectorPane(article: article) {
                    editorArticle = article
                }
                .frame(width: CGFloat(AdaptiveWorkspacePolicy.articleInspectorWidth))
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .background(DesignTokens.pageBackground)
        .accessibilityIdentifier("article-workbench")
    }

    @ToolbarContentBuilder
    private func detailToolbar(_ article: SavedArticle, width: CGFloat) -> some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if AdaptiveWorkspacePolicy.articleWorkbenchMode(width: Double(width)) == .switchableInspector {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { inspectorRequested.toggle() }
                } label: {
                    Image(systemName: "sidebar.trailing")
                }
                .accessibilityLabel(inspectorRequested ? "隐藏文章检查器" : "显示文章检查器")
                .accessibilityIdentifier("article-inspector-toggle")
            }
            Button { editorArticle = article } label: { Image(systemName: "square.and.pencil") }
                .accessibilityLabel("编辑文章信息")
                .accessibilityIdentifier("article-edit")
            Menu {
                ForEach(ArticleExportFormat.allCases) { format in
                    Button("导出 \(format.rawValue)") { export(article, format: format) }
                }
                Divider()
                Button("打开原网页") {
                    session.openArticleSource(article)
                }
                Button(article.archived ? "移出归档" : "归档") {
                    session.articles.setArchived(article.id, archived: !article.archived)
                    if !article.archived { dismiss() }
                }
            } label: { Image(systemName: "ellipsis.circle") }
        }
    }

    private func failedSurface(article: SavedArticle) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text(article.title.isEmpty ? URLPolicy.displayHost(article.sourceUrl) : article.title)
                .font(.title3.weight(.medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(DesignTokens.textPrimary)
            Text(article.failureMessage.isEmpty ? article.failure.displayName : article.failureMessage)
                .font(.subheadline)
                .foregroundStyle(DesignTokens.textSecondary)
                .multilineTextAlignment(.center)
            Text(article.sourceUrl)
                .font(.caption)
                .foregroundStyle(DesignTokens.textSecondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            HStack(spacing: 16) {
                Button("重试保存") {
                    session.retryArticleCapture(article)
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignTokens.accent)
                .accessibilityIdentifier("article-failed-retry")

                Button("打开原网页") {
                    session.openArticleSource(article)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("article-failed-open-source")
            }
            .padding(.top, 8)
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.pageBackground)
        .toolbar {
            ToolbarItem(placement: .destructiveAction) {
                Button("删除", role: .destructive) {
                    session.articles.remove(article.id)
                    dismiss()
                }
            }
        }
    }

    private var article: SavedArticle? {
        session.articles.articles.first { $0.id == articleID }
    }

    private func export(_ article: SavedArticle, format: ArticleExportFormat) {
        do {
            shareFile = ArticleShareFile(url: try session.articles.exportURL(for: article, format: format))
        } catch {
            exportError = error.localizedDescription
        }
    }
}

private struct ArticleInspectorPane: View {
    let article: SavedArticle
    let onEdit: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("文章检查器").font(.headline)
                    Spacer()
                    Button("编辑", action: onEdit)
                        .font(.subheadline)
                        .accessibilityIdentifier("article-inspector-edit")
                }

                inspectorSection("来源") {
                    Text(URLPolicy.displayHost(article.sourceUrl))
                    if !article.author.isEmpty { Text(article.author) }
                    Text(article.updatedAt.formattedRelative)
                }

                inspectorSection("标签") {
                    labelFlow(article.tags, emptyText: "尚未添加标签")
                }

                inspectorSection("主题") {
                    labelFlow(article.topics, emptyText: "尚未添加主题")
                }

                inspectorSection("笔记") {
                    if article.notes.isEmpty {
                        Text("尚未添加笔记")
                    } else {
                        ForEach(article.notes) { note in
                            Text(note.text).textSelection(.enabled)
                        }
                    }
                }

                inspectorSection("高亮") {
                    if article.highlights.isEmpty {
                        Text("尚未添加高亮")
                    } else {
                        ForEach(article.highlights) { highlight in
                            Text(highlight.quote)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(DesignTokens.surfaceSubtle, in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
            }
            .padding(18)
        }
        .background(DesignTokens.surfacePanel)
        .accessibilityIdentifier("article-inspector")
    }

    private func inspectorSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(DesignTokens.textSecondary)
                .textCase(.uppercase)
            content()
                .font(.subheadline)
                .foregroundStyle(DesignTokens.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func labelFlow(_ labels: [String], emptyText: String) -> some View {
        if labels.isEmpty {
            Text(emptyText)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(labels, id: \.self) { label in
                    Text(label)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(DesignTokens.surfaceSubtle, in: Capsule())
                }
            }
        }
    }
}

private struct ArticleShareFile: Identifiable {
    let id = UUID()
    let url: URL
}

struct ArticleEditorSheet: View {
    @EnvironmentObject private var session: BrowserSession
    @Environment(\.dismiss) private var dismiss
    let article: SavedArticle
    @State private var tags: String
    @State private var topics: String
    @State private var note: String

    init(article: SavedArticle) {
        self.article = article
        _tags = State(initialValue: article.tags.joined(separator: ", "))
        _topics = State(initialValue: article.topics.joined(separator: ", "))
        _note = State(initialValue: article.notes.first?.text ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("整理") {
                    TextField("标签，用逗号分隔", text: $tags)
                        .accessibilityIdentifier("article-tags")
                    TextField("主题，用逗号分隔", text: $topics)
                        .accessibilityIdentifier("article-topics")
                }
                Section("笔记") {
                    TextEditor(text: $note)
                        .frame(minHeight: 130)
                        .accessibilityIdentifier("article-note")
                }
                if !article.highlights.isEmpty {
                    Section("高亮") {
                        ForEach(currentArticle.highlights) { highlight in
                            Text(highlight.quote)
                                .swipeActions {
                                    Button("删除", role: .destructive) {
                                        session.articles.removeHighlight(article.id, highlightID: highlight.id)
                                    }
                                }
                        }
                    }
                }
            }
            .navigationTitle("文章信息")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        session.articles.updateMetadata(
                            article.id,
                            tags: split(tags),
                            topics: split(topics),
                            note: note
                        )
                        dismiss()
                    }
                    .accessibilityIdentifier("article-editor-save")
                }
            }
        }
    }

    private func split(_ value: String) -> [String] {
        value.components(separatedBy: CharacterSet(charactersIn: ",，"))
    }

    private var currentArticle: SavedArticle {
        session.articles.articles.first { $0.id == article.id } ?? article
    }
}

private extension TimeInterval {
    var formattedRelative: String {
        Date(timeIntervalSince1970: self).formatted(.relative(presentation: .numeric))
    }
}
