import { webview } from '@kit.ArkWeb';
import { ArticleHighlight } from '../models/ArticleLibraryModels';
import { decodeArticleScriptResult } from '../models/ArticleCaptureModels';
import { ARTICLE_SELECTION_SCRIPT, articleHighlightScript } from '../services/ArticleReaderScripts';
import { Logger } from '../utils/Logger';

interface ArticleSelection {
  quote: string;
  text: string;
}

@Component
export struct OfflineArticleReader {
  @Prop @Watch('loadDocument') html: string = '';
  @Prop @Watch('renderHighlights') highlights: ArticleHighlight[] = [];
  @Prop @Watch('renderHighlights') targetId: string = '';
  @Prop initialOffset: number = 0;
  @State private busy: boolean = false;
  private controller: webview.WebviewController = new webview.WebviewController();
  private attached: boolean = false;
  private ready: boolean = false;
  onSelection: (quote: string, text: string) => Promise<void> = async (): Promise<void> => {};
  onScroll: (offset: number) => void = (): void => {};
  onOpenLink: (url: string) => void = (): void => {};

  build() {
    Column() {
      Button($r('app.string.article_add_highlight'))
        .fontSize(13)
        .height(40)
        .margin({ top: 4, bottom: 4 })
        .enabled(!this.busy)
        .onClick((): void => { void this.saveSelection(); })
      Web({ src: 'about:blank', controller: this.controller, incognitoMode: true })
        .javaScriptAccess(true)
        .fileAccess(false)
        .domStorageAccess(false)
        .databaseAccess(false)
        .blockNetwork(true)
        .onControllerAttached((): void => { this.attached = true; this.loadDocument(); })
        .onPageEnd((): void => { void this.documentReady(); })
        .onLoadIntercept((event: OnLoadInterceptEvent): boolean => {
          const url: string = event.data.getRequestUrl();
          if (url === 'about:blank' || url === 'https://offline.invalid/') {
            return false;
          }
          if (event.data.isMainFrame() && /^https?:\/\//i.test(url)) {
            this.onOpenLink(url);
          }
          return true;
        })
        .onScroll((event: OnScrollEvent): void => this.onScroll(event.yOffset))
        .width('100%')
        .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
  }

  private loadDocument(): void {
    if (!this.attached || this.html.length === 0) {
      return;
    }
    this.ready = false;
    try {
      this.controller.loadData(this.html, 'text/html', 'UTF-8', 'https://offline.invalid/');
    } catch (error) {
      Logger.warn('OfflineArticleReader', 'Offline document could not be loaded');
      this.toast($r('app.string.article_library_unavailable'));
    }
  }

  private async documentReady(): Promise<void> {
    this.ready = true;
    try {
      await this.controller.runJavaScript(articleHighlightScript(this.highlights, this.targetId));
      if (this.targetId.length === 0) {
        await this.controller.runJavaScript(`window.scrollTo(0, ${Math.max(0, this.initialOffset)})`);
      }
    } catch (error) {
      Logger.warn('OfflineArticleReader', 'Offline reading position could not be restored');
    }
  }

  private renderHighlights(): void {
    if (!this.ready) {
      return;
    }
    this.controller.runJavaScript(articleHighlightScript(this.highlights, this.targetId))
      .then((result: string): void => {
        if (result === 'false' && this.targetId.length > 0) {
          this.toast($r('app.string.article_highlight_needs_relocation'));
        }
      }).catch((): void => this.toast($r('app.string.article_library_unavailable')));
  }

  private async saveSelection(): Promise<void> {
    this.busy = true;
    try {
      const raw: string = await this.controller.runJavaScript(ARTICLE_SELECTION_SCRIPT);
      const selection: ArticleSelection = JSON.parse(decodeArticleScriptResult(raw)) as ArticleSelection;
      if (selection.quote.trim().length === 0) {
        this.toast($r('app.string.article_select_text'));
      } else {
        await this.onSelection(selection.quote, selection.text);
        this.toast($r('app.string.article_highlight_added'));
      }
    } catch (error) {
      Logger.warn('OfflineArticleReader', 'Selected highlight could not be saved');
      this.toast($r('app.string.article_storage_failed'));
    } finally {
      this.busy = false;
    }
  }

  private toast(message: Resource): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message });
    } catch (error) {
      Logger.warn('OfflineArticleReader', 'Reader feedback could not be displayed');
    }
  }
}
