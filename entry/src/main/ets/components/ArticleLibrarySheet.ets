import { ArticleSaveFailure, isReadableSavedArticle, SavedArticle } from '../models/ArticleLibraryModels';
import { ArticleExportFormat } from '../services/ArticleExportService';
import { displayHost } from '../utils/UrlUtils';
import { AppIcon, IconName } from './AppIcon';

@Component
export struct ArticleLibrarySheet {
  @Prop articles: SavedArticle[] = [];
  @Prop selectedArticle: SavedArticle | undefined = undefined;
  @Prop markdown: string = '';
  @Prop isLoading: boolean = false;
  onDismiss: () => void = (): void => {};
  onSelect: (articleId: string) => void = (_articleId: string): void => {};
  onBackToList: () => void = (): void => {};
  onExport: (format: ArticleExportFormat) => void = (_format: ArticleExportFormat): void => {};

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
      Row({ space: 12 }) {
        AppIcon({ name: IconName.ArrowLeft, glyphSize: 21, color: $r('app.color.text_primary') })
          .onClick(() => this.onBackToList())
        Text($r('app.string.article_library'))
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Text($r('app.string.article_export_markdown'))
          .fontSize(12)
          .fontColor($r('app.color.accent'))
          .padding(8)
          .borderRadius(8)
          .backgroundColor($r('app.color.surface_subtle'))
          .onClick(() => this.onExport(ArticleExportFormat.Markdown))
        Text($r('app.string.article_export_html'))
          .fontSize(12)
          .fontColor($r('app.color.accent'))
          .padding(8)
          .borderRadius(8)
          .backgroundColor($r('app.color.surface_subtle'))
          .onClick(() => this.onExport(ArticleExportFormat.StandaloneHtml))
      }
      .width('100%')
      .height(62)
      .padding({ left: 20, right: 20 })
      .border({ width: { bottom: 1 }, color: $r('app.color.border') })

      Scroll() {
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
          }
        }
        .width('100%')
        .padding({ left: 24, right: 24, top: 24, bottom: 40 })
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
  }
}
