import { BrowserSettings, SearchEngine } from '../models/BrowserModels';
import { AppIcon, IconName } from './AppIcon';
import { OnboardingIllustration } from './OnboardingIllustration';

const ONBOARDING_PAGE_COUNT: number = 3;
const WIDE_CONTENT_MAX_WIDTH: number = 1180;
const WIDE_COPY_WIDTH: number = 460;
const COMPACT_CONTENT_MAX_WIDTH: number = 520;

@Component
export struct OnboardingSheet {
  @Link settings: BrowserSettings;
  @State private page: number = 0;
  @Prop isWide: boolean = false;
  @Prop isHeightConstrained: boolean = false;
  onSearchEngineChange: (engine: SearchEngine) => void = (_engine: SearchEngine): void => {};
  onFinish: () => void = (): void => {};
  onSkip: () => void = (): void => {};

  build() {
    Column({ space: this.isWide ? 24 : 14 }) {
      this.Header()

      if (this.isWide) {
        this.WideContent()
      } else {
        this.CompactContent()
      }
    }
    .width('100%')
    .height('100%')
    .padding({
      top: this.isWide ? 32 : 24,
      left: this.isWide ? 48 : 24,
      right: this.isWide ? 48 : 24,
      bottom: this.isWide ? 32 : 28
    })
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  private Header() {
    Row() {
      Row({ space: 10 }) {
        Row() {
          AppIcon({ name: IconName.Search, glyphSize: 18, color: $r('app.color.accent_foreground') })
        }
        .width(36)
        .height(36)
        .justifyContent(FlexAlign.Center)
        .borderRadius(12)
        .backgroundColor($r('app.color.accent'))

        Text($r('app.string.onboarding_title'))
          .fontSize(this.isWide ? 20 : 18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
      }
      .layoutWeight(1)

      Text($r('app.string.onboarding_skip'))
        .id('onboarding-skip')
        .height(40)
        .padding({ left: 16, right: 16 })
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .onClick(() => this.onSkip())
    }
    .width('100%')
    .constraintSize({ maxWidth: WIDE_CONTENT_MAX_WIDTH })
  }

  @Builder
  private WideContent() {
    Column({ space: 24 }) {
      Row({ space: 56 }) {
        Column({ space: 18 }) {
          this.StepLabel()
          Text(this.pageTitle())
            .width('100%')
            .fontSize(this.isHeightConstrained ? 30 : 38)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
          Text(this.pageMessage())
            .width('100%')
            .fontSize(17)
            .fontColor($r('app.color.text_secondary'))
            .lineHeight(28)

          if (this.page === 2) {
            this.SearchEnginePicker()
          }
        }
        .width(WIDE_COPY_WIDTH)
        .justifyContent(FlexAlign.Center)

        OnboardingIllustration({ page: this.page, compact: this.isHeightConstrained })
          .layoutWeight(1)
      }
      .width('100%')
      .layoutWeight(1)
      .alignItems(VerticalAlign.Center)
      .translate({ y: -40 })

      Row() {
        this.PageDots()
        Row().layoutWeight(1)
        this.NavigationButtons()
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .layoutWeight(1)
    .constraintSize({ maxWidth: WIDE_CONTENT_MAX_WIDTH })
  }

  @Builder
  private CompactContent() {
    Column({ space: 16 }) {
      if (this.isHeightConstrained) {
        Scroll() {
          this.CompactMainContent()
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      } else {
        Column() {
          this.CompactMainContent()
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      }

      this.NavigationButtons()
      this.PageDots()
    }
    .width('100%')
    .layoutWeight(1)
    .constraintSize({ maxWidth: COMPACT_CONTENT_MAX_WIDTH })
  }

  @Builder
  private CompactMainContent() {
    Column({ space: 14 }) {
      OnboardingIllustration({ page: this.page, compact: true })

      Column({ space: 10 }) {
        this.StepLabel()
        Text(this.pageTitle())
          .width('100%')
          .fontSize(26)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Text(this.pageMessage())
          .width('100%')
          .fontSize(15)
          .fontColor($r('app.color.text_secondary'))
          .lineHeight(23)
      }
      .width('100%')

      if (this.page === 2) {
        this.SearchEnginePicker()
      }
    }
    .width('100%')
    .padding({ top: 12, bottom: 12 })
  }

  @Builder
  private StepLabel() {
    Text(this.page === 0
      ? $r('app.string.onboarding_step_gestures')
      : this.page === 1
        ? $r('app.string.onboarding_step_privacy')
        : $r('app.string.onboarding_step_reading'))
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.accent_strong'))
  }

  @Builder
  private NavigationButtons() {
    Row({ space: 12 }) {
      if (this.page > 0) {
        Row() {
          AppIcon({ name: IconName.ChevronLeft, glyphSize: 20, color: $r('app.color.text_primary') })
        }
        .id('onboarding-back')
        .width(48)
        .height(48)
        .justifyContent(FlexAlign.Center)
        .onClick(() => this.page = Math.max(0, this.page - 1))
        .borderRadius(24)
        .backgroundColor($r('app.color.surface_subtle'))
      }

      Text(this.page === ONBOARDING_PAGE_COUNT - 1
        ? $r('app.string.onboarding_start')
        : $r('app.string.onboarding_next'))
        .id('onboarding-primary-action')
        .width(this.isWide ? 176 : '100%')
        .height(48)
        .layoutWeight(this.isWide ? 0 : 1)
        .textAlign(TextAlign.Center)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.accent_foreground'))
        .backgroundColor($r('app.color.accent'))
        .borderRadius(24)
        .onClick(() => this.next())
    }
    .width(this.isWide ? 236 : '100%')
  }

  @Builder
  private PageDots() {
    Row({ space: 7 }) {
      ForEach(this.pageDots(), (active: boolean, index: number) => {
        Row()
          .width(active ? 26 : 8)
          .height(8)
          .borderRadius(4)
          .backgroundColor(active ? $r('app.color.accent') : $r('app.color.border'))
      }, (active: boolean, index: number) => `onboarding-dot-${index}-${active}`)
    }
    .id('onboarding-page-indicator')
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
    .constraintSize({ maxWidth: WIDE_COPY_WIDTH })
  }

  @Builder
  private EngineButton(engine: SearchEngine, label: Resource) {
    Text(label)
      .height(44)
      .layoutWeight(1)
      .textAlign(TextAlign.Center)
      .fontSize(12)
      .fontColor(this.settings.searchEngine === engine
        ? $r('app.color.accent_foreground')
        : $r('app.color.text_primary'))
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
