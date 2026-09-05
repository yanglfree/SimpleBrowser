import { StartPageBackgroundSource } from '../models/BrowserModels';
import {
  DEFAULT_LANDSCAPE_PRESET_ID,
  DEFAULT_PORTRAIT_PRESET_ID,
  getAvailablePresets,
  HomeBackgroundPreset
} from '../models/HomeBackgroundPresets';
import { AppIcon, IconName } from './AppIcon';

const PICKER_THUMBNAIL_SIZE: number = 84;

@Component
export struct HomeBackgroundPicker {
  @Prop backgroundEnabled: boolean = true;
  @Prop source: StartPageBackgroundSource = StartPageBackgroundSource.BuiltIn;
  @Prop customUri: string = '';
  @Prop isLandscape: boolean = false;
  @Prop isSmallScreen: boolean = true;
  @Prop selectedPresetId: string = '';
  @Prop bottomInset: number = 0;
  /** The overlay that hosts this panel already draws its own scrim on wide screens. */
  @Prop scrimProvided: boolean = false;
  onSelectPreset: (presetId: string) => void = (_id: string): void => {};
  onSelectNone: () => void = (): void => {};
  onSelectCustom: () => void = (): void => {};
  onChooseCustom: () => void = (): void => {};
  onDismiss: () => void = (): void => {};

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      if (!this.scrimProvided) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor($r('app.color.home_menu_scrim'))
          .onClick(() => this.onDismiss())
      }

      Column({ space: 16 }) {
        Row() {
          Column({ space: 3 }) {
            Text($r('app.string.home_background_picker_title'))
              .fontSize(20)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.home_text_primary'))
            Text($r('app.string.home_background_picker_hint'))
              .fontSize(13)
              .fontColor($r('app.color.home_text_secondary'))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          AppIcon({ name: IconName.Close, glyphSize: 19, color: $r('app.color.home_text_secondary') })
            .width(40)
            .height(40)
            .onClick(() => this.onDismiss())
        }
        .width('100%')

        Scroll() {
          Row({ space: 14 }) {
            ForEach(
              getAvailablePresets(this.isLandscape, this.isSmallScreen),
              (preset: HomeBackgroundPreset) => {
                this.PresetOption(preset)
              },
              (preset: HomeBackgroundPreset): string => preset.id
            )
            this.NoneOption()
            this.CustomOption()
          }
          .constraintSize({ minWidth: '100%' })
          .justifyContent(FlexAlign.Center)
          .padding({ left: 4, right: 4 })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')

        Text($r('app.string.home_background_choose_photo'))
          .width('100%')
          .height(46)
          .borderRadius(14)
          .backgroundColor($r('app.color.home_panel_subtle'))
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.home_text_primary'))
          .textAlign(TextAlign.Center)
          .onClick(() => this.onChooseCustom())
      }
      .width('94%')
      .constraintSize({ maxWidth: 620 })
      .margin({ bottom: 10 })
      .padding({ top: 22, left: 20, right: 20, bottom: 18 + this.bottomInset })
      .borderRadius(28)
      .backgroundColor($r('app.color.home_menu_background'))
      .backdropBlur(36)
      .shadow({ radius: 28, color: $r('app.color.home_panel_shadow'), offsetY: -8 })
      .transition(TransitionEffect.OPACITY.animation({ duration: 180 })
        .combine(TransitionEffect.translate({ y: 40 })))
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private PresetOption(preset: HomeBackgroundPreset) {
    Column({ space: 8 }) {
      Stack({ alignContent: Alignment.Center }) {
        Image(preset.resource)
          .width(PICKER_THUMBNAIL_SIZE)
          .height(PICKER_THUMBNAIL_SIZE)
          .objectFit(ImageFit.Cover)
          .syncLoad(true)
        if (this.isPresetSelected(preset.id)) {
          this.SelectionBadge()
        }
      }
      .borderRadius(18)
      .clip(true)
      .border({
        width: this.isPresetSelected(preset.id) ? 2 : 1,
        color: this.isPresetSelected(preset.id)
          ? $r('app.color.home_text_primary')
          : $r('app.color.home_panel_border')
      })

      Text(preset.nameRes)
        .fontSize(12.5)
        .fontColor($r('app.color.home_text_primary'))
    }
    .onClick(() => this.onSelectPreset(preset.id))
  }

  @Builder
  private NoneOption() {
    Column({ space: 8 }) {
      Stack({ alignContent: Alignment.Center }) {
        Column()
          .width(PICKER_THUMBNAIL_SIZE)
          .height(PICKER_THUMBNAIL_SIZE)
          .backgroundColor($r('app.color.page_background'))
        if (!this.backgroundEnabled) {
          this.SelectionBadge()
        }
      }
      .borderRadius(18)
      .clip(true)
      .border({
        width: !this.backgroundEnabled ? 2 : 1,
        color: !this.backgroundEnabled
          ? $r('app.color.home_text_primary')
          : $r('app.color.home_panel_border')
      })

      Text($r('app.string.home_background_none'))
        .fontSize(12.5)
        .fontColor($r('app.color.home_text_primary'))
    }
    .onClick(() => this.onSelectNone())
  }

  @Builder
  private CustomOption() {
    Column({ space: 8 }) {
      Stack({ alignContent: Alignment.Center }) {
        if (this.customUri.length > 0) {
          Image(this.customUri)
            .width(PICKER_THUMBNAIL_SIZE)
            .height(PICKER_THUMBNAIL_SIZE)
            .objectFit(ImageFit.Cover)
            .syncLoad(true)
        } else {
          Column() {
            AppIcon({ name: IconName.Plus, glyphSize: 30, color: $r('app.color.home_text_secondary') })
          }
          .width(PICKER_THUMBNAIL_SIZE)
          .height(PICKER_THUMBNAIL_SIZE)
          .justifyContent(FlexAlign.Center)
          .backgroundColor($r('app.color.home_panel_subtle'))
        }
        if (this.isCustomSelected()) {
          this.SelectionBadge()
        }
      }
      .borderRadius(18)
      .clip(true)
      .border({
        width: this.isCustomSelected() ? 2 : 1,
        color: this.isCustomSelected()
          ? $r('app.color.home_text_primary')
          : $r('app.color.home_panel_border')
      })

      Text($r('app.string.home_background_custom'))
        .fontSize(12.5)
        .fontColor($r('app.color.home_text_primary'))
    }
    .onClick(() => {
      if (this.customUri.length > 0) {
        this.onSelectCustom();
      } else {
        this.onChooseCustom();
      }
    })
  }

  @Builder
  private SelectionBadge() {
    Column() {
      AppIcon({ name: IconName.Check, glyphSize: 18, color: $r('app.color.home_menu_background') })
    }
    .width(30)
    .height(30)
    .justifyContent(FlexAlign.Center)
    .borderRadius(15)
    .backgroundColor($r('app.color.home_text_primary'))
  }

  private isPresetSelected(presetId: string): boolean {
    if (!this.backgroundEnabled || this.source !== StartPageBackgroundSource.BuiltIn) {
      return false;
    }
    const defaultId: string = this.isLandscape ? DEFAULT_LANDSCAPE_PRESET_ID : DEFAULT_PORTRAIT_PRESET_ID;
    const activeId: string = (this.selectedPresetId && this.selectedPresetId.length > 0)
      ? this.selectedPresetId
      : defaultId;
    return activeId === presetId;
  }

  private isCustomSelected(): boolean {
    return this.backgroundEnabled && this.source === StartPageBackgroundSource.Custom;
  }
}
