import { BrowserSettings, SearchEngine } from '../models/BrowserModels';
import { AppIcon, IconName } from './AppIcon';

const ONBOARDING_PAGE_COUNT: number = 3;

@Component
export struct OnboardingSheet {
  @Link settings: BrowserSettings;
  @State private page: number = 0;
  onSearchEngineChange: (engine: SearchEngine) => void = (_engine: SearchEngine): void => {};
  onFinish: () => void = (): void => {};
  onSkip: () => void = (): void => {};

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.page_background'))

      Column({ space: 20 }) {
        Row() {
          Text($r('app.string.onboarding_title'))
            .fontSize(24)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
          Text($r('app.string.onboarding_skip'))
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .onClick(() => this.onSkip())
        }
        .width('100%')

        Column({ space: 16 }) {
          this.PageIcon()
          Text(this.pageTitle())
            .fontSize(22)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Text(this.pageMessage())
            .width('100%')
            .fontSize(15)
            .fontColor($r('app.color.text_secondary'))
            .lineHeight(24)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)

        if (this.page === 2) {
          this.SearchEnginePicker()
        }

          Row({ space: 12 }) {
          Row() {
            AppIcon({ name: IconName.ChevronLeft, glyphSize: 20, color: $r('app.color.text_primary') })
          }
          .width(44)
          .height(44)
          .justifyContent(FlexAlign.Center)
          .visibility(this.page > 0 ? Visibility.Visible : Visibility.Hidden)
          .onClick(() => this.page = Math.max(0, this.page - 1))
          .borderRadius(22)
          .backgroundColor($r('app.color.surface_subtle'))
          .layoutWeight(1)

          Text(this.page === ONBOARDING_PAGE_COUNT - 1
            ? $r('app.string.onboarding_start')
            : $r('app.string.onboarding_next'))
            .height(44)
            .layoutWeight(3)
            .textAlign(TextAlign.Center)
            .fontSize(15)
            .fontColor($r('app.color.surface_panel'))
            .backgroundColor($r('app.color.accent'))
            .borderRadius(22)
            .onClick(() => this.next())
        }
        .width('100%')

        Row({ space: 6 }) {
          ForEach(this.pageDots(), (active: boolean, index: number) => {
            Row()
              .width(active ? 22 : 7)
              .height(7)
              .borderRadius(4)
              .backgroundColor(active ? $r('app.color.accent') : $r('app.color.border'))
          }, (active: boolean, index: number) => `onboarding-dot-${index}-${active}`)
        }
        .justifyContent(FlexAlign.Center)
      }
      .width('100%')
      .height('100%')
      .padding({ top: 28, left: 28, right: 28, bottom: 36 })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private PageIcon() {
    Row() {
      AppIcon({
        name: this.page === 0 ? IconName.Tabs : this.page === 1 ? IconName.ShieldCheck : IconName.Reader,
        glyphSize: 36,
        color: $r('app.color.accent')
      })
    }
    .width(76)
    .height(76)
    .justifyContent(FlexAlign.Center)
    .borderRadius(38)
    .backgroundColor($r('app.color.surface_subtle'))
  }

  @Builder
  private SearchEnginePicker() {
    Column({ space: 8 }) {
      Text($r('app.string.onboarding_search_engine'))
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      Row({ space: 8 }) {
        this.EngineButton(SearchEngine.Bing, $r('app.string.engine_bing'))
        this.EngineButton(SearchEngine.Baidu, $r('app.string.engine_baidu'))
        this.EngineButton(SearchEngine.Google, $r('app.string.engine_google'))
        this.EngineButton(SearchEngine.DuckDuckGo, $r('app.string.engine_duckduckgo'))
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  private EngineButton(engine: SearchEngine, label: Resource) {
    Text(label)
      .height(44)
      .layoutWeight(1)
      .textAlign(TextAlign.Center)
      .fontSize(12)
      .fontColor(this.settings.searchEngine === engine ? $r('app.color.surface_panel') : $r('app.color.text_primary'))
      .backgroundColor(this.settings.searchEngine === engine ? $r('app.color.accent') : $r('app.color.surface_subtle'))
      .borderRadius(12)
      .onClick(() => this.onSearchEngineChange(engine))
  }

  private next(): void {
    if (this.page >= ONBOARDING_PAGE_COUNT - 1) {
      this.onFinish();
      return;
    }
    this.page += 1;
  }

  private pageTitle(): Resource {
    if (this.page === 0) {
      return $r('app.string.onboarding_gesture_title');
    }
    if (this.page === 1) {
      return $r('app.string.onboarding_privacy_title');
    }
    return $r('app.string.onboarding_reader_title');
  }

  private pageMessage(): Resource {
    if (this.page === 0) {
      return $r('app.string.onboarding_gesture_message');
    }
    if (this.page === 1) {
      return $r('app.string.onboarding_privacy_message');
    }
    return $r('app.string.onboarding_reader_message');
  }

  private pageDots(): boolean[] {
    return [this.page === 0, this.page === 1, this.page === 2];
  }
}
