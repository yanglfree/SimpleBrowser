import { QuickSite } from '../models/BrowserModels';
import { formatDate, greetingResource, groupNumber } from '../utils/Formatting';
import { AppIcon, IconName } from './AppIcon';

const TILE_BACKGROUNDS: Resource[] = [
  $r('app.color.site_tile_bg_1'),
  $r('app.color.site_tile_bg_2'),
  $r('app.color.site_tile_bg_3'),
  $r('app.color.site_tile_bg_4'),
  $r('app.color.site_tile_bg_5'),
  $r('app.color.site_tile_bg_6')
];

const TILE_FOREGROUNDS: Resource[] = [
  $r('app.color.site_tile_fg_1'),
  $r('app.color.site_tile_fg_2'),
  $r('app.color.site_tile_fg_3'),
  $r('app.color.site_tile_fg_4'),
  $r('app.color.site_tile_fg_5'),
  $r('app.color.site_tile_fg_6')
];

function tileColor(palette: Resource[], index: number): Resource {
  const safe: number = index >= 0 && index < palette.length ? index : 0;
  return palette[safe];
}

/**
 * 1a — start page. No toolbar of any kind: a greeting, one search capsule, the
 * six sites you actually visit, and a single quiet line of blocking statistics.
 */
@Component
export struct StartPage {
  @Prop quickSites: QuickSite[] = [];
  @Prop quickSitesEnabled: boolean = true;
  @Prop weeklyBlocked: number = 0;
  onOpenAddress: () => void = (): void => {};
  onOpenSite: (url: string) => void = (_url: string): void => {};
  onRemoveSite: (url: string) => void = (_url: string): void => {};
  onToggleQuickSites: () => void = (): void => {};
  /**
   * The start page has no capsule, so the statistics line doubles as the way
   * into the global blocking settings — otherwise a fresh launch, which starts
   * here with a single tab, has no route to 设置 at all.
   */
  onOpenStats: () => void = (): void => {};

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Scroll() {
        Column() {
          Text(greetingResource(new Date().getHours()))
            .fontSize(30)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .letterSpacing(0.3)

          Text(formatDate(new Date()))
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 8 })

          this.SearchCapsule()
          if (this.quickSitesEnabled) {
            this.SiteGrid()
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ top: 64, left: 32, right: 32, bottom: 120 })
      }
      .width('100%')
      .height('100%')
      .align(Alignment.TopStart)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)

      this.WeeklyStat()
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  private SearchCapsule() {
    Row({ space: 12 }) {
      AppIcon({ name: IconName.Search, glyphSize: 19, color: $r('app.color.text_secondary') })
      Text($r('app.string.address_placeholder'))
        .fontSize(16)
        .fontColor($r('app.color.text_secondary'))
    }
    .width('100%')
    .height(56)
    .padding({ left: 22, right: 22 })
    .margin({ top: 40 })
    .borderRadius(28)
    .backgroundColor($r('app.color.surface_panel'))
    .border({ width: 1, color: $r('app.color.border') })
    .shadow({ radius: 12, color: $r('app.color.shadow_soft'), offsetX: 0, offsetY: 2 })
    .onClick(() => this.onOpenAddress())
  }

  @Builder
  private SiteGrid() {
    Column() {
      Row() {
        Text($r('app.string.frequent_sites'))
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .layoutWeight(1)
        AppIcon({ name: IconName.Close, glyphSize: 15, color: $r('app.color.text_secondary') })
          .onClick(() => this.onToggleQuickSites())
      }
      .width('100%')

      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.quickSites, (site: QuickSite) => {
          Column({ space: 9 }) {
            Text(site.badge)
              .width(52)
              .height(52)
              .borderRadius(16)
              .backgroundColor(tileColor(TILE_BACKGROUNDS, site.colorIndex))
              .fontColor(tileColor(TILE_FOREGROUNDS, site.colorIndex))
              .fontSize(20)
              .fontWeight(FontWeight.Medium)
              .textAlign(TextAlign.Center)

            Text(site.title)
              .fontSize(12.5)
              .fontColor($r('app.color.text_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('33.33%')
          .margin({ bottom: 30 })
          .onClick(() => this.onOpenSite(site.url))
          .gesture(
            LongPressGesture({ repeat: false, duration: 450 })
              .onAction(() => this.onRemoveSite(site.url))
          )
        }, (site: QuickSite) => site.url)
      }
      .width('100%')
      .margin({ top: 18 })
    }
    .width('100%')
    .margin({ top: 44 })
  }

  @Builder
  private WeeklyStat() {
    Row({ space: 8 }) {
      AppIcon({ name: IconName.Shield, glyphSize: 15, color: $r('app.color.accent') })
      Text() {
        Span($r('app.string.weekly_blocked_prefix'))
        Span(' ')
        Span(groupNumber(this.weeklyBlocked))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Span(' ')
        Span($r('app.string.weekly_blocked_suffix'))
      }
      .fontSize(13)
      .fontColor($r('app.color.text_secondary'))
      .fontFeature('"tnum" 1')
    }
    .margin({ bottom: 70 })
    .onClick(() => this.onOpenStats())
  }
}
