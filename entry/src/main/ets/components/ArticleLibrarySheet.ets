import {
  ArticleHighlight,
  ArticleNote,
  ArticleSaveFailure,
  isReadableSavedArticle,
  SavedArticle,
  Topic
} from '../models/ArticleLibraryModels';
import {
  ARTICLE_WORKBENCH_INSPECTOR_WIDTH,
  ArticleWorkbenchMode,
  articleWorkbenchMode,
  shouldShowArticleInspector
} from '../models/ArticleWorkbenchModels';
import { BrowserLayoutClass } from '../models/WindowMetrics';
import { ArticleExportFormat } from '../services/ArticleExportService';
import { displayHost, looksLikeUrl, normalizeUrlInput } from '../utils/UrlUtils';
import { ArticleAnnotationPanel } from './ArticleAnnotationPanel';
import { AppIcon, IconName } from './AppIcon';
import { articleStatusLabel } from './ArticleStatus';
import { OfflineArticleReader } from './OfflineArticleReader';

@Component
export struct ArticleLibrarySheet {
  @Prop topInset: number = 0;
  @Prop @Watch('refreshFilter') articles: SavedArticle[] = [];
  @Prop @Watch('selectionChanged') selectedArticle: SavedArticle | undefined = undefined;
  @Prop markdown: string = '';
  @Prop html: string = '';
  @Prop isPro: boolean = false;
  @Prop isLoading: boolean = false;
  @Prop notes: ArticleNote[] = [];
  @Prop topics: Topic[] = [];
  @Prop highlights: ArticleHighlight[] = [];
  @Prop layoutClass: BrowserLayoutClass = BrowserLayoutClass.Compact;
  @Prop availableWidthVp: number = 0;
  @Prop inspectorVisible: boolean = false;
  @Prop initialReadingScrollOffset: number = 0;
  @State private query: string = '';
  @State private filter: number = 0;
  @State private filteredArticles: SavedArticle[] = [];
  @State private annotationsVisible: boolean = false;
  @State private highlightTarget: string = '';
  @State private tagOptions: SelectOption[] = [];
  @State private topicOptions: SelectOption[] = [];
  @State private selectedTag: string = '';
  @State private selectedTopic: string = '';
  @State private importVisible: boolean = false;
  @State private importUrl: string = '';
  @State private importInvalid: boolean = false;
  private readingOffset: number = 0;
  private readingArticleId: string = '';
  onDismiss: () => void = (): void => {};
  onImport: (url: string) => void = (): void => {};
  onSelect: (articleId: string) => void = (_articleId: string): void => {};
  onBackToList: () => void = (): void => {};
  onExport: (format: ArticleExportFormat) => void = (_format: ArticleExportFormat): void => {};
  onSearch: (query: string) => void = (_query: string): void => {};
  onAddNote: (body: string) => Promise<void> = async (): Promise<void> => {};
  onAddTopic: (name: string) => Promise<void> = async (): Promise<void> => {};
  onUpdateTags: (tags: string[]) => void = (_tags: string[]): void => {};
  onArchive: (isArchived: boolean) => void = (_isArchived: boolean): void => {};
  onAddHighlight: (quote: string) => void = (_quote: string): void => {};
  onInspectorVisibilityChange: (visible: boolean) => void = (_visible: boolean): void => {};
  onReadingScroll: (offset: number) => void = (_offset: number): void => {};
  onOpenSource: (article: SavedArticle) => void = (): void => {};
  onOpenLink: (url: string) => void = (): void => {};
  onRetry: (article: SavedArticle) => void = (): void => {};
  onDelete: (article: SavedArticle) => void = (): void => {};
  onEditNote: (id: string, body: string) => Promise<void> = async (): Promise<void> => {};
  onDeleteNote: (id: string) => Promise<void> = async (): Promise<void> => {};
  onDeleteHighlight: (id: string) => Promise<void> = async (): Promise<void> => {};
  onRemoveTopic: (id: string) => Promise<void> = async (): Promise<void> => {};
  onSelectedHighlight: (quote: string, text: string) => Promise<void> = async (): Promise<void> => {};

  aboutToAppear(): void {
    this.refreshFilter();
    this.selectionChanged();
  }

  private selectionChanged(): void {
    const id: string = this.selectedArticle?.id ?? '';
    if (id !== this.readingArticleId) {
      this.readingArticleId = id;
      this.readingOffset = this.selectedArticle?.readingPosition ?? 0;
      this.highlightTarget = '';
    }
  }

  build() {
    Column() {
      if (this.selectedArticle === undefined) {
        this.LibraryHeader()
        this.ArticleList()
      } else {
        this.ArticleDetail(this.selectedArticle)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  private LibraryHeader() {
    Row({ space: 12 }) {
      AppIcon({ name: IconName.ArrowLeft, glyphSize: 21, color: $r('app.color.text_primary') })
        .onClick(() => this.onDismiss())
      Text($r('app.string.article_library'))
        .fontSize(24)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
      Text(`${this.filteredArticles.length}`)
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .fontFeature('"tnum" 1')
      Button($r('app.string.article_add_link'))
        .fontSize(13)
        .height(40)
        .backgroundColor($r('app.color.accent'))
        .onClick((): void => { this.importVisible = !this.importVisible; })
    }
    .width('100%')
    .height(56 + Math.max(0, this.topInset))
    .padding({ top: Math.max(0, this.topInset), left: 24, right: 24 })
    .alignItems(VerticalAlign.Center)
    .border({ width: { bottom: 1 }, color: $r('app.color.border') })

    if (this.importVisible) {
      Row({ space: 8 }) {
        TextInput({ text: this.importUrl, placeholder: $r('app.string.article_link_placeholder') })
          .layoutWeight(1)
          .height(42)
          .onChange((value: string): void => { this.importUrl = value; this.importInvalid = false; })
        Button($r('app.string.article_save'))
          .height(42)
          .backgroundColor($r('app.color.accent'))
          .onClick((): void => {
            const value: string = this.importUrl.trim();
            const url: string = normalizeUrlInput(value);
            if (!looksLikeUrl(value) || !/^https?:\/\//i.test(url)) {
              this.importInvalid = true;
              return;
            }
            this.onImport(url);
          })
      }.padding({ left: 20, right: 20, top: 8, bottom: 8 })
      if (this.importInvalid) {
        Text($r('app.string.article_invalid_link')).fontSize(12).fontColor($r('app.color.text_secondary'))
      }
    }

    TextInput({ text: this.query, placeholder: $r('app.string.article_search_placeholder') })
      .width('90%')
      .height(42)
      .margin({ left: 24, right: 24, bottom: 10 })
      .padding({ left: 12, right: 12 })
      .fontSize(14)
      .fontColor($r('app.color.text_primary'))
      .placeholderColor($r('app.color.text_secondary'))
      .backgroundColor($r('app.color.surface_subtle'))
      .borderRadius(10)
      .onChange((value: string): void => {
        this.query = value;
        this.onSearch(value);
      })
    Flex({ wrap: FlexWrap.Wrap }) {
      this.FilterButton($r('app.string.article_filter_all'), 0)
      this.FilterButton($r('app.string.article_filter_active'), 1)
      this.FilterButton($r('app.string.article_archived'), 2)
      this.FilterButton($r('app.string.article_filter_failed'), 3)
    }
    .padding({ left: 20, right: 20, bottom: 8 })
    Row({ space: 12 }) {
      Select(this.tagOptions).value(this.selectedTag || $r('app.string.article_tags'))
        .layoutWeight(1)
        .onSelect((index: number, value: string): void => {
          this.selectedTag = index === 0 ? '' : value;
          this.refreshFilter();
        })
      Select(this.topicOptions).value(this.selectedTopic || $r('app.string.article_topics'))
        .layoutWeight(1)
        .onSelect((index: number, value: string): void => {
          this.selectedTopic = index === 0 ? '' : value;
          this.refreshFilter();
        })
    }.padding({ left: 20, right: 20, bottom: 8 }).width('100%')
    if (!this.isPro) {
      Text($r('app.string.article_offline_retained'))
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .padding({ left: 24, right: 24, bottom: 12 })
    }
  }

  @Builder
  private FilterButton(label: Resource, value: number) {
    Button(label)
      .fontSize(12)
      .height(36)
      .margin({ right: 8, bottom: 4 })
      .backgroundColor(this.filter === value ? $r('app.color.accent') : $r('app.color.surface_subtle'))
      .fontColor(this.filter === value ? Color.White : $r('app.color.text_primary'))
      .onClick((): void => { this.filter = value; this.refreshFilter(); })
  }

  private refreshFilter(): void {
    const tags: string[] = [];
    const topics: string[] = [];
    for (const article of this.articles) {
      for (const tag of article.tags) {
        if (!tags.includes(tag)) {
          tags.push(tag);
        }
      }
      for (const topic of article.topicNames ?? []) {
        if (!topics.includes(topic)) {
          topics.push(topic);
        }
      }
    }
    this.tagOptions = [{ value: $r('app.string.article_filter_all') },
      ...tags.sort().map((value: string): SelectOption => { return { value: value }; })];
    this.topicOptions = [{ value: $r('app.string.article_filter_all') },
      ...topics.sort().map((value: string): SelectOption => { return { value: value }; })];
    this.filteredArticles = this.articles.filter((article: SavedArticle): boolean => {
      if (this.selectedTag.length > 0 && !article.tags.includes(this.selectedTag)) {
        return false;
      }
      if (this.selectedTopic.length > 0 && !(article.topicNames ?? []).includes(this.selectedTopic)) {
        return false;
      }
      if (this.filter === 1) {
        return !article.isArchived && isReadableSavedArticle(article);
      }
      if (this.filter === 2) {
        return article.isArchived;
      }
      if (this.filter === 3) {
        return !isReadableSavedArticle(article);
      }
      return true;
    });
  }

  @Builder
  private ArticleList() {
    if (this.filteredArticles.length === 0) {
      Column({ space: 12 }) {
        AppIcon({ name: IconName.Reader, glyphSize: 30, color: $r('app.color.text_secondary') })
        Text(this.query.length > 0 || this.filter !== 0 || this.selectedTag.length > 0 || this.selectedTopic.length > 0
          ? $r('app.string.article_no_results') : $r('app.string.article_library_empty'))
          .fontSize(15)
          .fontColor($r('app.color.text_secondary'))
        Text($r('app.string.article_library_hint'))
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .textAlign(TextAlign.Center)
          .padding(24)
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
    } else {
      List({ space: 0 }) {
        ForEach(this.filteredArticles, (article: SavedArticle) => {
          ListItem() {
            this.ArticleRow(article)
          }
        }, (article: SavedArticle): string => article.id)
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
  }

  @Builder
  private ArticleRow(article: SavedArticle) {
    Row({ space: 12 }) {
      AppIcon({
        name: IconName.Reader,
        glyphSize: 18,
        color: article.failure === ArticleSaveFailure.None
          ? $r('app.color.accent')
          : $r('app.color.text_secondary')
      })
      Column({ space: 4 }) {
        Text(article.title)
          .fontSize(16)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(articleStatusLabel(article))
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(displayHost(article.canonicalUrl))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        if (article.isArchived) {
          Text($r('app.string.article_archived'))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
        }
      }
      .layoutWeight(1)
      AppIcon({ name: IconName.ChevronRight, glyphSize: 16, color: $r('app.color.text_secondary') })
    }
    .width('100%')
    .padding({ left: 24, right: 24, top: 14, bottom: 14 })
    .border({ width: { bottom: 1 }, color: $r('app.color.border') })
    .focusable(true)
    .hoverEffect(HoverEffect.Auto)
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.99 })
    .onClick(() => {
      this.annotationsVisible = false;
      this.highlightTarget = '';
      this.onSelect(article.id);
    })
  }

  @Builder
  private ArticleDetail(article: SavedArticle) {
    Column() {
      this.ArticleHeader()
      this.ArticleActions(article)
      Text(articleStatusLabel(article))
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .padding({ left: 20, right: 20, top: 8, bottom: 8 })
      if (!isReadableSavedArticle(article)) {
        Text(article.title)
          .fontSize(20)
          .padding(24)
      } else if (this.showInspector()) {
        Row() {
          this.ArticleReader(article, false)
          this.InspectorPane()
        }
        .width('100%')
        .layoutWeight(1)
      } else {
        this.ArticleReader(article, true)
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private ArticleHeader() {
    Row({ space: 12 }) {
      AppIcon({ name: IconName.ArrowLeft, glyphSize: 21, color: $r('app.color.text_primary') })
        .onClick(() => this.onBackToList())
      Text($r('app.string.article_library'))
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
      if (this.canToggleInspector()) {
        Text(this.inspectorVisible
          ? $r('app.string.article_workbench_hide_inspector')
          : $r('app.string.article_workbench_show_inspector'))
          .fontSize(12)
          .fontColor($r('app.color.accent'))
          .padding(8)
          .borderRadius(8)
          .backgroundColor($r('app.color.surface_subtle'))
          .focusable(true)
          .hoverEffect(HoverEffect.Auto)
          .id('article-workbench-inspector-toggle')
          .onClick(() => this.onInspectorVisibilityChange(!this.inspectorVisible))
      }
      Text(this.annotationsVisible ? $r('app.string.article_read') : $r('app.string.article_annotations'))
        .fontSize(12)
        .fontColor($r('app.color.accent'))
        .padding(8)
        .borderRadius(8)
        .backgroundColor($r('app.color.surface_subtle'))
        .focusable(true)
        .hoverEffect(HoverEffect.Auto)
        .onClick(() => { this.annotationsVisible = !this.annotationsVisible; })
    }
    .width('100%')
    .height(56 + Math.max(0, this.topInset))
    .padding({ top: Math.max(0, this.topInset), left: 20, right: 20 })
    .alignItems(VerticalAlign.Center)
    .border({ width: { bottom: 1 }, color: $r('app.color.border') })
  }

  @Builder
  private ArticleActions(article: SavedArticle) {
    Scroll() {
      Row({ space: 8 }) {
        Button($r('app.string.article_open_source'))
          .fontSize(12)
          .height(36)
          .onClick(() => this.onOpenSource(article))
        Button($r('app.string.article_retry'))
          .fontSize(12)
          .height(36)
          .onClick(() => this.onRetry(article))
        if (isReadableSavedArticle(article)) {
          Button(article.isArchived ? $r('app.string.article_unarchive') : $r('app.string.article_archive'))
            .fontSize(12)
            .height(36)
            .onClick(() => this.onArchive(!article.isArchived))
          Button($r('app.string.article_export_markdown'))
            .fontSize(12)
            .height(36)
            .onClick(() => this.onExport(ArticleExportFormat.Markdown))
          Button($r('app.string.article_export_html'))
            .fontSize(12)
            .height(36)
            .onClick(() => this.onExport(ArticleExportFormat.StandaloneHtml))
        }
        Button($r('app.string.article_delete'))
          .fontSize(12)
          .height(36)
          .onClick(() => this.onDelete(article))
      }
      .padding({ left: 16, right: 16, top: 4, bottom: 4 })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .width('100%')
  }

  @Builder
  private ArticleReader(article: SavedArticle, showInlineInspector: boolean) {
    Column() {
      if (this.isLoading) {
        LoadingProgress().width(28).height(28)
      } else if (showInlineInspector && this.annotationsVisible) {
        Scroll() { this.AnnotationPanel() }.width('100%').layoutWeight(1).padding(20)
      } else {
        OfflineArticleReader({
          html: this.html,
          highlights: this.highlights,
          targetId: this.highlightTarget,
          initialOffset: this.readingOffset,
          onSelection: this.onSelectedHighlight,
          onScroll: (offset: number): void => { this.readingOffset = offset; this.onReadingScroll(offset); },
          onOpenLink: this.onOpenLink
        }).layoutWeight(1)
      }
    }.width('100%').layoutWeight(1)
  }

  @Builder
  private InspectorPane() {
    Scroll() {
      Column({ space: 12 }) {
        Text($r('app.string.article_workbench_inspector'))
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
        this.AnnotationPanel()
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 20, bottom: 36 })
    }
    .width(ARTICLE_WORKBENCH_INSPECTOR_WIDTH)
    .height('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .border({ width: { left: 1 }, color: $r('app.color.border') })
  }

  @Builder
  private AnnotationPanel() {
    ArticleAnnotationPanel({
      notes: this.notes,
      topics: this.topics,
      tags: this.selectedArticle?.tags ?? [],
      highlights: this.highlights,
      onAddNote: this.onAddNote,
      onAddTopic: this.onAddTopic,
      onUpdateTags: this.onUpdateTags,
      onAddHighlight: this.onAddHighlight,
      onEditNote: this.onEditNote,
      onDeleteNote: this.onDeleteNote,
      onDeleteHighlight: this.onDeleteHighlight,
      onRemoveTopic: this.onRemoveTopic,
      onLocateHighlight: (id: string): void => {
        this.highlightTarget = id;
        this.annotationsVisible = false;
      }
    })
      .margin({ top: 18 })
  }

  private showInspector(): boolean {
    return shouldShowArticleInspector(this.layoutClass, this.inspectorVisible);
  }

  private canToggleInspector(): boolean {
    return articleWorkbenchMode(this.layoutClass) === ArticleWorkbenchMode.SwitchableInspector;
  }

}
