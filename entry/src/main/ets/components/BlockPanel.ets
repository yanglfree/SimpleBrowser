import { BlockStats, totalBlocked } from '../models/BrowserModels';
import { groupNumber } from '../utils/Formatting';
import { AppIcon, IconName } from './AppIcon';
import { AppSwitch } from './AppSwitch';

const SWIPE_THRESHOLD: number = 26;

interface BlockRow {
  key: string;
  label: Resource;
  value: number;
}

/**
 * 1f — long-press the capsule. The counts are the loudest thing on screen but
 * still typeset in the primary text colour: statistics, not an alarm. The
 * distribution bars stay neutral grey so the accent never encodes data.
 */
@Component
export struct BlockPanel {
  @Prop host: string = '';
  @Prop stats: BlockStats = { ads: 0, trackers: 0, malicious: 0, popups: 0, cookieBanners: 0 };
  @Prop cumulativeBlockedCount: number = 0;
  /** The switch reads "关闭拦截", so on means blocking is off for this site. */
  @Prop isDisabledForSite: boolean = false;
  onDismiss: () => void = (): void => {};
  onToggleSite: () => void = (): void => {};
  onOpenEvents: () => void = (): void => {};
  onOpenSiteControls: () => void = (): void => {};
  onReportIssue: () => void = (): void => {};
  onOpenSettings: () => void = (): void => {};

  build() {
    Column() {
      Column()
        .layoutWeight(1)
        .width('100%')
        .backgroundColor($r('app.color.scrim'))
        .onClick(() => this.onDismiss())

      this.Panel()
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private Panel() {
    Column() {
      Row()
        .width(36)
        .height(4)
        .borderRadius(2)
        .backgroundColor($r('app.color.handle'))

      Row({ space: 10 }) {
        AppIcon({ name: IconName.ShieldCheck, glyphSize: 16, color: $r('app.color.accent') })
        Text() {
          Span(this.host)
          Span(' · ')
          Span($r('app.string.blocked_on_site'))
        }
        .fontSize(13.5)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .margin({ top: 24 })

      Text(groupNumber(totalBlocked(this.stats)))
        .width('100%')
        .fontSize(54)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .fontFeature('"tnum" 1')
        .margin({ top: 12 })
      Text() {
        Span($r('app.string.blocked_cumulative_prefix'))
        Span(` ${groupNumber(this.cumulativeBlockedCount)}`)
        Span($r('app.string.blocked_cumulative_suffix'))
      }
        .width('100%')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))

      Column({ space: 16 }) {
        ForEach(this.rows(), (row: BlockRow) => {
          this.DistributionRow(row)
        }, (row: BlockRow) => row.key)
      }
      .width('100%')
      .margin({ top: 28 })

      Divider()
        .strokeWidth(1)
        .color($r('app.color.border'))
        .margin({ top: 28 })

      Row() {
        Text($r('app.string.disable_blocking_on_site'))
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        AppSwitch({ checked: this.isDisabledForSite, onToggle: () => this.onToggleSite() })
      }
      .width('100%')
      .height(56)

      Divider()
        .strokeWidth(1)
        .color($r('app.color.border'))

      Row() {
        Text($r('app.string.page_issue_report'))
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        AppIcon({ name: IconName.ChevronRight, glyphSize: 17, color: $r('app.color.text_secondary') })
      }
      .width('100%')
      .height(56)
      .onClick(() => this.onReportIssue())

      Divider()
        .strokeWidth(1)
        .color($r('app.color.border'))

      Row() {
        Text($r('app.string.site_control_title'))
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        AppIcon({ name: IconName.ChevronRight, glyphSize: 17, color: $r('app.color.text_secondary') })
      }
      .width('100%')
      .height(56)
      .onClick(() => this.onOpenSiteControls())

      Divider()
        .strokeWidth(1)
        .color($r('app.color.border'))

      Row() {
        Text($r('app.string.block_event_title'))
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        AppIcon({ name: IconName.ChevronRight, glyphSize: 17, color: $r('app.color.text_secondary') })
      }
      .width('100%')
      .height(56)
      .onClick(() => this.onOpenEvents())

      Divider()
        .strokeWidth(1)
        .color($r('app.color.border'))

      Row() {
        Text($r('app.string.blocking_global_settings'))
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        AppIcon({ name: IconName.ChevronRight, glyphSize: 17, color: $r('app.color.text_secondary') })
      }
      .width('100%')
      .height(56)
      .onClick(() => this.onOpenSettings())
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .padding({ top: 10, left: 28, right: 28, bottom: 46 })
    .backgroundColor($r('app.color.surface_panel'))
    .borderRadius({ topLeft: 20, topRight: 20 })
    .shadow({ radius: 12, color: $r('app.color.shadow_soft'), offsetX: 0, offsetY: -2 })
    .gesture(
      PanGesture({ direction: PanDirection.Vertical, distance: 6 })
        .onActionEnd((event: GestureEvent) => {
          if (event.offsetY >= SWIPE_THRESHOLD) {
            this.onDismiss();
          }
        })
    )
  }

  @Builder
  private DistributionRow(row: BlockRow) {
    Row({ space: 14 }) {
      Text(row.label)
        .width(76)
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(1)

      Stack({ alignContent: Alignment.Start }) {
        Row()
          .width(`${this.barPercent(row.value)}%`)
          .height(8)
          .borderRadius(4)
          .backgroundColor($r('app.color.bar_fill'))
      }
      .layoutWeight(1)
      .height(8)
      .borderRadius(4)
      .backgroundColor($r('app.color.bar_track'))

      Text(`${row.value}`)
        .width(36)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .fontFeature('"tnum" 1')
        .textAlign(TextAlign.End)
    }
    .width('100%')
  }

  /** Bars are scaled against the largest category, as in the design. */
  private barPercent(value: number): number {
    const peak: number = Math.max(
      this.stats.ads,
      this.stats.trackers,
      this.stats.malicious,
      this.stats.popups,
      this.stats.cookieBanners
    );
    return peak <= 0 ? 0 : Math.round((value / peak) * 100);
  }

  private rows(): BlockRow[] {
    return [
      { key: 'ads', label: $r('app.string.category_ads'), value: this.stats.ads },
      { key: 'trackers', label: $r('app.string.category_trackers'), value: this.stats.trackers },
      { key: 'malicious', label: $r('app.string.category_malicious'), value: this.stats.malicious },
      { key: 'popups', label: $r('app.string.category_popups'), value: this.stats.popups },
      {
        key: 'cookies',
        label: $r('app.string.category_cookie_banners'),
        value: this.stats.cookieBanners
      }
    ];
  }
}
