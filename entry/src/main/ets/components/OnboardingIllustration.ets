import { AppIcon, IconName } from './AppIcon';

const ILLUSTRATION_WIDE_HEIGHT: number = 420;
const ILLUSTRATION_COMPACT_HEIGHT: number = 236;
const BROWSER_CARD_MAX_WIDTH: number = 540;

@Component
export struct OnboardingIllustration {
  @Prop page: number = 0;
  @Prop compact: boolean = false;

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Row()
        .width(this.compact ? 180 : 340)
        .height(this.compact ? 180 : 340)
        .borderRadius(this.compact ? 90 : 170)
        .backgroundColor($r('app.color.surface_subtle'))

      Column() {
        if (this.page === 0) {
          this.GesturePreview()
        } else if (this.page === 1) {
          this.PrivacyPreview()
        } else {
          this.ReaderPreview()
        }
      }
      .width(this.compact ? '94%' : '86%')
      .constraintSize({ maxWidth: BROWSER_CARD_MAX_WIDTH })
    }
    .width('100%')
    .height(this.compact ? ILLUSTRATION_COMPACT_HEIGHT : ILLUSTRATION_WIDE_HEIGHT)
    .borderRadius(this.compact ? 22 : 32)
    .backgroundColor($r('app.color.content_background'))
    .border({ width: 1, color: $r('app.color.border') })
    .shadow({ radius: 24, color: $r('app.color.shadow_soft'), offsetX: 0, offsetY: 10 })
  }

  @Builder
  private GesturePreview() {
    Column() {
      this.BrowserChrome()

      Column({ space: this.compact ? 10 : 16 }) {
        Row({ space: 10 }) {
          AppIcon({ name: IconName.ChevronLeft, glyphSize: 18, color: $r('app.color.accent_strong') })
          Text($r('app.string.onboarding_visual_swipe_tabs'))
            .fontSize(this.compact ? 12 : 15)
            .fontColor($r('app.color.text_primary'))
          AppIcon({ name: IconName.ChevronRight, glyphSize: 18, color: $r('app.color.accent_strong') })
        }
        .height(this.compact ? 38 : 46)
        .padding({ left: 14, right: 14 })
        .borderRadius(23)
        .backgroundColor($r('app.color.surface_subtle'))

        Row({ space: 8 }) {
          AppIcon({ name: IconName.ChevronUp, glyphSize: 17, color: $r('app.color.accent_strong') })
          Text($r('app.string.onboarding_visual_swipe_tools'))
            .fontSize(this.compact ? 11 : 13)
            .fontColor($r('app.color.text_secondary'))
        }
      }
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .height(this.compact ? 184 : 300)
    .borderRadius(this.compact ? 16 : 22)
    .clip(true)
    .backgroundColor($r('app.color.surface_panel'))
    .border({ width: 1, color: $r('app.color.border') })
  }

  @Builder
  private PrivacyPreview() {
    Column() {
      this.BrowserChrome()

      Column({ space: this.compact ? 10 : 16 }) {
        Row() {
          AppIcon({
            name: IconName.ShieldCheck,
            glyphSize: this.compact ? 38 : 58,
            color: $r('app.color.accent_strong')
          })
        }
        .width(this.compact ? 72 : 104)
        .height(this.compact ? 72 : 104)
        .justifyContent(FlexAlign.Center)
        .borderRadius(this.compact ? 36 : 52)
        .backgroundColor($r('app.color.surface_subtle'))

        Text($r('app.string.onboarding_visual_blocked'))
          .fontSize(this.compact ? 13 : 17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))

        Row({ space: 6 }) {
          Row().width(7).height(7).borderRadius(4).backgroundColor($r('app.color.accent_strong'))
          Text($r('app.string.onboarding_visual_local'))
            .fontSize(this.compact ? 11 : 13)
            .fontColor($r('app.color.text_secondary'))
        }
      }
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .height(this.compact ? 184 : 300)
    .borderRadius(this.compact ? 16 : 22)
    .clip(true)
    .backgroundColor($r('app.color.surface_panel'))
    .border({ width: 1, color: $r('app.color.border') })
  }

  @Builder
  private ReaderPreview() {
    Row({ space: this.compact ? 10 : 18 }) {
      Column({ space: this.compact ? 8 : 12 }) {
        Text($r('app.string.onboarding_visual_reader_title'))
          .width('100%')
          .fontSize(this.compact ? 14 : 22)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.reader_paper_night'))
          .maxLines(2)

        ForEach([100, 92, 96, 74], (width: number, index: number) => {
          Row()
            .width(`${width}%`)
            .height(this.compact ? 5 : 7)
            .borderRadius(4)
            .backgroundColor(index === 0 ? $r('app.color.skeleton_strong') : $r('app.color.skeleton_weak'))
        }, (width: number, index: number) => `reader-line-${index}-${width}`)
      }
      .layoutWeight(1)
      .height(this.compact ? 140 : 230)
      .padding(this.compact ? 16 : 28)
      .justifyContent(FlexAlign.Center)
      .borderRadius(this.compact ? 16 : 22)
      .backgroundColor($r('app.color.reader_paper_sepia'))

      Column({ space: this.compact ? 8 : 12 }) {
        this.ReaderTool(IconName.Reader)
        this.ReaderTool(IconName.LineHeight)
        this.ReaderTool(IconName.Check)
      }
      .width(this.compact ? 50 : 64)
      .padding({ top: this.compact ? 8 : 12, bottom: this.compact ? 8 : 12 })
      .borderRadius(this.compact ? 20 : 26)
      .backgroundColor($r('app.color.surface_panel'))
      .border({ width: 1, color: $r('app.color.border') })
    }
    .width('100%')
    .padding(this.compact ? 12 : 24)
    .borderRadius(this.compact ? 18 : 26)
    .backgroundColor($r('app.color.surface_subtle'))
  }

  @Builder
  private BrowserChrome() {
    Column({ space: this.compact ? 6 : 9 }) {
      Row({ space: 6 }) {
        Row().width(8).height(8).borderRadius(4).backgroundColor($r('app.color.site_tile_fg_2'))
        Row().width(8).height(8).borderRadius(4).backgroundColor($r('app.color.site_tile_fg_4'))
        Row().width(8).height(8).borderRadius(4).backgroundColor($r('app.color.site_tile_fg_3'))
        Row().layoutWeight(1)
        Text($r('app.string.onboarding_visual_tab_count'))
          .fontSize(this.compact ? 10 : 12)
          .fontColor($r('app.color.text_secondary'))
      }

      Row({ space: 8 }) {
        AppIcon({ name: IconName.Search, glyphSize: 14, color: $r('app.color.text_secondary') })
        Text($r('app.string.onboarding_visual_address'))
          .fontSize(this.compact ? 10 : 12)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      .height(this.compact ? 28 : 34)
      .padding({ left: 10, right: 10 })
      .borderRadius(17)
      .backgroundColor($r('app.color.surface_subtle'))
    }
    .width('100%')
    .padding({
      top: this.compact ? 10 : 14,
      left: this.compact ? 12 : 16,
      right: this.compact ? 12 : 16,
      bottom: this.compact ? 8 : 12
    })
    .border({ width: { bottom: 1 }, color: $r('app.color.border') })
  }

  @Builder
  private ReaderTool(icon: IconName) {
    Row() {
      AppIcon({
        name: icon,
        glyphSize: this.compact ? 17 : 21,
        color: icon === IconName.Reader ? $r('app.color.accent_foreground') : $r('app.color.text_secondary')
      })
    }
    .width(this.compact ? 34 : 42)
    .height(this.compact ? 34 : 42)
    .justifyContent(FlexAlign.Center)
    .borderRadius(this.compact ? 17 : 21)
    .backgroundColor(icon === IconName.Reader ? $r('app.color.accent') : $r('app.color.surface_subtle'))
  }
}
