import { APP_VERSION } from '../constants/AppConstants';
import {
  AppearanceMode,
  BrowserSettings,
  RuleStrength,
  SearchEngine,
  TabExpiry,
  cloneSettings,
  defaultBrowserSettings
} from '../models/BrowserModels';
import { AppIcon, IconName } from './AppIcon';
import { AppSwitch } from './AppSwitch';
import { SearchTemplateSheet } from './SearchTemplateSheet';

enum PickerKind {
  None = 0,
  RuleStrength = 1,
  SearchEngine = 2,
  Appearance = 3,
  TabExpiry = 4,
  HistoryRetention = 5,
  LiveWebViewLimit = 6,
  DownloadConcurrency = 7,
  ClearDataRange = 8
}
interface PickerOption {
  label: Resource;
  value: number;
}

export enum ClearDataRange {
  All = 0,
  Today = 1,
  SevenDays = 7,
  ThirtyDays = 30
}

export interface ClearDataSelection {
  history: boolean;
  cookies: boolean;
  cache: boolean;
  permissions: boolean;
  range: ClearDataRange;
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

const TAB_EXPIRY_LABELS: Resource[] = [
  $r('app.string.tab_expiry_never'),
  $r('app.string.tab_expiry_one_day'),
  $r('app.string.tab_expiry_three_days'),
  $r('app.string.tab_expiry_seven_days')
];

const HISTORY_RETENTION_LABELS: Resource[] = [
  $r('app.string.history_retention_never'),
  $r('app.string.history_retention_one_day'),
  $r('app.string.history_retention_seven_days'),
  $r('app.string.history_retention_thirty_days')
];

const LIVE_WEBVIEW_LIMIT_LABELS: Resource[] = [
  $r('app.string.live_webview_limit_one'),
  $r('app.string.live_webview_limit_two'),
  $r('app.string.live_webview_limit_four'),
  $r('app.string.live_webview_limit_six')
];

const DOWNLOAD_CONCURRENCY_LABELS: Resource[] = [
  $r('app.string.download_concurrency_one'),
  $r('app.string.download_concurrency_two'),
  $r('app.string.download_concurrency_three'),
  $r('app.string.download_concurrency_four')
];

const CLEAR_DATA_RANGE_LABELS: Resource[] = [
  $r('app.string.clear_data_all_time'),
  $r('app.string.clear_data_today'),
  $r('app.string.clear_data_seven_days'),
  $r('app.string.clear_data_thirty_days')
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
  @Prop allowedHosts: string[] = [];
  onChange: (settings: BrowserSettings) => void = (_settings: BrowserSettings): void => {};
  onResetGestures: () => void = (): void => {};
  onClearData: (selection: ClearDataSelection) => void = (_selection: ClearDataSelection): void => {};
  onRemoveAllowedHost: (host: string) => void = (_host: string): void => {};
  onBack: () => void = (): void => {};
  @State private picker: PickerKind = PickerKind.None;
  @State private isEditingSearchTemplate: boolean = false;
  @State private isClearDataSheetVisible: boolean = false;
  @State private clearHistory: boolean = true;
  @State private clearCookies: boolean = true;
  @State private clearCache: boolean = true;
  @State private clearPermissions: boolean = true;
  @State private clearDataRange: ClearDataRange = ClearDataRange.All;

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
            this.ValueRowText(
              $r('app.string.custom_search_template'),
              this.settings.customSearchTemplate.length > 0
                ? this.settings.customSearchTemplate
                : $r('app.string.custom_search_template_off'),
              true,
              () => this.isEditingSearchTemplate = true
            )
            this.SwitchRow(
              $r('app.string.search_suggestions'),
              this.settings.searchSuggestionsEnabled,
              true,
              () => {
                const next: BrowserSettings = cloneSettings(this.settings);
                next.searchSuggestionsEnabled = !next.searchSuggestionsEnabled;
                this.onChange(next);
              }
            )
            this.SwitchRow(
              $r('app.string.gestures_enabled'),
              this.settings.gesturesEnabled,
              true,
              () => {
                const next: BrowserSettings = cloneSettings(this.settings);
                next.gesturesEnabled = !next.gesturesEnabled;
                this.onChange(next);
              }
            )
            this.SwitchRow(
              $r('app.string.gesture_actions'),
              this.settings.gestureActionsEnabled,
              true,
              () => {
                const next: BrowserSettings = cloneSettings(this.settings);
                next.gestureActionsEnabled = !next.gestureActionsEnabled;
                this.onChange(next);
              }
            )
            this.SwitchRow(
              $r('app.string.gesture_tab_switch'),
              this.settings.gestureTabSwitchEnabled,
              true,
              () => {
                const next: BrowserSettings = cloneSettings(this.settings);
                next.gestureTabSwitchEnabled = !next.gestureTabSwitchEnabled;
                this.onChange(next);
              }
            )
            this.SwitchRow(
              $r('app.string.gesture_blocking'),
              this.settings.gestureBlockingEnabled,
              true,
              () => {
                const next: BrowserSettings = cloneSettings(this.settings);
                next.gestureBlockingEnabled = !next.gestureBlockingEnabled;
                this.onChange(next);
              }
            )
            this.ActionRow($r('app.string.restore_gesture_defaults'), false, () => this.onResetGestures())
            this.SwitchRow(
              $r('app.string.auto_hide_toolbar'),
              this.settings.autoHideToolbarEnabled,
              true,
              () => {
                const next: BrowserSettings = cloneSettings(this.settings);
                next.autoHideToolbarEnabled = !next.autoHideToolbarEnabled;
                this.onChange(next);
              }
            )
            this.SwitchRow(
              $r('app.string.show_quick_sites'),
              this.settings.quickSitesEnabled,
              true,
              () => {
                const next: BrowserSettings = cloneSettings(this.settings);
                next.quickSitesEnabled = !next.quickSitesEnabled;
                this.onChange(next);
              }
            )
            this.ValueRow(
              $r('app.string.appearance'),
              APPEARANCE_LABELS[this.settings.appearance as number],
              false,
              () => this.picker = PickerKind.Appearance
            )
            this.ValueRow(
              $r('app.string.tab_expiry'),
              this.tabExpiryLabel(),
              false,
              () => this.picker = PickerKind.TabExpiry
            )
            this.ValueRow(
              $r('app.string.live_webview_limit'),
              this.liveWebViewLimitLabel(),
              false,
              () => this.picker = PickerKind.LiveWebViewLimit
            )
            this.ValueRow(
              $r('app.string.download_concurrency'),
              this.downloadConcurrencyLabel(),
              false,
              () => this.picker = PickerKind.DownloadConcurrency
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
            this.ValueRow(
              $r('app.string.history_retention'),
              this.historyRetentionLabel(),
              true,
              () => this.picker = PickerKind.HistoryRetention
            )
            this.ActionRow($r('app.string.clear_browsing_data'), false, () => this.openClearDataSheet())
            if (this.allowedHosts.length > 0) {
              ForEach(this.allowedHosts, (host: string) => this.AllowedHostRow(host), (host: string) => host)
            } else {
              Text($r('app.string.no_allowed_hosts'))
                .width('100%')
                .height(44)
                .fontSize(13)
                .fontColor($r('app.color.text_secondary'))
                .textAlign(TextAlign.Start)
            }
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

      if (this.isClearDataSheetVisible && this.picker === PickerKind.None) {
        this.ClearDataSheet()
      }
      if (this.picker !== PickerKind.None) {
        this.Picker()
      }
      if (this.isEditingSearchTemplate) {
        SearchTemplateSheet({
          initialValue: this.settings.customSearchTemplate,
          onSave: (template: string): void => this.saveSearchTemplate(template),
          onDismiss: (): void => { this.isEditingSearchTemplate = false; }
        })
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
  private ValueRowText(label: Resource, value: ResourceStr, divided: boolean, onTap: () => void) {
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

  @Builder
  private AllowedHostRow(host: string) {
    Row({ space: 10 }) {
      Text(host)
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      AppIcon({ name: IconName.Close, glyphSize: 16, color: $r('app.color.text_secondary') })
        .onClick(() => this.onRemoveAllowedHost(host))
    }
    .width('100%')
    .height(44)
    .border({ width: { bottom: 1 }, color: $r('app.color.border') })
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
    if (this.picker === PickerKind.TabExpiry) {
      return optionsFrom(TAB_EXPIRY_LABELS);
    }
    if (this.picker === PickerKind.HistoryRetention) {
      return optionsFrom(HISTORY_RETENTION_LABELS);
    }
    if (this.picker === PickerKind.LiveWebViewLimit) {
      return optionsFrom(LIVE_WEBVIEW_LIMIT_LABELS);
    }
    if (this.picker === PickerKind.DownloadConcurrency) {
      return optionsFrom(DOWNLOAD_CONCURRENCY_LABELS);
    }
    if (this.picker === PickerKind.ClearDataRange) {
      return optionsFrom(CLEAR_DATA_RANGE_LABELS);
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
    if (this.picker === PickerKind.TabExpiry) {
      return this.tabExpiryIndex();
    }
    if (this.picker === PickerKind.HistoryRetention) {
      return this.historyRetentionIndex();
    }
    if (this.picker === PickerKind.LiveWebViewLimit) {
      return this.liveWebViewLimitIndex();
    }
    if (this.picker === PickerKind.DownloadConcurrency) {
      return this.downloadConcurrencyIndex();
    }
    if (this.picker === PickerKind.ClearDataRange) {
      return this.clearDataRangeIndex();
    }
    return this.settings.appearance as number;
  }

  private applyPick(value: number): void {
    if (this.picker === PickerKind.ClearDataRange) {
      this.clearDataRange = this.clearDataRangeValue(value);
      this.picker = PickerKind.None;
      return;
    }
    const next: BrowserSettings = cloneSettings(this.settings);
    if (this.picker === PickerKind.RuleStrength) {
      next.ruleStrength = value as RuleStrength;
    } else if (this.picker === PickerKind.SearchEngine) {
      next.searchEngine = value as SearchEngine;
    } else if (this.picker === PickerKind.TabExpiry) {
      next.tabExpiryDays = this.tabExpiryValue(value);
    } else if (this.picker === PickerKind.HistoryRetention) {
      next.historyRetentionDays = this.historyRetentionValue(value);
    } else if (this.picker === PickerKind.LiveWebViewLimit) {
      next.liveWebViewLimit = this.liveWebViewLimitValue(value);
    } else if (this.picker === PickerKind.DownloadConcurrency) {
      next.downloadConcurrency = this.downloadConcurrencyValue(value);
    } else {
      next.appearance = value as AppearanceMode;
    }
    this.picker = PickerKind.None;
    this.onChange(next);
  }

  private tabExpiryIndex(): number {
    if (this.settings.tabExpiryDays === TabExpiry.OneDay) {
      return 1;
    }
    if (this.settings.tabExpiryDays === TabExpiry.ThreeDays) {
      return 2;
    }
    if (this.settings.tabExpiryDays === TabExpiry.SevenDays) {
      return 3;
    }
    return 0;
  }

  private tabExpiryValue(index: number): TabExpiry {
    if (index === 1) {
      return TabExpiry.OneDay;
    }
    if (index === 2) {
      return TabExpiry.ThreeDays;
    }
    if (index === 3) {
      return TabExpiry.SevenDays;
    }
    return TabExpiry.Never;
  }

  private tabExpiryLabel(): Resource {
    return TAB_EXPIRY_LABELS[this.tabExpiryIndex()];
  }

  private historyRetentionIndex(): number {
    if (this.settings.historyRetentionDays === 1) {
      return 1;
    }
    if (this.settings.historyRetentionDays === 7) {
      return 2;
    }
    if (this.settings.historyRetentionDays === 30) {
      return 3;
    }
    return 0;
  }

  private historyRetentionValue(index: number): number {
    if (index === 1) {
      return 1;
    }
    if (index === 2) {
      return 7;
    }
    if (index === 3) {
      return 30;
    }
    return 0;
  }

  private historyRetentionLabel(): Resource {
    return HISTORY_RETENTION_LABELS[this.historyRetentionIndex()];
  }

  private liveWebViewLimitIndex(): number {
    if (this.settings.liveWebViewLimit === 1) {
      return 0;
    }
    if (this.settings.liveWebViewLimit === 2) {
      return 1;
    }
    if (this.settings.liveWebViewLimit === 6) {
      return 3;
    }
    return 2;
  }

  private liveWebViewLimitValue(index: number): number {
    if (index === 0) {
      return 1;
    }
    if (index === 1) {
      return 2;
    }
    if (index === 3) {
      return 6;
    }
    return 4;
  }

  private liveWebViewLimitLabel(): Resource {
    return LIVE_WEBVIEW_LIMIT_LABELS[this.liveWebViewLimitIndex()];
  }

  private downloadConcurrencyIndex(): number {
    return Math.min(3, Math.max(0, this.settings.downloadConcurrency - 1));
  }

  private downloadConcurrencyValue(index: number): number {
    return Math.min(4, Math.max(1, index + 1));
  }

  private downloadConcurrencyLabel(): Resource {
    return DOWNLOAD_CONCURRENCY_LABELS[this.downloadConcurrencyIndex()];
  }

  private saveSearchTemplate(template: string): void {
    const next: BrowserSettings = cloneSettings(this.settings);
    next.customSearchTemplate = template;
    this.isEditingSearchTemplate = false;
    this.onChange(next);
  }

  private confirmClear(): void {
    if (!this.clearHistory && !this.clearCookies && !this.clearCache && !this.clearPermissions) {
      this.getUIContext().showAlertDialog({
        title: $r('app.string.clear_browsing_data'),
        message: $r('app.string.clear_data_select_at_least_one'),
        confirm: { value: $r('app.string.done'), action: (): void => {} }
      });
      return;
    }
    const selection: ClearDataSelection = {
      history: this.clearHistory,
      cookies: this.clearCookies,
      cache: this.clearCache,
      permissions: this.clearPermissions,
      range: this.clearDataRange
    };
    this.getUIContext().showAlertDialog({
      title: $r('app.string.clear_browsing_data'),
      message: $r('app.string.clear_data_confirm_message'),
      primaryButton: {
        value: $r('app.string.cancel'),
        action: (): void => {}
      },
      secondaryButton: {
        value: $r('app.string.clear_browsing_data_confirm'),
        fontColor: $r('app.color.accent'),
        action: (): void => {
          this.isClearDataSheetVisible = false;
          this.onClearData(selection);
        }
      }
    });
  }

  private openClearDataSheet(): void {
    this.clearHistory = true;
    this.clearCookies = true;
    this.clearCache = true;
    this.clearPermissions = true;
    this.clearDataRange = ClearDataRange.All;
    this.isClearDataSheetVisible = true;
  }

  @Builder
  private ClearDataSheet() {
    Column() {
      Column()
        .layoutWeight(1)
        .width('100%')
        .backgroundColor($r('app.color.scrim'))
        .onClick(() => this.isClearDataSheetVisible = false)

      Column() {
        Row()
          .width(36)
          .height(4)
          .borderRadius(2)
          .backgroundColor($r('app.color.handle'))
          .margin({ bottom: 12 })
        Text($r('app.string.clear_browsing_data'))
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
        Text($r('app.string.clear_data_select_hint'))
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .margin({ top: 6, bottom: 8 })
        this.ClearDataSwitchRow($r('app.string.clear_data_history'), this.clearHistory,
          () => this.clearHistory = !this.clearHistory)
        this.ClearDataSwitchRow($r('app.string.clear_data_cookies'), this.clearCookies,
          () => this.clearCookies = !this.clearCookies)
        this.ClearDataSwitchRow($r('app.string.clear_data_cache'), this.clearCache,
          () => this.clearCache = !this.clearCache)
        this.ClearDataSwitchRow($r('app.string.clear_data_permissions'), this.clearPermissions,
          () => this.clearPermissions = !this.clearPermissions)
        Row() {
          Text($r('app.string.clear_data_time_range'))
            .fontSize(15)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
          Text(this.clearDataRangeLabel())
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
          AppIcon({ name: IconName.ChevronRight, glyphSize: 16, color: $r('app.color.text_secondary') })
        }
        .width('100%')
        .height(52)
        .onClick(() => this.picker = PickerKind.ClearDataRange)
        Text($r('app.string.clear_data_range_note'))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .margin({ top: 4 })
        Row({ space: 12 }) {
          Text($r('app.string.cancel'))
            .fontSize(15)
            .fontColor($r('app.color.text_secondary'))
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
            .onClick(() => this.isClearDataSheetVisible = false)
          Text($r('app.string.clear_data_continue'))
            .fontSize(15)
            .fontColor($r('app.color.accent'))
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
            .onClick(() => this.confirmClear())
        }
        .width('100%')
        .height(52)
        .margin({ top: 8 })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .padding({ top: 10, left: 28, right: 28, bottom: 32 })
      .backgroundColor($r('app.color.surface_panel'))
      .borderRadius({ topLeft: 20, topRight: 20 })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private ClearDataSwitchRow(label: Resource, checked: boolean, onToggle: () => void) {
    Row() {
      Text(label)
        .fontSize(15)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
      AppSwitch({ checked: checked, onToggle: onToggle })
    }
    .width('100%')
    .height(48)
    .border({ width: { bottom: 1 }, color: $r('app.color.border') })
  }

  private clearDataRangeIndex(): number {
    if (this.clearDataRange === ClearDataRange.Today) {
      return 1;
    }
    if (this.clearDataRange === ClearDataRange.SevenDays) {
      return 2;
    }
    if (this.clearDataRange === ClearDataRange.ThirtyDays) {
      return 3;
    }
    return 0;
  }

  private clearDataRangeValue(index: number): ClearDataRange {
    if (index === 1) {
      return ClearDataRange.Today;
    }
    if (index === 2) {
      return ClearDataRange.SevenDays;
    }
    if (index === 3) {
      return ClearDataRange.ThirtyDays;
    }
    return ClearDataRange.All;
  }

  private clearDataRangeLabel(): Resource {
    return CLEAR_DATA_RANGE_LABELS[this.clearDataRangeIndex()];
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
