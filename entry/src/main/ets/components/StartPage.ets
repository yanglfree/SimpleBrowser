import { QuickSite } from '../models/BrowserModels';
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

@Component
export struct StartPage {
  @Prop quickSites: QuickSite[] = [];
  @Prop quickSitesEnabled: boolean = true;
  @Prop backgroundEnabled: boolean = true;
  onOpenAddress: () => void = (): void => {};
  onOpenSite: (url: string) => void = (_url: string): void => {};
  onRemoveSite: (url: string) => void = (_url: string): void => {};
  onOpenPageSettings: () => void = (): void => {};

  build() {
    Stack({ alignContent: Alignment.Top }) {
      if (this.backgroundEnabled) {
        Image($r('app.media.home_background'))
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor($r('app.color.home_scrim'))
      }

      Column() {
        Blank()
        if (this.quickSitesEnabled) {
          this.SiteGrid()
        }
      }
      .width('100%')
      .height('100%')

      Row() {
        Blank()
        Column() {
          AppIcon({
            name: IconName.Sliders,
            glyphSize: 32,
            color: this.primaryColor(),
            strokeWidth: 1.8
          })
        }
        .width(48)
        .height(48)
        .justifyContent(FlexAlign.Center)
        .onClick(() => this.onOpenPageSettings())
      }
      .width('100%')
      .padding({ top: 50, left: 24, right: 18 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  private SiteGrid() {
    Flex({ wrap: FlexWrap.Wrap }) {
      ForEach(this.quickSites, (site: QuickSite) => {
        Column({ space: 8 }) {
          Text(site.badge)
            .width(58)
            .height(58)
            .borderRadius(17)
            .backgroundColor(tileColor(TILE_BACKGROUNDS, site.colorIndex))
            .fontColor(tileColor(TILE_FOREGROUNDS, site.colorIndex))
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .textAlign(TextAlign.Center)

          Text(site.title)
            .width('100%')
            .fontSize(12.5)
            .fontColor(this.primaryColor())
            .textAlign(TextAlign.Center)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('25%')
        .margin({ bottom: 22 })
        .onClick(() => this.onOpenSite(site.url))
        .gesture(
          LongPressGesture({ repeat: false, duration: 450 })
            .onAction(() => this.onRemoveSite(site.url))
        )
      }, (site: QuickSite) => site.url)

      Column({ space: 8 }) {
        Column() {
          AppIcon({ name: IconName.Plus, glyphSize: 36, color: this.primaryColor(), strokeWidth: 1.8 })
        }
        .width(58)
        .height(58)
        .justifyContent(FlexAlign.Center)
        .borderRadius(17)
        .backgroundColor(this.backgroundEnabled
          ? $r('app.color.home_tile_background')
          : $r('app.color.surface_subtle'))

        Text($r('app.string.add_shortcut'))
          .width('100%')
          .fontSize(12.5)
          .fontColor(this.primaryColor())
          .textAlign(TextAlign.Center)
      }
      .width('25%')
      .margin({ bottom: 22 })
      .onClick(() => this.onOpenAddress())
    }
    .width('100%')
    .padding({ left: 20, right: 20, bottom: 144 })
  }

  private primaryColor(): ResourceColor {
    return this.backgroundEnabled ? $r('app.color.home_text_primary') : $r('app.color.text_primary');
  }
}
