import {
  AppearanceMode,
  BrowserSettings,
  RuleStrength,
  SearchEngine,
  SitePermission,
  SitePermissionDecision,
  TabExpiry,
  WebDarkModePreference,
  cloneSettings
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
  TabSoftLimit = 8,
  MinimumFontSize = 9,
  ClearDataRange = 10,
  LargeDownloadThreshold = 11,
  WebDarkMode = 12
}
interface PickerOption {
  label: Resource;
  value: number;
}

interface SettingsSearchEntry {
  key: string;
  label: Resource;
  keywords: string;
  action: () => void;
}

interface SwitchRowParams {
  label: Resource;
  checked: boolean;
  divided: boolean;
  onToggle: () => void;
}

interface ClearDataSwitchRowParams {
  label: Resource;
  checked: boolean;
  onToggle: () => void;
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

const WEB_DARK_MODE_LABELS: Resource[] = [
  $r('app.string.web_dark_mode_system'),
  $r('app.string.web_dark_mode_light'),
  $r('app.string.web_dark_mode_dark')
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

const TAB_SOFT_LIMIT_LABELS: Resource[] = [
  $r('app.string.tab_soft_limit_eight'),
  $r('app.string.tab_soft_limit_twelve'),
  $r('app.string.tab_soft_limit_twenty'),
  $r('app.string.tab_soft_limit_forty')
];

const MINIMUM_FONT_SIZE_LABELS: Resource[] = [
  $r('app.string.minimum_font_size_twelve'),
  $r('app.string.minimum_font_size_fourteen'),
  $r('app.string.minimum_font_size_sixteen'),
  $r('app.string.minimum_font_size_eighteen')
];

const LARGE_DOWNLOAD_THRESHOLD_LABELS: Resource[] = [
  $r('app.string.large_download_threshold_fifty'),
  $r('app.string.large_download_threshold_one_hundred'),
  $r('app.string.large_download_threshold_five_hundred'),
  $r('app.string.large_download_threshold_one_thousand')
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

export function shouldShowCurrentSiteDarkModeRow(
  currentHost: string,
  webDarkMode: WebDarkModePreference
): boolean {
  return currentHost.length > 0 && webDarkMode !== WebDarkModePreference.Light;
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
  @Link settings: BrowserSettings;
  @Prop topInset: number = 0;
  @Prop isWide: boolean = false;
  @Prop allowedHosts: string[] = [];
  @Prop sitePermissions: SitePermission[] = [];
  @Prop currentHost: string = '';
  @Prop currentHostDarkModeEnabled: boolean = false;
  @Prop rulesLastUpdatedAt: number = 0;
  @Prop appVersion: string = '';
  onChange: (settings: BrowserSettings) => void = (_settings: BrowserSettings): void => {};
  onResetGestures: () => void = (): void => {};
  onClearData: (selection: ClearDataSelection) => void = (_selection: ClearDataSelection): void => {};
  onImportBookmarks: () => void = (): void => {};
  onExportBookmarks: () => void = (): void => {};
  onRemoveAllowedHost: (host: string) => void = (_host: string): void => {};
  onRemoveSitePermission: (origin: string) => void = (_origin: string): void => {};
  onUpdateSitePermission: (origin: string, kind: string, decision: SitePermissionDecision) => void =
    (_origin: string, _kind: string, _decision: SitePermissionDecision): void => {};
  onToggleCurrentSiteDarkMode: () => void = (): void => {};
  onUpdateRules: () => void = (): void => {};
  onBack: () => void = (): void => {};
  @State private picker: PickerKind = PickerKind.None;
  @State private isEditingSearchTemplate: boolean = false;
  @State private isClearDataSheetVisible: boolean = false;
  @State private clearHistory: boolean = true;
  @State private clearCookies: boolean = true;
  @State private clearCache: boolean = true;
  @State private clearPermissions: boolean = true;
  @State private clearDataRange: ClearDataRange = ClearDataRange.All;
  @State private searchQuery: string = '';
  @State private isAboutDialogVisible: boolean = false;

  build() {
    Stack({ alignContent: this.isWide ? Alignment.TopEnd : Alignment.Bottom }) {
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

          TextInput({ text: this.searchQuery, placeholder: $r('app.string.settings_search_placeholder') })
            .width('100%')
            .height(46)
            .margin({ top: 16 })
            .padding({ left: 14, right: 14 })
            .fontSize(15)
            .fontColor($r('app.color.text_primary'))
            .placeholderColor($r('app.color.text_secondary'))
            .backgroundColor($r('app.color.surface_subtle'))
            .borderRadius(12)
            .accessibilityText($r('app.string.settings_search_placeholder'))
            .onChange((value: string): void => { this.searchQuery = value; })

          if (this.searchQuery.trim().length > 0) {
            this.SearchResults()
          } else {
          this.GroupLabel($r('app.string.group_rules'), 22)
          Column() {
            this.SwitchRow({
              label: $r('app.string.content_protection'),
              checked: this.isContentProtectionEnabled(),
              divided: true,
              onToggle: () => this.toggleContentProtection()
            })
            this.ValueRow(
              $r('app.string.rule_strength'),
              RULE_STRENGTH_LABELS[this.settings.ruleStrength as number],
              false,
              () => this.picker = PickerKind.RuleStrength
            )
            this.ValueRowText(
              $r('app.string.rules_update'),
              this.rulesLastUpdatedLabel(),
              false,
              () => this.onUpdateRules()
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
            this.SwitchRow({
              label: $r('app.string.search_suggestions'),
              checked: this.settings.searchSuggestionsEnabled,
              divided: true,
              onToggle: () => this.toggleSearchSuggestions()
            })
            this.SwitchRow({
              label: $r('app.string.gestures_enabled'),
              checked: this.settings.gesturesEnabled,
              divided: true,
              onToggle: () => {
                const next: BrowserSettings = cloneSettings(this.settings);
                next.gesturesEnabled = !next.gesturesEnabled;
                this.onChange(next);
              }
            })
            this.SwitchRow({
              label: $r('app.string.gesture_actions'),
              checked: this.settings.gestureActionsEnabled,
              divided: true,
              onToggle: () => {
                const next: BrowserSettings = cloneSettings(this.settings);
                next.gestureActionsEnabled = !next.gestureActionsEnabled;
                this.onChange(next);
              }
            })
            this.SwitchRow({
              label: $r('app.string.gesture_tab_switch'),
              checked: this.settings.gestureTabSwitchEnabled,
              divided: true,
              onToggle: () => {
                const next: BrowserSettings = cloneSettings(this.settings);
                next.gestureTabSwitchEnabled = !next.gestureTabSwitchEnabled;
                this.onChange(next);
              }
            })
            this.SwitchRow({
              label: $r('app.string.gesture_blocking'),
              checked: this.settings.gestureBlockingEnabled,
              divided: true,
              onToggle: () => {
                const next: BrowserSettings = cloneSettings(this.settings);
                next.gestureBlockingEnabled = !next.gestureBlockingEnabled;
                this.onChange(next);
              }
            })
            this.ActionRow($r('app.string.restore_gesture_defaults'), false, () => this.onResetGestures())
            this.SwitchRow({
              label: $r('app.string.auto_hide_toolbar'),
              checked: this.settings.autoHideToolbarEnabled,
              divided: true,
              onToggle: () => {
                const next: BrowserSettings = cloneSettings(this.settings);
                next.autoHideToolbarEnabled = !next.autoHideToolbarEnabled;
                this.onChange(next);
              }
            })
            this.SwitchRow({
              label: $r('app.string.show_quick_sites'),
              checked: this.settings.quickSitesEnabled,
              divided: true,
              onToggle: () => {
                const next: BrowserSettings = cloneSettings(this.settings);
                next.quickSitesEnabled = !next.quickSitesEnabled;
                this.onChange(next);
              }
            })
            this.ValueRow(
              $r('app.string.appearance'),
              APPEARANCE_LABELS[this.settings.appearance as number],
              true,
              () => this.picker = PickerKind.Appearance
            )
            this.ValueRow(
              $r('app.string.web_dark_mode'),
              WEB_DARK_MODE_LABELS[this.settings.webDarkMode as number],
              this.shouldShowCurrentSiteDarkMode(),
              () => this.picker = PickerKind.WebDarkMode
            )
            if (this.shouldShowCurrentSiteDarkMode()) {
              this.SwitchRow({
                label: $r('app.string.web_dark_mode_current_site'),
                checked: this.currentHostDarkModeEnabled,
                divided: true,
                onToggle: () => this.onToggleCurrentSiteDarkMode()
              })
            }
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
            this.ValueRow(
              $r('app.string.large_download_threshold'),
              this.largeDownloadThresholdLabel(),
              true,
              () => this.picker = PickerKind.LargeDownloadThreshold
            )
            this.SwitchRow({
              label: $r('app.string.wifi_only_downloads'),
              checked: this.settings.wifiOnlyDownloads,
              divided: true,
              onToggle: () => {
                const next: BrowserSettings = cloneSettings(this.settings);
                next.wifiOnlyDownloads = !next.wifiOnlyDownloads;
                this.onChange(next);
              }
            })
            this.ActionRow($r('app.string.bookmark_import_html'), false, () => this.onImportBookmarks())
            this.ActionRow($r('app.string.bookmark_export_html'), false, () => this.onExportBookmarks())
            this.ValueRow(
              $r('app.string.tab_soft_limit'),
              this.tabSoftLimitLabel(),
              false,
              () => this.picker = PickerKind.TabSoftLimit
            )
            this.ValueRow(
              $r('app.string.minimum_font_size'),
              this.minimumFontSizeLabel(),
              false,
              () => this.picker = PickerKind.MinimumFontSize
            )
          }
          .groupCard()

          this.GroupLabel($r('app.string.group_privacy'), 20)
          Column() {
            this.SwitchRow({
              label: $r('app.string.clear_cookies_on_tab_close'),
              checked: this.settings.clearCookiesOnTabClose,
              divided: true,
              onToggle: () => {
                const next: BrowserSettings = cloneSettings(this.settings);
                next.clearCookiesOnTabClose = !next.clearCookiesOnTabClose;
                this.onChange(next);
              }
            })
            this.SwitchRow({
              label: $r('app.string.telemetry_switch'),
              checked: this.settings.telemetryEnabled,
              divided: true,
              onToggle: () => {
                const next: BrowserSettings = cloneSettings(this.settings);
                next.telemetryEnabled = !next.telemetryEnabled;
                this.onChange(next);
              }
            })
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
            Text($r('app.string.site_permissions'))
              .width('100%')
              .height(44)
              .margin({ top: 12 })
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
            if (this.sitePermissions.length > 0) {
              ForEach(this.sitePermissions,
                (permission: SitePermission) => this.SitePermissionRow(permission),
                (permission: SitePermission) => permission.origin)
            } else {
              Text($r('app.string.site_permissions_empty'))
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
            this.ValueRowText($r('app.string.about_app'), this.appVersionLabel(), false, () => this.showAbout())
          }
          .groupCard()
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ top: 18, left: 24, right: 24, bottom: 40 })
      }
      .width(this.isWide ? 820 : '100%')
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
          isWide: this.isWide,
          onSave: (template: string): void => this.saveSearchTemplate(template),
          onDismiss: (): void => { this.isEditingSearchTemplate = false; }
        })
      }
      if (this.isAboutDialogVisible) {
        this.AboutDialog()
      }
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.topInset })
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
  private SearchResults() {
    Column({ space: 8 }) {
      Text($r('app.string.settings_search_results'))
        .width('100%')
        .margin({ top: 18, bottom: 4 })
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
      ForEach(this.filteredSearchEntries(), (entry: SettingsSearchEntry) => {
        Row() {
          Text(entry.label)
            .fontSize(15)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
          AppIcon({ name: IconName.ChevronRight, glyphSize: 16, color: $r('app.color.text_secondary') })
        }
        .width('100%')
        .height(56)
        .padding({ left: 16, right: 16 })
        .border({ width: { bottom: 1 }, color: $r('app.color.border') })
        .accessibilityText(entry.label)
        .onClick(() => entry.action())
      }, (entry: SettingsSearchEntry) => entry.key)
      if (this.filteredSearchEntries().length === 0) {
        Text($r('app.string.settings_search_empty'))
          .width('100%')
          .height(56)
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .textAlign(TextAlign.Center)
      }
    }
    .width('100%')
  }

  private filteredSearchEntries(): SettingsSearchEntry[] {
    const query: string = this.searchQuery.trim().toLowerCase();
    const compactQuery: string = query.replace(/\s+/g, '');
    return this.searchEntries().filter((entry: SettingsSearchEntry): boolean => {
      const keywords: string = entry.keywords.toLowerCase();
      if (keywords.includes(query) || keywords.replace(/\s+/g, '').includes(compactQuery)) {
        return true;
      }
      // Chinese users commonly enter a phrase without spaces, while the index
      // intentionally stores independent searchable terms.
      return /[\u4e00-\u9fff]/.test(compactQuery) &&
        compactQuery.split('').every((character: string): boolean => keywords.includes(character));
    });
  }

  private searchEntries(): SettingsSearchEntry[] {
    return [
      {
        key: 'content_protection',
        label: $r('app.string.content_protection'),
        keywords: '广告 追踪 防护 拦截 规则 隐私',
        action: () => this.toggleContentProtection()
      },
      {
        key: 'rule_strength',
        label: $r('app.string.rule_strength'),
        keywords: '页面 清理 强度 标准 严格',
        action: (): void => { this.picker = PickerKind.RuleStrength; }
      },
      {
        key: 'rules_update',
        label: $r('app.string.rules_update'),
        keywords: '更新 拦截 规则',
        action: () => this.onUpdateRules()
      },
      {
        key: 'search_engine',
        label: $r('app.string.default_search_engine'),
        keywords: '搜索 引擎 默认 必应 百度 谷歌 DuckDuckGo',
        action: (): void => { this.picker = PickerKind.SearchEngine; }
      },
      {
        key: 'custom_search_template',
        label: $r('app.string.custom_search_template'),
        keywords: '自定义 搜索 模板 URL',
        action: (): void => { this.isEditingSearchTemplate = true; }
      },
      {
        key: 'search_suggestions',
        label: $r('app.string.search_suggestions'),
        keywords: '搜索 快捷项 本地 地址 历史 收藏',
        action: () => this.toggleSearchSuggestions()
      },
      {
        key: 'gestures_enabled',
        label: $r('app.string.gestures_enabled'),
        keywords: '手势 滑动 操作 启用',
        action: () => this.toggleGesturesEnabled()
      },
      {
        key: 'gesture_actions',
        label: $r('app.string.gesture_actions'),
        keywords: '手势 动作 面板 上滑',
        action: () => this.toggleGestureActions()
      },
      {
        key: 'gesture_tab_switch',
        label: $r('app.string.gesture_tab_switch'),
        keywords: '手势 标签 切换 地址栏 左右滑动',
        action: () => this.toggleGestureTabSwitch()
      },
      {
        key: 'gesture_blocking',
        label: $r('app.string.gesture_blocking'),
        keywords: '手势 拦截 面板 长按',
        action: () => this.toggleGestureBlocking()
      },
      {
        key: 'restore_gesture_defaults',
        label: $r('app.string.restore_gesture_defaults'),
        keywords: '手势 默认 重置 恢复',
        action: () => this.onResetGestures()
      },
      {
        key: 'auto_hide_toolbar',
        label: $r('app.string.auto_hide_toolbar'),
        keywords: '工具栏 自动 隐藏 滚动',
        action: () => this.toggleAutoHideToolbar()
      },
      {
        key: 'quick_sites',
        label: $r('app.string.show_quick_sites'),
        keywords: '常访问 站点 快捷 主页',
        action: () => this.toggleQuickSites()
      },
      {
        key: 'appearance',
        label: $r('app.string.appearance'),
        keywords: '外观 主题 深色 浅色',
        action: (): void => { this.picker = PickerKind.Appearance; }
      },
      {
        key: 'web_dark_mode',
        label: $r('app.string.web_dark_mode'),
        keywords: '网页 深色 暗色 模式 强制 图片 视频',
        action: (): void => { this.picker = PickerKind.WebDarkMode; }
      },
      {
        key: 'tab_expiry',
        label: $r('app.string.tab_expiry'),
        keywords: '标签 清理 归档 过期',
        action: (): void => { this.picker = PickerKind.TabExpiry; }
      },
      {
        key: 'live_webview_limit',
        label: $r('app.string.live_webview_limit'),
        keywords: 'WebView 存活 网页 内存 数量',
        action: (): void => { this.picker = PickerKind.LiveWebViewLimit; }
      },
      {
        key: 'download_concurrency',
        label: $r('app.string.download_concurrency'),
        keywords: '下载 并发 任务 数量',
        action: (): void => { this.picker = PickerKind.DownloadConcurrency; }
      },
      {
        key: 'large_download_threshold',
        label: $r('app.string.large_download_threshold'),
        keywords: '下载 大文件 阈值 流量 移动网络',
        action: (): void => { this.picker = PickerKind.LargeDownloadThreshold; }
      },
      {
        key: 'wifi_only_downloads',
        label: $r('app.string.wifi_only_downloads'),
        keywords: 'Wi-Fi WIFI 下载 网络',
        action: () => this.toggleWifiOnlyDownloads()
      },
      {
        key: 'bookmark_import',
        label: $r('app.string.bookmark_import_html'),
        keywords: '书签 导入 HTML',
        action: () => this.onImportBookmarks()
      },
      {
        key: 'bookmark_export',
        label: $r('app.string.bookmark_export_html'),
        keywords: '书签 导出 HTML',
        action: () => this.onExportBookmarks()
      },
      {
        key: 'tab_soft_limit',
        label: $r('app.string.tab_soft_limit'),
        keywords: '标签 提醒 阈值 数量',
        action: (): void => { this.picker = PickerKind.TabSoftLimit; }
      },
      {
        key: 'minimum_font_size',
        label: $r('app.string.minimum_font_size'),
        keywords: '网页 字号 字体 大字 无障碍',
        action: (): void => { this.picker = PickerKind.MinimumFontSize; }
      },
      {
        key: 'clear_cookies_on_tab_close',
        label: $r('app.string.clear_cookies_on_tab_close'),
        keywords: 'Cookie 关闭 标签 清除',
        action: () => this.toggleClearCookiesOnTabClose()
      },
      {
        key: 'telemetry',
        label: $r('app.string.telemetry_switch'),
        keywords: '遥测 崩溃 性能 统计',
        action: () => this.toggleTelemetry()
      },
      {
        key: 'history_retention',
        label: $r('app.string.history_retention'),
        keywords: '历史 保留 时长 清除',
        action: (): void => { this.picker = PickerKind.HistoryRetention; }
      },
      {
        key: 'clear_data',
        label: $r('app.string.clear_browsing_data'),
        keywords: '历史 Cookie 缓存 权限 清除 数据',
        action: () => this.openClearDataSheet()
      },
      {
        key: 'about',
        label: $r('app.string.about_app'),
        keywords: '关于 版本 应用',
        action: () => this.showAbout()
      }
    ];
  }

  private updateSettings(mutator: (settings: BrowserSettings) => void): void {
    const next: BrowserSettings = cloneSettings(this.settings);
    mutator(next);
    this.onChange(next);
  }

  private isContentProtectionEnabled(): boolean {
    return this.settings.blockAds || this.settings.blockTrackers;
  }

  private toggleContentProtection(): void {
    const enabled: boolean = !this.isContentProtectionEnabled();
    this.updateSettings((next: BrowserSettings): void => {
      next.blockAds = enabled;
      next.blockTrackers = enabled;
    });
  }

  private toggleSearchSuggestions(): void {
    this.updateSettings((next: BrowserSettings): void => {
      next.searchSuggestionsEnabled = !next.searchSuggestionsEnabled;
    });
  }

  private toggleGesturesEnabled(): void {
    this.updateSettings((next: BrowserSettings): void => {
      next.gesturesEnabled = !next.gesturesEnabled;
    });
  }

  private toggleGestureActions(): void {
    this.updateSettings((next: BrowserSettings): void => {
      next.gestureActionsEnabled = !next.gestureActionsEnabled;
    });
  }

  private toggleGestureTabSwitch(): void {
    this.updateSettings((next: BrowserSettings): void => {
      next.gestureTabSwitchEnabled = !next.gestureTabSwitchEnabled;
    });
  }

  private toggleGestureBlocking(): void {
    this.updateSettings((next: BrowserSettings): void => {
      next.gestureBlockingEnabled = !next.gestureBlockingEnabled;
    });
  }

  private toggleAutoHideToolbar(): void {
    this.updateSettings((next: BrowserSettings): void => {
      next.autoHideToolbarEnabled = !next.autoHideToolbarEnabled;
    });
  }

  private toggleQuickSites(): void {
    this.updateSettings((next: BrowserSettings): void => {
      next.quickSitesEnabled = !next.quickSitesEnabled;
    });
  }

  private toggleWifiOnlyDownloads(): void {
    this.updateSettings((next: BrowserSettings): void => {
      next.wifiOnlyDownloads = !next.wifiOnlyDownloads;
    });
  }

  private toggleClearCookiesOnTabClose(): void {
    this.updateSettings((next: BrowserSettings): void => {
      next.clearCookiesOnTabClose = !next.clearCookiesOnTabClose;
    });
  }

  private toggleTelemetry(): void {
    this.updateSettings((next: BrowserSettings): void => {
      next.telemetryEnabled = !next.telemetryEnabled;
    });
  }

  private shouldShowCurrentSiteDarkMode(): boolean {
    return shouldShowCurrentSiteDarkModeRow(this.currentHost, this.settings.webDarkMode);
  }

  private appVersionLabel(): ResourceStr {
    const version: string = this.appVersion.trim();
    if (version.length > 0) {
      return version;
    }
    return $r('app.string.about_version_unknown');
  }

  @Builder
  private SwitchRow($$: SwitchRowParams) {
    Row() {
      Text($$.label)
        .fontSize(15)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
      AppSwitch({ checked: $$.checked, accessibilityLabel: $$.label, onToggle: $$.onToggle })
    }
    .width('100%')
    .height(56)
    .border($$.divided
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

  @Builder
  private SitePermissionRow(permission: SitePermission) {
    Column() {
      Row({ space: 10 }) {
        Text(permission.origin)
          .layoutWeight(1)
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        AppIcon({ name: IconName.Close, glyphSize: 16, color: $r('app.color.text_secondary') })
          .accessibilityText($r('app.string.site_permission_deny'))
          .onClick(() => this.onRemoveSitePermission(permission.origin))
      }
      .width('100%')
      this.PermissionStatusRow($r('app.string.site_permission_camera'), permission.camera,
        () => this.onUpdateSitePermission(permission.origin, 'camera', permission.camera))
      this.PermissionStatusRow($r('app.string.site_permission_microphone'), permission.microphone,
        () => this.onUpdateSitePermission(permission.origin, 'microphone', permission.microphone))
      this.PermissionStatusRow($r('app.string.site_permission_location'), permission.location,
        () => this.onUpdateSitePermission(permission.origin, 'location', permission.location))
    }
    .width('100%')
    .padding({ top: 10, bottom: 10 })
    .border({ width: { bottom: 1 }, color: $r('app.color.border') })
  }

  @Builder
  private PermissionStatusRow(
    label: Resource,
    decision: SitePermissionDecision,
    onTap: () => void
  ) {
    Row() {
      Text(label)
        .layoutWeight(1)
        .fontSize(12.5)
        .fontColor($r('app.color.text_secondary'))
      Text(this.permissionDecisionLabel(decision))
        .fontSize(12.5)
        .fontColor(this.permissionDecisionColor(decision))
      AppIcon({
        name: IconName.ChevronRight,
        glyphSize: 13,
        color: $r('app.color.text_secondary')
      })
    }
    .width('100%')
    .height(28)
    .onClick(onTap)
  }

  private permissionDecisionColor(decision: SitePermissionDecision): ResourceColor {
    if (decision === SitePermissionDecision.Allow) {
      return $r('app.color.accent');
    }
    if (decision === SitePermissionDecision.Deny) {
      return $r('app.color.danger');
    }
    return $r('app.color.text_secondary');
  }

  private permissionDecisionLabel(decision: SitePermissionDecision): Resource {
    if (decision === SitePermissionDecision.Allow) {
      return $r('app.string.site_permission_allowed');
    }
    if (decision === SitePermissionDecision.Deny) {
      return $r('app.string.site_permission_denied');
    }
    return $r('app.string.site_permission_prompt');
  }

  /** Choices stay within Settings while adapting from compact sheets to wide dialogs. */
  @Builder
  private Picker() {
    Stack({ alignContent: this.isWide ? Alignment.Center : Alignment.Bottom }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.scrim'))
        .onClick(() => this.picker = PickerKind.None)

      Column() {
        if (!this.isWide) {
          Row()
            .width(36)
            .height(4)
            .borderRadius(2)
            .backgroundColor($r('app.color.handle'))
            .margin({ bottom: 10 })
        }

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
      .width(this.isWide ? '88%' : '100%')
      .constraintSize({ maxWidth: this.isWide ? 520 : '100%' })
      .alignItems(HorizontalAlign.Center)
      .padding({
        top: this.isWide ? 20 : 10,
        left: 28,
        right: 28,
        bottom: this.isWide ? 20 : 46
      })
      .backgroundColor($r('app.color.surface_panel'))
      .borderRadius(this.isWide
        ? 20
        : { topLeft: 20, topRight: 20 })
      .border({ width: this.isWide ? 1 : 0, color: $r('app.color.border') })
      .shadow(this.isWide
        ? { radius: 18, color: $r('app.color.shadow_soft'), offsetX: 0, offsetY: 6 }
        : undefined)
      .onClick((): void => {})
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
    if (this.picker === PickerKind.TabSoftLimit) {
      return optionsFrom(TAB_SOFT_LIMIT_LABELS);
    }
    if (this.picker === PickerKind.MinimumFontSize) {
      return optionsFrom(MINIMUM_FONT_SIZE_LABELS);
    }
    if (this.picker === PickerKind.LargeDownloadThreshold) {
      return optionsFrom(LARGE_DOWNLOAD_THRESHOLD_LABELS);
    }
    if (this.picker === PickerKind.WebDarkMode) {
      return optionsFrom(WEB_DARK_MODE_LABELS);
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
    if (this.picker === PickerKind.TabSoftLimit) {
      return this.tabSoftLimitIndex();
    }
    if (this.picker === PickerKind.MinimumFontSize) {
      return this.minimumFontSizeIndex();
    }
    if (this.picker === PickerKind.LargeDownloadThreshold) {
      return this.largeDownloadThresholdIndex();
    }
    if (this.picker === PickerKind.WebDarkMode) {
      return this.settings.webDarkMode as number;
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
    } else if (this.picker === PickerKind.TabSoftLimit) {
      next.tabSoftLimit = this.tabSoftLimitValue(value);
    } else if (this.picker === PickerKind.MinimumFontSize) {
      next.minimumFontSize = this.minimumFontSizeValue(value);
    } else if (this.picker === PickerKind.LargeDownloadThreshold) {
      next.largeDownloadThresholdMb = this.largeDownloadThresholdValue(value);
    } else if (this.picker === PickerKind.WebDarkMode) {
      next.webDarkMode = value as WebDarkModePreference;
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

  private tabSoftLimitIndex(): number {
    if (this.settings.tabSoftLimit === 8) {
      return 0;
    }
    if (this.settings.tabSoftLimit === 20) {
      return 2;
    }
    if (this.settings.tabSoftLimit === 40) {
      return 3;
    }
    return 1;
  }

  private tabSoftLimitValue(index: number): number {
    if (index === 0) {
      return 8;
    }
    if (index === 2) {
      return 20;
    }
    if (index === 3) {
      return 40;
    }
    return 12;
  }

  private tabSoftLimitLabel(): Resource {
    return TAB_SOFT_LIMIT_LABELS[this.tabSoftLimitIndex()];
  }

  private minimumFontSizeIndex(): number {
    if (this.settings.minimumFontSize === 12) {
      return 0;
    }
    if (this.settings.minimumFontSize === 16) {
      return 2;
    }
    if (this.settings.minimumFontSize === 18) {
      return 3;
    }
    return 1;
  }

  private minimumFontSizeValue(index: number): number {
    if (index === 0) {
      return 12;
    }
    if (index === 2) {
      return 16;
    }
    if (index === 3) {
      return 18;
    }
    return 14;
  }

  private minimumFontSizeLabel(): Resource {
    return MINIMUM_FONT_SIZE_LABELS[this.minimumFontSizeIndex()];
  }

  private largeDownloadThresholdIndex(): number {
    if (this.settings.largeDownloadThresholdMb === 100) {
      return 1;
    }
    if (this.settings.largeDownloadThresholdMb === 500) {
      return 2;
    }
    if (this.settings.largeDownloadThresholdMb === 1000) {
      return 3;
    }
    return 0;
  }

  private largeDownloadThresholdValue(index: number): number {
    if (index === 1) {
      return 100;
    }
    if (index === 2) {
      return 500;
    }
    if (index === 3) {
      return 1000;
    }
    return 50;
  }

  private largeDownloadThresholdLabel(): Resource {
    return LARGE_DOWNLOAD_THRESHOLD_LABELS[this.largeDownloadThresholdIndex()];
  }

  private rulesLastUpdatedLabel(): ResourceStr {
    if (this.rulesLastUpdatedAt <= 0) {
      return $r('app.string.rules_update_never');
    }
    const date: Date = new Date(this.rulesLastUpdatedAt);
    const hour: string = `${date.getHours()}`.padStart(2, '0');
    const minute: string = `${date.getMinutes()}`.padStart(2, '0');
    return `${date.getMonth() + 1}月${date.getDate()}日 ${hour}:${minute}`;
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
    Stack({ alignContent: this.isWide ? Alignment.Center : Alignment.Bottom }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.scrim'))
        .onClick(() => this.isClearDataSheetVisible = false)

      Column() {
        if (!this.isWide) {
          Row()
            .width(36)
            .height(4)
            .borderRadius(2)
            .backgroundColor($r('app.color.handle'))
            .margin({ bottom: 12 })
        }
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
        this.ClearDataSwitchRow({
          label: $r('app.string.clear_data_history'),
          checked: this.clearHistory,
          onToggle: () => this.clearHistory = !this.clearHistory
        })
        this.ClearDataSwitchRow({
          label: $r('app.string.clear_data_cookies'),
          checked: this.clearCookies,
          onToggle: () => this.clearCookies = !this.clearCookies
        })
        this.ClearDataSwitchRow({
          label: $r('app.string.clear_data_cache'),
          checked: this.clearCache,
          onToggle: () => this.clearCache = !this.clearCache
        })
        this.ClearDataSwitchRow({
          label: $r('app.string.clear_data_permissions'),
          checked: this.clearPermissions,
          onToggle: () => this.clearPermissions = !this.clearPermissions
        })
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
      .width(this.isWide ? '88%' : '100%')
      .constraintSize({ maxWidth: this.isWide ? 520 : '100%' })
      .alignItems(HorizontalAlign.Center)
      .padding({
        top: this.isWide ? 24 : 10,
        left: 28,
        right: 28,
        bottom: this.isWide ? 24 : 32
      })
      .backgroundColor($r('app.color.surface_panel'))
      .borderRadius(this.isWide
        ? 20
        : { topLeft: 20, topRight: 20 })
      .border({ width: this.isWide ? 1 : 0, color: $r('app.color.border') })
      .shadow(this.isWide
        ? { radius: 18, color: $r('app.color.shadow_soft'), offsetX: 0, offsetY: 6 }
        : undefined)
      .onClick((): void => {})
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private ClearDataSwitchRow($$: ClearDataSwitchRowParams) {
    Row() {
      Text($$.label)
        .fontSize(15)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
      AppSwitch({ checked: $$.checked, accessibilityLabel: $$.label, onToggle: $$.onToggle })
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

  @Builder
  private AboutDialog() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.scrim'))
        .onClick(() => this.isAboutDialogVisible = false)

      Column() {
        Text($r('app.string.app_name'))
          .fontSize(22)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .textAlign(TextAlign.Center)
          .width('100%')
        Text(this.appVersionLabel())
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .fontFeature('"tnum" 1')
          .textAlign(TextAlign.Center)
          .width('100%')
          .margin({ top: 8 })
        Text($r('app.string.about_tagline'))
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .textAlign(TextAlign.Center)
          .width('100%')
          .margin({ top: 12 })
        Text($r('app.string.done'))
          .fontSize(16)
          .fontColor($r('app.color.accent'))
          .textAlign(TextAlign.Center)
          .width('100%')
          .height(48)
          .margin({ top: 18 })
          .onClick(() => this.isAboutDialogVisible = false)
      }
      .width('78%')
      .constraintSize({ maxWidth: 360 })
      .padding({ top: 28, left: 24, right: 24, bottom: 12 })
      .borderRadius(20)
      .backgroundColor($r('app.color.surface_panel'))
      .border({ width: 1, color: $r('app.color.border') })
    }
    .width('100%')
    .height('100%')
  }

  private showAbout(): void {
    this.isAboutDialogVisible = true;
  }
}
