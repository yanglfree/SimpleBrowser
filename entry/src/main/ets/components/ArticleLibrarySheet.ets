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
  articleReaderMaxWidth,
  articleWorkbenchMode,
  shouldShowArticleInspector
} from '../models/ArticleWorkbenchModels';
import { BrowserLayoutClass } from '../models/WindowMetrics';
import { ArticleExportFormat } from '../services/ArticleExportService';
import { displayHost } from '../utils/UrlUtils';
import { ArticleAnnotationPanel } from './ArticleAnnotationPanel';
import { AppIcon, IconName } from './AppIcon';

@Component
export struct ArticleLibrarySheet {
  @Prop articles: SavedArticle[] = [];
  @Prop selectedArticle: SavedArticle | undefined = undefined;
  @Prop markdown: string = '';
  @Prop isLoading: boolean = false;
  @Prop notes: ArticleNote[] = [];
  @Prop topics: Topic[] = [];
  @Prop highlights: ArticleHighlight[] = [];
  @Prop layoutClass: BrowserLayoutClass = BrowserLayoutClass.Compact;
  @Prop availableWidthVp: number = 0;
  @Prop inspectorVisible: boolean = false;
  @Prop initialReadingScrollOffset: number = 0;
  @State private query: string = '';
  private articleScroller: Scroller = new Scroller();
  private readingScrollOffset: number = 0;
  onDismiss: () => void = (): void => {};
  onSelect: (articleId: string) => void = (_articleId: string): void => {};
  onBackToList: () => void = (): void => {};
  onExport: (format: ArticleExportFormat) => void = (_format: ArticleExportFormat): void => {};
  onSearch: (query: string) => void = (_query: string): void => {};
  onAddNote: (body: string) => void = (_body: string): void => {};
  onAddTopic: (name: string) => void = (_name: string): void => {};
  onUpdateTags: (tags: string[]) => void = (_tags: string[]): void => {};
  onArchive: (isArchived: boolean) => void = (_isArchived: boolean): void => {};
  onAddHighlight: (quote: string) => void = (_quote: string): void => {};
  onInspectorVisibilityChange: (visible: boolean) => void = (_visible: boolean): void => {};
  onReadingScroll: (offset: number) => void = (_offset: number): void => {};

  aboutToAppear(): void {
    this.readingScrollOffset = this.initialReadingScrollOffset;
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
      Text(`${this.articles.length}`)
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .fontFeature('"tnum" 1')
    }
    .width('100%')
    .height(62)
    .padding({ left: 24, right: 24 })
    .border({ width: { bottom: 1 }, color: $r('app.color.border') })

    TextInput({ text: this.query, placeholder: $r('app.string.article_search_placeholder') })
      .width('100%')
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
  }

  @Builder
  private ArticleList() {
    if (this.articles.length === 0) {
      Column({ space: 12 }) {
        AppIcon({ name: IconName.Reader, glyphSize: 30, color: $r('app.color.text_secondary') })
        Text($r('app.string.article_library_empty'))
          .fontSize(15)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
    } else {
      List({ space: 0 }) {
        ForEach(this.articles, (article: SavedArticle) => {
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
        Text(article.failure === ArticleSaveFailure.None ? article.excerpt : article.failureMessage)
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
    .opacity(isReadableSavedArticle(article) ? 1 : 0.55)
    .focusable(isReadableSavedArticle(article))
    .hoverEffect(isReadableSavedArticle(article) ? HoverEffect.Auto : HoverEffect.None)
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.99 })
    .onClick(() => {
      if (isReadableSavedArticle(article)) {
        this.onSelect(article.id);
      }
    })
  }

  @Builder
  private ArticleDetail(article: SavedArticle) {
    Column() {
      this.ArticleHeader()
      if (this.showInspector()) {
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
      Text($r('app.string.article_export_markdown'))
        .fontSize(12)
        .fontColor($r('app.color.accent'))
        .padding(8)
        .borderRadius(8)
        .backgroundColor($r('app.color.surface_subtle'))
        .focusable(true)
        .hoverEffect(HoverEffect.Auto)
        .onClick(() => this.onExport(ArticleExportFormat.Markdown))
      Text($r('app.string.article_export_html'))
        .fontSize(12)
        .fontColor($r('app.color.accent'))
        .padding(8)
        .borderRadius(8)
        .backgroundColor($r('app.color.surface_subtle'))
        .focusable(true)
        .hoverEffect(HoverEffect.Auto)
        .onClick(() => this.onExport(ArticleExportFormat.StandaloneHtml))
      Text(this.selectedArticle?.isArchived === true
        ? $r('app.string.article_unarchive') : $r('app.string.article_archive'))
        .fontSize(12)
        .fontColor($r('app.color.accent'))
        .padding(8)
        .borderRadius(8)
        .backgroundColor($r('app.color.surface_subtle'))
        .focusable(true)
        .hoverEffect(HoverEffect.Auto)
        .onClick(() => this.onArchive(this.selectedArticle?.isArchived !== true))
    }
    .width('100%')
    .height(62)
    .padding({ left: 20, right: 20 })
    .border({ width: { bottom: 1 }, color: $r('app.color.border') })
  }

  @Builder
  private ArticleReader(article: SavedArticle, showInlineInspector: boolean) {
    Scroll(this.articleScroller) {
      Column() {
        Column({ space: 12 }) {
          Text(article.title)
            .fontSize(26)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
          Text(displayHost(article.canonicalUrl))
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
          if (article.author.length > 0) {
            Text(article.author)
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
          }
          if (this.isLoading) {
            LoadingProgress()
              .width(28)
              .height(28)
              .margin({ top: 28 })
          } else {
            Text(this.markdown)
              .fontSize(17)
              .lineHeight(30)
              .fontColor($r('app.color.text_primary'))
              .width('100%')
              .textAlign(TextAlign.Start)
              .copyOption(CopyOptions.LocalDevice)
              .textSelectable(TextSelectableMode.SELECTABLE_FOCUSABLE)
            if (showInlineInspector) {
              this.AnnotationPanel()
            }
          }
        }
        .width('100%')
        .constraintSize({ maxWidth: this.readerMaxWidth() })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .padding({ left: 24, right: 24, top: 24, bottom: 40 })
      .onAreaChange((_old: Area, _current: Area): void => this.restoreReadingScrollOffset())
    }
    .layoutWeight(1)
    .width('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .onDidScroll((): void => {
      this.readingScrollOffset = Math.max(0, this.articleScroller.currentOffset().yOffset);
      this.onReadingScroll(this.readingScrollOffset);
    })
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
      onAddHighlight: this.onAddHighlight
    })
      .margin({ top: 18 })
  }

  private showInspector(): boolean {
    return shouldShowArticleInspector(this.layoutClass, this.inspectorVisible);
  }

  private canToggleInspector(): boolean {
    return articleWorkbenchMode(this.layoutClass) === ArticleWorkbenchMode.SwitchableInspector;
  }

  private readerMaxWidth(): number {
    return articleReaderMaxWidth(this.availableWidthVp, this.showInspector());
  }

  private restoreReadingScrollOffset(): void {
    if (this.readingScrollOffset <= 0) {
      return;
    }
    this.articleScroller.scrollTo({ xOffset: 0, yOffset: this.readingScrollOffset, animation: false });
  }
}
