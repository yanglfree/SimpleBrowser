import { QuickSite, QuickSiteIcon, quickSiteDropTarget, quickSiteIconPath } from '../models/BrowserModels';
import { rawHost } from '../utils/UrlUtils';
import { AppIcon, IconName } from './AppIcon';
import {
  QUICK_SITE_ADD_STROKE_WIDTH, QUICK_SITE_COLUMNS, QUICK_SITE_DELETE_VISUAL_SIZE,
  QUICK_SITE_WIDE_LANDSCAPE_COLUMNS,
  QUICK_SITE_DONE_FONT_SIZE, QUICK_SITE_DONE_RADIUS, QUICK_SITE_DONE_WIDTH,
  QUICK_SITE_DRAG_SHADOW_OFFSET_Y, QUICK_SITE_DRAG_SHADOW_RADIUS, QUICK_SITE_EDIT_LONG_PRESS_DURATION,
  QUICK_SITE_GRID_SECTION_GAP, QUICK_SITE_HORIZONTAL_PADDING, QUICK_SITE_ICON_RATIO,
  QUICK_SITE_PHONE_ADD_GLYPH_SIZE,
  QUICK_SITE_PHONE_COLUMN_GAP, QUICK_SITE_PHONE_ITEM_GAP, QUICK_SITE_PHONE_MAX_WIDTH,
  QUICK_SITE_PHONE_ROW_EXTRA, QUICK_SITE_PHONE_ROW_GAP, QUICK_SITE_PHONE_TILE_FONT_SIZE,
  QUICK_SITE_PHONE_TILE_RADIUS, QUICK_SITE_PHONE_TILE_SIZE, QUICK_SITE_PHONE_TITLE_FONT_SIZE,
  QUICK_SITE_REMOVE_GLYPH_SIZE, QUICK_SITE_TOUCH_TARGET, QUICK_SITE_WIDE_ADD_GLYPH_SIZE,
  QUICK_SITE_WIDE_COLUMN_GAP, QUICK_SITE_WIDE_ITEM_GAP, QUICK_SITE_WIDE_MAX_WIDTH,
  QUICK_SITE_WIDE_ROW_EXTRA, QUICK_SITE_WIDE_ROW_GAP, QUICK_SITE_WIDE_TILE_FONT_SIZE,
  QUICK_SITE_WIDE_TILE_RADIUS, QUICK_SITE_WIDE_TILE_SIZE, QUICK_SITE_WIDE_TITLE_FONT_SIZE,
  QUICK_SITE_WIGGLE_ANGLE, QUICK_SITE_WIGGLE_TICK_MS,
  QUICK_SITE_WIGGLE_STEP, QUICK_SITE_WIGGLE_PHASE_OFFSET,
  QUICK_SITE_WIGGLE_ENTER_DURATION, QUICK_SITE_WIGGLE_EXIT_DURATION
} from './QuickSiteTokens';

const TILE_BACKGROUNDS: Resource[] = [
  $r('app.color.site_tile_bg_1'), $r('app.color.site_tile_bg_2'), $r('app.color.site_tile_bg_3'),
  $r('app.color.site_tile_bg_4'), $r('app.color.site_tile_bg_5'), $r('app.color.site_tile_bg_6')
];

const TILE_FOREGROUNDS: Resource[] = [
  $r('app.color.site_tile_fg_1'), $r('app.color.site_tile_fg_2'), $r('app.color.site_tile_fg_3'),
  $r('app.color.site_tile_fg_4'), $r('app.color.site_tile_fg_5'), $r('app.color.site_tile_fg_6')
];

function tileColor(palette: Resource[], index: number): Resource {
  return palette[index >= 0 && index < palette.length ? index : 0];
}

@Component
export struct QuickSiteGrid {
  @Prop quickSites: QuickSite[] = [];
  @Prop siteIcons: QuickSiteIcon[] = [];
  @Prop quickSiteLimit: number = 6;
  @Prop backgroundEnabled: boolean = true;
  @Prop isWide: boolean = false;
  @Prop isLandscape: boolean = false;
  @State private isEditing: boolean = false;
  @State private wigglePhase: number = 0;
  @State private wiggleScale: number = 0;
  @State private dragBadge: string = '';
  @State private dragColorIndex: number = 0;
  @State private dragIconPath: string = '';
  /** Hosts whose cached file would not decode; they fall back to the letter tile. */
  @State private brokenIconHosts: string[] = [];
  private wiggleTimer: number = -1;
  onAddSite: () => void = (): void => {};
  onOpenSite: (url: string) => void = (_url: string): void => {};
  onRemoveSite: (url: string) => void = (_url: string): void => {};
  onMoveSite: (from: number, to: number) => void = (_from: number, _to: number): void => {};

  aboutToDisappear(): void {
    if (this.wiggleTimer >= 0) {
      clearInterval(this.wiggleTimer);
      this.wiggleTimer = -1;
    }
  }

  build() {
    Column({ space: QUICK_SITE_GRID_SECTION_GAP }) {
      if (this.isEditing) {
        Row() {
          Text($r('app.string.done'))
            .fontSize(QUICK_SITE_DONE_FONT_SIZE)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.accent_strong'))
        }
        .id('quick-site-edit-done')
        .width(QUICK_SITE_DONE_WIDTH)
        .height(QUICK_SITE_TOUCH_TARGET)
        .alignSelf(ItemAlign.End)
        .justifyContent(FlexAlign.Center)
        .borderRadius(QUICK_SITE_DONE_RADIUS)
        .backgroundColor(this.backgroundEnabled
          ? $r('app.color.home_tile_background') : $r('app.color.surface_panel'))
        .onClick(() => this.leaveEditing())
      }

      Grid() {
        ForEach(this.visibleSites(), (site: QuickSite, index: number) => {
          GridItem() {
            this.SiteTile(site, index)
          }
        }, (site: QuickSite) => site.url)

        GridItem() {
          this.AddTile()
        }
        .draggable(false)
      }
      .columnsTemplate(this.columnTemplate())
      .columnsGap(this.isWide ? QUICK_SITE_WIDE_COLUMN_GAP : QUICK_SITE_PHONE_COLUMN_GAP)
      .rowsGap(this.isWide ? QUICK_SITE_WIDE_ROW_GAP : QUICK_SITE_PHONE_ROW_GAP)
      .width('100%')
      .height(this.gridHeight())
      .editMode(true)
      .supportAnimation(true)
      .onItemDragStart((_event: ItemDragInfo, itemIndex: number) => {
        if (itemIndex >= 0 && itemIndex < this.visibleSites().length) {
          const site: QuickSite = this.visibleSites()[itemIndex];
          this.dragBadge = site.badge;
          this.dragColorIndex = site.colorIndex;
          this.dragIconPath = this.iconPath(site);
          this.enterEditing();
          return this.DragPreview();
        }
      })
      .onItemDrop((_event: ItemDragInfo, itemIndex: number, insertIndex: number, isSuccess: boolean): void => {
        const count: number = this.visibleSites().length;
        const target: number = quickSiteDropTarget(count, insertIndex);
        if (isSuccess && itemIndex >= 0 && itemIndex < count && target >= 0) {
          this.onMoveSite(itemIndex, target);
        }
      })
    }
    .width('100%')
    .constraintSize({ maxWidth: this.isWide ? QUICK_SITE_WIDE_MAX_WIDTH : QUICK_SITE_PHONE_MAX_WIDTH })
    .padding({ left: QUICK_SITE_HORIZONTAL_PADDING, right: QUICK_SITE_HORIZONTAL_PADDING })
  }

  @Builder
  private SiteTile(site: QuickSite, index: number) {
    Column({ space: this.isWide ? QUICK_SITE_WIDE_ITEM_GAP : QUICK_SITE_PHONE_ITEM_GAP }) {
      Stack({ alignContent: Alignment.TopEnd }) {
        if (this.iconPath(site).length > 0) {
          this.IconTile(site)
        } else {
          Text(site.badge)
            .width(this.tileSize()).height(this.tileSize())
            .borderRadius(this.isWide ? QUICK_SITE_WIDE_TILE_RADIUS : QUICK_SITE_PHONE_TILE_RADIUS)
            .backgroundColor(tileColor(TILE_BACKGROUNDS, site.colorIndex))
            .fontColor(tileColor(TILE_FOREGROUNDS, site.colorIndex))
            .fontSize(this.isWide ? QUICK_SITE_WIDE_TILE_FONT_SIZE : QUICK_SITE_PHONE_TILE_FONT_SIZE)
            .fontWeight(FontWeight.Bold).textAlign(TextAlign.Center)
        }

        if (this.isEditing) {
          Stack({ alignContent: Alignment.TopEnd }) {
            Column() {
              AppIcon({
                name: IconName.Close,
                glyphSize: QUICK_SITE_REMOVE_GLYPH_SIZE,
                color: $r('app.color.content_background')
              })
            }
            .width(QUICK_SITE_DELETE_VISUAL_SIZE).height(QUICK_SITE_DELETE_VISUAL_SIZE)
            .justifyContent(FlexAlign.Center).borderRadius(QUICK_SITE_DELETE_VISUAL_SIZE / 2)
            .backgroundColor($r('app.color.danger'))
          }
          .id(`quick-site-remove-${index}`)
          .width(QUICK_SITE_TOUCH_TARGET).height(QUICK_SITE_TOUCH_TARGET)
          .position({ x: this.tileSize() - QUICK_SITE_TOUCH_TARGET, y: 0 })
          .onClick(() => this.onRemoveSite(site.url))
        }
      }
      .width(this.tileSize()).height(this.tileSize())

      Text(site.title)
        .width('100%')
        .fontSize(this.isWide ? QUICK_SITE_WIDE_TITLE_FONT_SIZE : QUICK_SITE_PHONE_TITLE_FONT_SIZE)
        .fontColor(this.primaryColor())
        .textAlign(TextAlign.Center).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .rotate({ angle: this.tileAngle(index) })
    .onClick(() => {
      if (!this.isEditing) {
        this.onOpenSite(site.url);
      }
    })
    .parallelGesture(
      LongPressGesture({ repeat: false, duration: QUICK_SITE_EDIT_LONG_PRESS_DURATION })
        .onAction(() => this.enterEditing())
    )
  }

  /**
   * The real site icon on a plain card rather than the coloured letter tile: a
   * favicon carries its own brand colour, and a transparent one needs a neutral
   * surface behind it instead of a letter showing through.
   */
  @Builder
  private IconTile(site: QuickSite) {
    Column() {
      Image(this.iconPath(site))
        .width(this.iconSize())
        .height(this.iconSize())
        .objectFit(ImageFit.Contain)
        .interpolation(ImageInterpolation.High)
        .draggable(false)
        .onError(() => this.markIconBroken(site))
    }
    .width(this.tileSize()).height(this.tileSize())
    .justifyContent(FlexAlign.Center)
    .borderRadius(this.isWide ? QUICK_SITE_WIDE_TILE_RADIUS : QUICK_SITE_PHONE_TILE_RADIUS)
    .backgroundColor(this.backgroundEnabled
      ? $r('app.color.home_tile_background') : $r('app.color.surface_panel'))
  }

  @Builder
  private AddTile() {
    Column({ space: this.isWide ? QUICK_SITE_WIDE_ITEM_GAP : QUICK_SITE_PHONE_ITEM_GAP }) {
      Column() {
        AppIcon({
          name: IconName.Plus,
          glyphSize: this.isWide ? QUICK_SITE_WIDE_ADD_GLYPH_SIZE : QUICK_SITE_PHONE_ADD_GLYPH_SIZE,
          color: this.primaryColor(), strokeWidth: QUICK_SITE_ADD_STROKE_WIDTH
        })
      }
      .width(this.tileSize()).height(this.tileSize()).justifyContent(FlexAlign.Center)
      .borderRadius(this.isWide ? QUICK_SITE_WIDE_TILE_RADIUS : QUICK_SITE_PHONE_TILE_RADIUS)
      .backgroundColor(this.backgroundEnabled
        ? $r('app.color.home_tile_background') : $r('app.color.surface_subtle'))

      Text($r('app.string.add_shortcut'))
        .width('100%')
        .fontSize(this.isWide ? QUICK_SITE_WIDE_TITLE_FONT_SIZE : QUICK_SITE_PHONE_TITLE_FONT_SIZE)
        .fontColor(this.primaryColor()).textAlign(TextAlign.Center)
    }
    .width('100%').opacity(this.isEditing ? 0.45 : 1)
    .onClick(() => {
      if (!this.isEditing) {
        this.onAddSite();
      }
    })
  }

  @Builder
  private DragPreview() {
    if (this.dragIconPath.length > 0) {
      Column() {
        Image(this.dragIconPath)
          .width(this.iconSize()).height(this.iconSize())
          .objectFit(ImageFit.Contain)
          .draggable(false)
      }
      .width(this.tileSize()).height(this.tileSize())
      .justifyContent(FlexAlign.Center)
      .borderRadius(this.isWide ? QUICK_SITE_WIDE_TILE_RADIUS : QUICK_SITE_PHONE_TILE_RADIUS)
      .backgroundColor(this.backgroundEnabled
        ? $r('app.color.home_tile_background') : $r('app.color.surface_panel'))
      .shadow({
        radius: QUICK_SITE_DRAG_SHADOW_RADIUS,
        color: $r('app.color.shadow_soft'),
        offsetY: QUICK_SITE_DRAG_SHADOW_OFFSET_Y
      })
    } else {
      Text(this.dragBadge)
        .width(this.tileSize()).height(this.tileSize())
        .borderRadius(this.isWide ? QUICK_SITE_WIDE_TILE_RADIUS : QUICK_SITE_PHONE_TILE_RADIUS)
        .backgroundColor(tileColor(TILE_BACKGROUNDS, this.dragColorIndex))
        .fontColor(tileColor(TILE_FOREGROUNDS, this.dragColorIndex))
        .fontSize(this.isWide ? QUICK_SITE_WIDE_TILE_FONT_SIZE : QUICK_SITE_PHONE_TILE_FONT_SIZE)
        .fontWeight(FontWeight.Bold).textAlign(TextAlign.Center)
        .shadow({
          radius: QUICK_SITE_DRAG_SHADOW_RADIUS,
          color: $r('app.color.shadow_soft'),
          offsetY: QUICK_SITE_DRAG_SHADOW_OFFSET_Y
        })
    }
  }

  private visibleSites(): QuickSite[] {
    return this.quickSites.slice(0, this.quickSiteLimit);
  }

  private tileSize(): number {
    return this.isWide ? QUICK_SITE_WIDE_TILE_SIZE : QUICK_SITE_PHONE_TILE_SIZE;
  }

  /** Inset so a square favicon does not touch the rounded corners of its card. */
  private iconSize(): number {
    return Math.round(this.tileSize() * QUICK_SITE_ICON_RATIO);
  }

  private iconPath(site: QuickSite): string {
    const host: string = rawHost(site.url);
    if (host.length === 0 || this.brokenIconHosts.includes(host)) {
      return '';
    }
    return quickSiteIconPath(this.siteIcons, host);
  }

  private markIconBroken(site: QuickSite): void {
    const host: string = rawHost(site.url);
    if (host.length > 0 && !this.brokenIconHosts.includes(host)) {
      this.brokenIconHosts = this.brokenIconHosts.concat([host]);
    }
  }

  private columnCount(): number {
    return this.isWide && this.isLandscape ? QUICK_SITE_WIDE_LANDSCAPE_COLUMNS : QUICK_SITE_COLUMNS;
  }

  private columnTemplate(): string {
    const parts: string[] = [];
    for (let index: number = 0; index < this.columnCount(); index += 1) {
      parts.push('1fr');
    }
    return parts.join(' ');
  }

  private gridHeight(): number {
    const rows: number = Math.ceil((this.visibleSites().length + 1) / this.columnCount());
    const rowHeight: number = this.tileSize() +
      (this.isWide ? QUICK_SITE_WIDE_ROW_EXTRA : QUICK_SITE_PHONE_ROW_EXTRA);
    return rows * rowHeight + Math.max(0, rows - 1) *
      (this.isWide ? QUICK_SITE_WIDE_ROW_GAP : QUICK_SITE_PHONE_ROW_GAP);
  }

  private enterEditing(): void {
    if (this.isEditing) {
      return;
    }
    this.isEditing = true;
    this.wigglePhase = 0;
    this.getUIContext().animateTo({
      duration: QUICK_SITE_WIGGLE_ENTER_DURATION,
      curve: Curve.EaseOut
    }, (): void => {
      this.wiggleScale = 1;
    });
    // A sine wave driven by a 25fps timer; every icon gets its own phase
    // offset so they wobble out of lockstep, like the iOS launcher.
    this.wiggleTimer = setInterval((): void => {
      if (!this.isEditing) {
        return;
      }
      this.wigglePhase = (this.wigglePhase + QUICK_SITE_WIGGLE_STEP) % (Math.PI * 2);
    }, QUICK_SITE_WIGGLE_TICK_MS);
  }

  private leaveEditing(): void {
    this.isEditing = false;
    this.getUIContext().animateTo({
      duration: QUICK_SITE_WIGGLE_EXIT_DURATION,
      curve: Curve.EaseOut
    }, (): void => {
      this.wiggleScale = 0;
    });
    setTimeout((): void => {
      if (this.wiggleTimer >= 0) {
        clearInterval(this.wiggleTimer);
        this.wiggleTimer = -1;
      }
      this.wigglePhase = 0;
    }, QUICK_SITE_WIGGLE_EXIT_DURATION);
  }

  private tileAngle(index: number): number {
    if (!this.isEditing) {
      return 0;
    }
    return Math.sin(this.wigglePhase + index * QUICK_SITE_WIGGLE_PHASE_OFFSET) *
      QUICK_SITE_WIGGLE_ANGLE * this.wiggleScale;
  }

  private primaryColor(): ResourceColor {
    return this.backgroundEnabled ? $r('app.color.home_text_primary') : $r('app.color.text_primary');
  }
}
