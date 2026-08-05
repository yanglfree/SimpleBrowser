import { APP_VERSION } from '../constants/AppConstants';
import {
  AppearanceMode,
  BrowserSettings,
  RuleStrength,
  SearchEngine,
  cloneSettings,
  defaultBrowserSettings
} from '../models/BrowserModels';
import { AppIcon, IconName } from './AppIcon';
import { AppSwitch } from './AppSwitch';

enum PickerKind {
  None = 0,
  RuleStrength = 1,
  SearchEngine = 2,
  Appearance = 3
}
interface PickerOption {
  label: Resource;
  value: number;
}

const RULE_STRENGTH_LABELS: Resource[] = [
  $r('app.string.rule_strength_standard'),
  $r('app.string.rule_strength_strict')
];

const SEARCH_ENGINE_LABELS: Resource[] = [
  $r('app.string.engine_bing'),
  $r('app.string.engine_baidu'),
  $r('app.string.engine_google'),
  $r('app.string.engine_duckduckgo')
];

const APPEARANCE_LABELS: Resource[] = [
  $r('app.string.appearance_system'),
  $r('app.string.appearance_light'),
  $r('app.string.appearance_dark')
];

function optionsFrom(labels: Resource[]): PickerOption[] {
  return labels.map((label: Resource, index: number): PickerOption => ({ label: label, value: index }));
}

/** Rounded card that wraps each settings group. */
@Styles
function groupCard() {
  .width('100%')
  .margin({ top: 8 })
  .padding({ left: 18, right: 18 })
  .borderRadius(20)
  .backgroundColor($r('app.color.surface_panel'))
  .border({ width: 1, color: $r('app.color.border') })
}

/**
 * 1h — grouped list, 56vp rows, no inline icons. The switch fill is the only
 * ink-green surface on the screen.
 */
@Component
export struct SettingsPage {
  @Prop settings: BrowserSettings = defaultBrowserSettings();
  onChange: (settings: BrowserSettings) => void = (_settings: BrowserSettings): void => {};
  onClearData: () => void = (): void => {};
  onBack: () => void = (): void => {};
  @State private picker: PickerKind = PickerKind.None;

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Scroll() {
        Column() {
          Row({ space: 12 }) {
            AppIcon({ name: IconName.ArrowLeft, glyphSize: 21, color: $r('app.color.text_primary') })
              .onClick(() => this.onBack())
            Text($r('app.string.settings'))
              .fontSize(24)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
          }
          .width('100%')

          this.GroupLabel($r('app.string.group_rules'), 22)
          Column() {
            this.SwitchRow($r('app.string.block_ads'), this.settings.blockAds, true, () => {
              const next: BrowserSettings = cloneSettings(this.settings);
              next.blockAds = !next.blockAds;
              this.onChange(next);
            })
            this.SwitchRow($r('app.string.block_trackers'), this.settings.blockTrackers, true, () => {
              const next: BrowserSettings = cloneSettings(this.settings);
              next.blockTrackers = !next.blockTrackers;
              this.onChange(next);
            })
            this.ValueRow(
              $r('app.string.rule_strength'),
              RULE_STRENGTH_LABELS[this.settings.ruleStrength as number],
              false,
              () => this.picker = PickerKind.RuleStrength
            )
          }
          .groupCard()

          this.GroupLabel($r('app.string.group_general'), 20)
          Column() {
            this.ValueRow(
              $r('app.string.default_search_engine'),
              SEARCH_ENGINE_LABELS[this.settings.searchEngine as number],
              true,
              () => this.picker = PickerKind.SearchEngine
            )
            this.ValueRow(
              $r('app.string.appearance'),
              APPEARANCE_LABELS[this.settings.appearance as number],
              false,
              () => this.picker = PickerKind.Appearance
            )
          }
          .groupCard()

          this.GroupLabel($r('app.string.group_privacy'), 20)
          Column() {
            this.SwitchRow(
              $r('app.string.clear_cookies_on_tab_close'),
              this.settings.clearCookiesOnTabClose,
              true,
              () => {
                const next: BrowserSettings = cloneSettings(this.settings);
                next.clearCookiesOnTabClose = !next.clearCookiesOnTabClose;
                this.onChange(next);
              }
            )
            this.ActionRow($r('app.string.clear_browsing_data'), false, () => this.confirmClear())
          }
          .groupCard()

          this.GroupLabel($r('app.string.group_about'), 20)
          Column() {
            this.ValueRowText($r('app.string.about_app'), APP_VERSION, false, () => this.showAbout())
          }
          .groupCard()
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ top: 18, left: 24, right: 24, bottom: 40 })
      }
      .width('100%')
      .height('100%')
      .align(Alignment.TopStart)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)

      if (this.picker !== PickerKind.None) {
        this.Picker()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  private GroupLabel(label: Resource, top: number) {
    Text(label)
      .fontSize(12.5)
      .fontColor($r('app.color.text_secondary'))
      .padding({ left: 4, right: 4 })
      .margin({ top: top })
  }

  @Builder
  private SwitchRow(label: Resource, checked: boolean, divided: boolean, onToggle: () => void) {
    Row() {
      Text(label)
        .fontSize(15)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
      AppSwitch({ checked: checked, onToggle: onToggle })
    }
    .width('100%')
    .height(56)
    .border(divided
      ? { width: { bottom: 1 }, color: $r('app.color.border') }
      : { width: 0 })
  }

  @Builder
  private ValueRow(label: Resource, value: Resource, divided: boolean, onTap: () => void) {
    Row() {
      Text(label)
        .fontSize(15)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
      Row({ space: 8 }) {
        Text(value)
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
        AppIcon({ name: IconName.ChevronRight, glyphSize: 16, color: $r('app.color.text_secondary') })
      }
    }
    .width('100%')
    .height(56)
    .border(divided
      ? { width: { bottom: 1 }, color: $r('app.color.border') }
      : { width: 0 })
    .onClick(onTap)
  }

  @Builder
  private ValueRowText(label: Resource, value: string, divided: boolean, onTap: () => void) {
    Row() {
      Text(label)
        .fontSize(15)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
      Row({ space: 8 }) {
        Text(value)
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .fontFeature('"tnum" 1')
        AppIcon({ name: IconName.ChevronRight, glyphSize: 16, color: $r('app.color.text_secondary') })
      }
    }
    .width('100%')
    .height(56)
    .border(divided
      ? { width: { bottom: 1 }, color: $r('app.color.border') }
      : { width: 0 })
    .onClick(onTap)
  }

  @Builder
  private ActionRow(label: Resource, divided: boolean, onTap: () => void) {
    Row() {
      Text(label)
        .fontSize(15)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
      AppIcon({ name: IconName.ChevronRight, glyphSize: 16, color: $r('app.color.text_secondary') })
    }
    .width('100%')
    .height(56)
    .border(divided
      ? { width: { bottom: 1 }, color: $r('app.color.border') }
      : { width: 0 })
    .onClick(onTap)
  }

  /** Sub-screens would break the single-surface rule, so choices open as sheets. */
  @Builder
  private Picker() {
    Column() {
      Column()
        .layoutWeight(1)
        .width('100%')
        .backgroundColor($r('app.color.scrim'))
        .onClick(() => this.picker = PickerKind.None)

      Column() {
        Row()
          .width(36)
          .height(4)
          .borderRadius(2)
          .backgroundColor($r('app.color.handle'))
          .margin({ bottom: 10 })

        ForEach(this.pickerOptions(), (option: PickerOption, index: number) => {
          Row() {
            Text(option.label)
              .fontSize(15)
              .fontColor($r('app.color.text_primary'))
              .layoutWeight(1)
            if (option.value === this.selectedValue()) {
              AppIcon({ name: IconName.Check, glyphSize: 17, color: $r('app.color.accent') })
            }
          }
          .width('100%')
          .height(56)
          .border(index === this.pickerOptions().length - 1
            ? { width: 0 }
            : { width: { bottom: 1 }, color: $r('app.color.border') })
          .onClick(() => this.applyPick(option.value))
        }, (option: PickerOption) => `${option.value}`)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .padding({ top: 10, left: 28, right: 28, bottom: 46 })
      .backgroundColor($r('app.color.surface_panel'))
      .borderRadius({ topLeft: 20, topRight: 20 })
    }
    .width('100%')
    .height('100%')
  }

  private pickerOptions(): PickerOption[] {
    if (this.picker === PickerKind.RuleStrength) {
      return optionsFrom(RULE_STRENGTH_LABELS);
    }
    if (this.picker === PickerKind.SearchEngine) {
      return optionsFrom(SEARCH_ENGINE_LABELS);
    }
    return optionsFrom(APPEARANCE_LABELS);
  }

  private selectedValue(): number {
    if (this.picker === PickerKind.RuleStrength) {
      return this.settings.ruleStrength as number;
    }
    if (this.picker === PickerKind.SearchEngine) {
      return this.settings.searchEngine as number;
    }
    return this.settings.appearance as number;
  }

  private applyPick(value: number): void {
    const next: BrowserSettings = cloneSettings(this.settings);
    if (this.picker === PickerKind.RuleStrength) {
      next.ruleStrength = value as RuleStrength;
    } else if (this.picker === PickerKind.SearchEngine) {
      next.searchEngine = value as SearchEngine;
    } else {
      next.appearance = value as AppearanceMode;
    }
    this.picker = PickerKind.None;
    this.onChange(next);
  }

  private confirmClear(): void {
    this.getUIContext().showAlertDialog({
      title: $r('app.string.clear_browsing_data'),
      message: $r('app.string.clear_browsing_data_message'),
      primaryButton: {
        value: $r('app.string.cancel'),
        action: (): void => {}
      },
      secondaryButton: {
        value: $r('app.string.clear_browsing_data_confirm'),
        fontColor: $r('app.color.accent'),
        action: (): void => this.onClearData()
      }
    });
  }

  private showAbout(): void {
    this.getUIContext().showAlertDialog({
      title: $r('app.string.app_name'),
      message: $r('app.string.about_tagline'),
      confirm: {
        value: $r('app.string.done'),
        action: (): void => {}
      }
    });
  }
}
