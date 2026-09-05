import { QuickSite, SiteIcon, StartPageBackgroundSource } from '../models/BrowserModels';
import {
  DEFAULT_LANDSCAPE_PRESET_ID,
  DEFAULT_PORTRAIT_PRESET_ID,
  resolvePresetResource
} from '../models/HomeBackgroundPresets';
import { AppIcon, IconName } from './AppIcon';
import { QuickSiteGrid } from './QuickSiteGrid';

@Component
export struct StartPage {
  @Prop quickSites: QuickSite[] = [];
  /** Resolved site icons, keyed by host; a tile without one keeps its letter. */
  @Prop siteIcons: SiteIcon[] = [];
  @Prop quickSitesEnabled: boolean = true;
  @Prop quickSiteLimit: number = 6;
  @Prop backgroundEnabled: boolean = true;
  @Prop backgroundSource: StartPageBackgroundSource = StartPageBackgroundSource.BuiltIn;
  @Prop customBackgroundUri: string = '';
  @Prop presetPortraitId: string = DEFAULT_PORTRAIT_PRESET_ID;
  @Prop presetLandscapeId: string = DEFAULT_LANDSCAPE_PRESET_ID;
  /** Wide chrome already puts a menu at the top-right; the home gear would overlap it. */
  @Prop hidePageSettings: boolean = false;
  @Prop isWide: boolean = false;
  @Prop isLandscape: boolean = false;
  onAddSite: () => void = (): void => {};
  onOpenSite: (url: string) => void = (_url: string): void => {};
  onEditSite: (site: QuickSite) => void = (_site: QuickSite): void => {};
  onRemoveSite: (url: string) => void = (_url: string): void => {};
  onMoveSite: (from: number, to: number) => void = (_from: number, _to: number): void => {};
  onOpenPageSettings: () => void = (): void => {};
  onOpenBackgroundPicker: () => void = (): void => {};

  build() {
    Stack({ alignContent: Alignment.Top }) {
      if (this.backgroundEnabled) {
        Image(this.imageSource())
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .syncLoad(true)
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor($r('app.color.home_scrim'))
      }

      Column() {
        if (this.quickSitesEnabled) {
          QuickSiteGrid({
            quickSites: this.quickSites,
            siteIcons: this.siteIcons,
            quickSiteLimit: this.quickSiteLimit,
            backgroundEnabled: this.backgroundEnabled,
            isWide: this.isWide,
            isLandscape: this.isLandscape,
            onAddSite: this.onAddSite,
            onOpenSite: this.onOpenSite,
            onEditSite: this.onEditSite,
            onRemoveSite: this.onRemoveSite,
            onMoveSite: this.onMoveSite
          })
        }
      }
      .width('100%')
      .height('100%')
      .padding({ top: 96, bottom: 112 })
      .justifyContent(FlexAlign.Center)

      if (!this.hidePageSettings) {
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
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.backgroundEnabled
      ? $r('app.color.home_background_fallback')
      : $r('app.color.page_background'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .gesture(
      LongPressGesture({ repeat: false, duration: 500 })
        .onAction(() => this.onOpenBackgroundPicker())
    )
  }

  private imageSource(): ResourceStr {
    if (this.backgroundSource === StartPageBackgroundSource.Custom && this.customBackgroundUri.length > 0) {
      return this.customBackgroundUri;
    }
    return resolvePresetResource(
      this.isLandscape,
      this.isLandscape ? this.presetLandscapeId : this.presetPortraitId
    );
  }

  private primaryColor(): ResourceColor {
    return this.backgroundEnabled ? $r('app.color.home_text_primary') : $r('app.color.text_primary');
  }
}
