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
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  @Prop isWide: boolean = false;
  @Prop isHeightConstrained: boolean = false;
  onSearchEngineChange: (engine: SearchEngine) => void = (_engine: SearchEngine): void => {};
  onFinish: () => void = (): void => {};
  onSkip: () => void = (): void => {};

  private swiperController: SwiperController = new SwiperController();

  build() {
    Column({ space: this.isWide ? 24 : 16 }) {
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
      top: Math.max(0, this.topInset) + (this.isWide ? 24 : 16),
      left: this.isWide ? 48 : 24,
      right: this.isWide ? 48 : 24,
      bottom: Math.max(0, this.bottomInset) + (this.isWide ? 28 : 20)
    })
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  private Header() {
    Row() {
      Row({ space: 10 }) {
        Row() {
          Image($r('app.media.start_window_icon'))
            .width(30)
            .height(30)
            .objectFit(ImageFit.Contain)
        }
        .width(36)
        .height(36)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .borderRadius(10)
        .backgroundColor($r('app.color.surface_subtle'))

        Column({ space: 2 }) {
          Text($r('app.string.onboarding_title'))
            .fontSize(this.isWide ? 18 : 16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))

          Text($r('app.string.module_desc'))
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
        }
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)

      Text($r('app.string.onboarding_skip'))
        .id('onboarding-skip')
        .height(32)
        .padding({ left: 14, right: 14 })
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_secondary'))
        .backgroundColor($r('app.color.surface_subtle'))
        .borderRadius(16)
        .onClick(() => this.onSkip())
    }
    .width('100%')
    .constraintSize({ maxWidth: WIDE_CONTENT_MAX_WIDTH })
  }

  @Builder
  private WideContent() {
    Column({ space: 24 }) {
      Swiper(this.swiperController) {
        ForEach([0, 1, 2], (index: number) => {
          this.WidePage(index)
        }, (index: number) => `onboarding-wide-slide-${index}`)
      }
      .layoutWeight(1)
      .width('100%')
      .index(this.page)
      .indicator(false)
      .loop(false)
      .duration(280)
      .curve(Curve.EaseOut)
      .onChange((index: number): void => {
        this.page = index;
      })

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
  private WidePage(index: number) {
    Row({ space: 56 }) {
      Column({ space: 18 }) {
        this.StepLabel(index)
        Text(this.pageTitle(index))
          .width('100%')
          .fontSize(this.isHeightConstrained ? 30 : 38)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Text(this.pageMessage(index))
          .width('100%')
          .fontSize(17)
          .fontColor($r('app.color.text_secondary'))
          .lineHeight(28)

        if (index === 2) {
          this.SearchEnginePicker()
        }
      }
      .width(WIDE_COPY_WIDTH)
      .justifyContent(FlexAlign.Center)

      OnboardingIllustration({ page: index, compact: this.isHeightConstrained })
        .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private CompactContent() {
    Column({ space: 16 }) {
      Swiper(this.swiperController) {
        ForEach([0, 1, 2], (index: number) => {
          if (this.isHeightConstrained) {
            Scroll() {
              this.CompactPage(index)
            }
            .width('100%')
            .height('100%')
            .scrollBar(BarState.Off)
          } else {
            Column() {
              this.CompactPage(index)
            }
            .width('100%')
            .height('100%')
            .justifyContent(FlexAlign.Center)
          }
        }, (index: number) => `onboarding-compact-slide-${index}`)
      }
      .layoutWeight(1)
      .width('100%')
      .index(this.page)
      .indicator(false)
      .loop(false)
      .duration(280)
      .curve(Curve.EaseOut)
      .onChange((index: number): void => {
        this.page = index;
      })

      this.PageDots()
      this.NavigationButtons()
    }
    .width('100%')
    .layoutWeight(1)
    .constraintSize({ maxWidth: COMPACT_CONTENT_MAX_WIDTH })
  }

  @Builder
  private CompactPage(index: number) {
    Column({ space: 14 }) {
      OnboardingIllustration({ page: index, compact: true })

      Column({ space: 10 }) {
        this.StepLabel(index)
        Text(this.pageTitle(index))
          .width('100%')
          .fontSize(26)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Text(this.pageMessage(index))
          .width('100%')
          .fontSize(15)
          .fontColor($r('app.color.text_secondary'))
          .lineHeight(23)
      }
      .width('100%')

      if (index === 2) {
        this.SearchEnginePicker()
      }
    }
    .width('100%')
    .padding({ top: 12, bottom: 12 })
  }

  @Builder
  private StepLabel(index: number = this.page) {
    Row() {
      Text(index === 0
        ? $r('app.string.onboarding_step_gestures')
        : index === 1
          ? $r('app.string.onboarding_step_privacy')
          : $r('app.string.onboarding_step_reading'))
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.accent_strong'))
    }
    .padding({ left: 10, right: 10, top: 4, bottom: 4 })
    .backgroundColor($r('app.color.surface_subtle'))
    .borderRadius(12)
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
        .onClick(() => this.prev())
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
    Row({ space: 8 }) {
      ForEach(this.pageDots(), (active: boolean, index: number) => {
        Row()
          .width(active ? 24 : 8)
          .height(8)
          .borderRadius(4)
          .backgroundColor(active ? $r('app.color.accent') : $r('app.color.border'))
          .animation({ duration: 250, curve: Curve.EaseOut })
          .onClick(() => {
            this.page = index;
            this.swiperController.changeIndex(index, true);
          })
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
    this.swiperController.changeIndex(this.page, true);
  }

  private prev(): void {
    if (this.page > 0) {
      this.page -= 1;
      this.swiperController.changeIndex(this.page, true);
    }
  }

  private pageTitle(pageIndex: number = this.page): Resource {
    if (pageIndex === 0) {
      return $r('app.string.onboarding_gesture_title');
    }
    if (pageIndex === 1) {
      return $r('app.string.onboarding_privacy_title');
    }
    return $r('app.string.onboarding_reader_title');
  }

  private pageMessage(pageIndex: number = this.page): Resource {
    if (pageIndex === 0) {
      return $r('app.string.onboarding_gesture_message');
    }
    if (pageIndex === 1) {
      return $r('app.string.onboarding_privacy_message');
    }
    return $r('app.string.onboarding_reader_message');
  }

  private pageDots(): boolean[] {
    return [this.page === 0, this.page === 1, this.page === 2];
  }
}
