import { QuickSite, quickSiteDropTarget } from '../models/BrowserModels';
import { AppIcon, IconName } from './AppIcon';
import {
  QUICK_SITE_ADD_STROKE_WIDTH, QUICK_SITE_COLUMNS, QUICK_SITE_DELETE_VISUAL_SIZE,
  QUICK_SITE_DONE_FONT_SIZE, QUICK_SITE_DONE_RADIUS, QUICK_SITE_DONE_WIDTH,
  QUICK_SITE_DRAG_SHADOW_OFFSET_Y, QUICK_SITE_DRAG_SHADOW_RADIUS, QUICK_SITE_EDIT_LONG_PRESS_DURATION,
  QUICK_SITE_GRID_SECTION_GAP, QUICK_SITE_HORIZONTAL_PADDING, QUICK_SITE_PHONE_ADD_GLYPH_SIZE,
  QUICK_SITE_PHONE_COLUMN_GAP, QUICK_SITE_PHONE_ITEM_GAP, QUICK_SITE_PHONE_MAX_WIDTH,
  QUICK_SITE_PHONE_ROW_EXTRA, QUICK_SITE_PHONE_ROW_GAP, QUICK_SITE_PHONE_TILE_FONT_SIZE,
  QUICK_SITE_PHONE_TILE_RADIUS, QUICK_SITE_PHONE_TILE_SIZE, QUICK_SITE_PHONE_TITLE_FONT_SIZE,
  QUICK_SITE_REMOVE_GLYPH_SIZE, QUICK_SITE_TOUCH_TARGET, QUICK_SITE_WIDE_ADD_GLYPH_SIZE,
  QUICK_SITE_WIDE_COLUMN_GAP, QUICK_SITE_WIDE_ITEM_GAP, QUICK_SITE_WIDE_MAX_WIDTH,
  QUICK_SITE_WIDE_ROW_EXTRA, QUICK_SITE_WIDE_ROW_GAP, QUICK_SITE_WIDE_TILE_FONT_SIZE,
  QUICK_SITE_WIDE_TILE_RADIUS, QUICK_SITE_WIDE_TILE_SIZE, QUICK_SITE_WIDE_TITLE_FONT_SIZE,
  QUICK_SITE_WIGGLE_ANGLE, QUICK_SITE_WIGGLE_DURATION,
  QUICK_SITE_WIGGLE_EXIT_DURATION
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
  @Prop quickSiteLimit: number = 6;
  @Prop backgroundEnabled: boolean = true;
  @Prop isWide: boolean = false;
  @State private isEditing: boolean = false;
  @State private wiggle: number = 0;
  @State private dragBadge: string = '';
  @State private dragColorIndex: number = 0;
  onAddSite: () => void = (): void => {};
  onOpenSite: (url: string) => void = (_url: string): void => {};
  onRemoveSite: (url: string) => void = (_url: string): void => {};
  onMoveSite: (from: number, to: number) => void = (_from: number, _to: number): void => {};

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
      .columnsTemplate('1fr 1fr 1fr 1fr')
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
        Text(site.badge)
          .width(this.tileSize()).height(this.tileSize())
          .borderRadius(this.isWide ? QUICK_SITE_WIDE_TILE_RADIUS : QUICK_SITE_PHONE_TILE_RADIUS)
          .backgroundColor(tileColor(TILE_BACKGROUNDS, site.colorIndex))
          .fontColor(tileColor(TILE_FOREGROUNDS, site.colorIndex))
          .fontSize(this.isWide ? QUICK_SITE_WIDE_TILE_FONT_SIZE : QUICK_SITE_PHONE_TILE_FONT_SIZE)
          .fontWeight(FontWeight.Bold).textAlign(TextAlign.Center)

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
    .rotate({ angle: this.isEditing ? this.wiggle * (index % 2 === 0 ? 1 : -1) : 0 })
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

  private visibleSites(): QuickSite[] {
    return this.quickSites.slice(0, this.quickSiteLimit);
  }

  private tileSize(): number {
    return this.isWide ? QUICK_SITE_WIDE_TILE_SIZE : QUICK_SITE_PHONE_TILE_SIZE;
  }

  private gridHeight(): number {
    const rows: number = Math.ceil((this.visibleSites().length + 1) / QUICK_SITE_COLUMNS);
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
    this.wiggle = -QUICK_SITE_WIGGLE_ANGLE;
    this.getUIContext().animateTo({
      duration: QUICK_SITE_WIGGLE_DURATION,
      curve: Curve.EaseInOut,
      iterations: -1,
      playMode: PlayMode.Alternate
    }, (): void => {
      this.wiggle = QUICK_SITE_WIGGLE_ANGLE;
    });
  }

  private leaveEditing(): void {
    this.isEditing = false;
    this.getUIContext().animateTo({ duration: QUICK_SITE_WIGGLE_EXIT_DURATION, curve: Curve.EaseOut }, (): void => {
      this.wiggle = 0;
    });
  }

  private primaryColor(): ResourceColor {
    return this.backgroundEnabled ? $r('app.color.home_text_primary') : $r('app.color.text_primary');
  }
}
