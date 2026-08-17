import { HistoryEntry, SavedItem } from '../models/BrowserModels';
import { AppIcon, IconName } from './AppIcon';
import { QuickSiteSourceList } from './QuickSiteSourceList';
import {
  QUICK_SITE_EDITOR_ACTION_FONT_SIZE, QUICK_SITE_EDITOR_ACTION_GAP, QUICK_SITE_EDITOR_ACTION_RADIUS,
  QUICK_SITE_EDITOR_BOTTOM_PADDING, QUICK_SITE_EDITOR_CLOSE_GLYPH_SIZE,
  QUICK_SITE_EDITOR_COMPACT_HEIGHT, QUICK_SITE_EDITOR_COMPACT_HORIZONTAL_PADDING,
  QUICK_SITE_EDITOR_COMPACT_RADIUS, QUICK_SITE_EDITOR_COMPACT_TITLE_SIZE, QUICK_SITE_EDITOR_FIELD_HEIGHT,
  QUICK_SITE_EDITOR_FORM_GAP, QUICK_SITE_EDITOR_HEADER_GAP, QUICK_SITE_EDITOR_INPUT_FONT_SIZE,
  QUICK_SITE_EDITOR_INPUT_HORIZONTAL_PADDING, QUICK_SITE_EDITOR_INPUT_RADIUS,
  QUICK_SITE_EDITOR_LABEL_FONT_SIZE, QUICK_SITE_EDITOR_LABEL_SECTION_GAP,
  QUICK_SITE_EDITOR_SECTION_GAP, QUICK_SITE_EDITOR_SELECTED_TAB_RADIUS,
  QUICK_SITE_EDITOR_SHADOW_OFFSET_Y, QUICK_SITE_EDITOR_SHADOW_RADIUS, QUICK_SITE_EDITOR_TAB_FONT_SIZE,
  QUICK_SITE_EDITOR_TAB_HEIGHT, QUICK_SITE_EDITOR_TAB_PADDING, QUICK_SITE_EDITOR_TAB_RADIUS,
  QUICK_SITE_EDITOR_TOP_PADDING, QUICK_SITE_EDITOR_WIDE_HEIGHT,
  QUICK_SITE_EDITOR_WIDE_HORIZONTAL_PADDING, QUICK_SITE_EDITOR_WIDE_RADIUS,
  QUICK_SITE_EDITOR_WIDE_TITLE_SIZE, QUICK_SITE_EDITOR_WIDE_WIDTH,
  QUICK_SITE_TOUCH_TARGET
} from './QuickSiteTokens';

enum QuickSiteSource {
  Custom = 0,
  Favorites = 1,
  History = 2
}

@Component
export struct QuickSiteEditor {
  @Prop savedItems: SavedItem[] = [];
  @Prop history: HistoryEntry[] = [];
  @Prop isWide: boolean = false;
  /** Soft keyboard height in vp while shown; the compact sheet floats above it. */
  @Prop keyboardInset: number = 0;
  @State private source: QuickSiteSource = QuickSiteSource.Custom;
  @State private name: string = '';
  @State private url: string = '';
  onSave: (title: string, url: string) => void = (_title: string, _url: string): void => {};
  onDismiss: () => void = (): void => {};

  build() {
    Stack({ alignContent: this.isWide ? Alignment.Center : Alignment.Bottom }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.isWide ? Color.Transparent : $r('app.color.scrim'))
        .opacity(this.isWide ? 1 : 0.42)
        .onClick(() => this.onDismiss())

      this.Panel()
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private Panel() {
    Column({ space: QUICK_SITE_EDITOR_SECTION_GAP }) {
      Row({ space: QUICK_SITE_EDITOR_HEADER_GAP }) {
        Text($r('app.string.quick_site_add_title'))
          .fontSize(this.isWide ? QUICK_SITE_EDITOR_WIDE_TITLE_SIZE : QUICK_SITE_EDITOR_COMPACT_TITLE_SIZE)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Column() {
          AppIcon({
            name: IconName.Close,
            glyphSize: QUICK_SITE_EDITOR_CLOSE_GLYPH_SIZE,
            color: $r('app.color.text_secondary')
          })
        }
          .id('quick-site-editor-close')
          .width(QUICK_SITE_TOUCH_TARGET)
          .height(QUICK_SITE_TOUCH_TARGET)
          .justifyContent(FlexAlign.Center)
          .onClick(() => this.onDismiss())
      }
      .width('100%')

      Row() {
        this.SourceTab($r('app.string.quick_site_source_custom'), QuickSiteSource.Custom)
        this.SourceTab($r('app.string.quick_site_source_favorites'), QuickSiteSource.Favorites)
        this.SourceTab($r('app.string.quick_site_source_history'), QuickSiteSource.History)
      }
      .width('100%')
      .height(QUICK_SITE_EDITOR_TAB_HEIGHT)
      .padding(QUICK_SITE_EDITOR_TAB_PADDING)
      .borderRadius(QUICK_SITE_EDITOR_TAB_RADIUS)
      .backgroundColor($r('app.color.surface_subtle'))

      if (this.source === QuickSiteSource.Custom) {
        this.CustomForm()
      } else {
        QuickSiteSourceList({
          savedItems: this.savedItems,
          history: this.history,
          favorites: this.source === QuickSiteSource.Favorites,
          onSelect: (title: string, url: string): void => this.onSave(title, url)
        })
      }

      Row({ space: QUICK_SITE_EDITOR_ACTION_GAP }) {
        this.ActionButton($r('app.string.cancel'), false, (): void => this.onDismiss())
        this.ActionButton($r('app.string.save'), true, (): void => this.saveCustom())
      }
      .width('100%')
      .visibility(this.source === QuickSiteSource.Custom ? Visibility.Visible : Visibility.None)
    }
    .width(this.isWide ? QUICK_SITE_EDITOR_WIDE_WIDTH : '100%')
    .height(this.isWide ? QUICK_SITE_EDITOR_WIDE_HEIGHT : QUICK_SITE_EDITOR_COMPACT_HEIGHT)
    .padding({
      top: QUICK_SITE_EDITOR_TOP_PADDING,
      right: this.isWide
        ? QUICK_SITE_EDITOR_WIDE_HORIZONTAL_PADDING : QUICK_SITE_EDITOR_COMPACT_HORIZONTAL_PADDING,
      bottom: QUICK_SITE_EDITOR_BOTTOM_PADDING,
      left: this.isWide
        ? QUICK_SITE_EDITOR_WIDE_HORIZONTAL_PADDING : QUICK_SITE_EDITOR_COMPACT_HORIZONTAL_PADDING
    })
    .borderRadius(this.isWide
      ? QUICK_SITE_EDITOR_WIDE_RADIUS
      : { topLeft: QUICK_SITE_EDITOR_COMPACT_RADIUS, topRight: QUICK_SITE_EDITOR_COMPACT_RADIUS })
    .backgroundColor($r('app.color.surface_panel'))
    .border({ width: this.isWide ? 1 : 0, color: $r('app.color.border') })
    .margin({ bottom: this.isWide ? 0 : this.keyboardInset })
    .animation({ duration: 180, curve: Curve.EaseOut })
    .shadow(this.isWide ? {
      radius: QUICK_SITE_EDITOR_SHADOW_RADIUS,
      color: $r('app.color.shadow_soft'),
      offsetY: QUICK_SITE_EDITOR_SHADOW_OFFSET_Y
    } : undefined)
    .onClick((): void => {})
  }

  @Builder
  private SourceTab(label: Resource, source: QuickSiteSource) {
    Row() {
      Text(label)
        .fontSize(QUICK_SITE_EDITOR_TAB_FONT_SIZE)
        .fontWeight(this.source === source ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(this.source === source
          ? $r('app.color.text_primary')
          : $r('app.color.text_secondary'))
    }
    .height('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .borderRadius(QUICK_SITE_EDITOR_SELECTED_TAB_RADIUS)
    .backgroundColor(this.source === source ? $r('app.color.surface_panel') : Color.Transparent)
    .onClick(() => {
      this.source = source;
    })
  }

  @Builder
  private CustomForm() {
    Column({ space: QUICK_SITE_EDITOR_FORM_GAP }) {
      Text($r('app.string.quick_site_name'))
        .width('100%')
        .fontSize(QUICK_SITE_EDITOR_LABEL_FONT_SIZE)
        .fontColor($r('app.color.text_secondary'))
      TextInput({ text: this.name, placeholder: $r('app.string.quick_site_name_placeholder') })
        .id('quick-site-name-input')
        .width('100%')
        .height(QUICK_SITE_EDITOR_FIELD_HEIGHT)
        .padding({ left: QUICK_SITE_EDITOR_INPUT_HORIZONTAL_PADDING, right: QUICK_SITE_EDITOR_INPUT_HORIZONTAL_PADDING })
        .fontSize(QUICK_SITE_EDITOR_INPUT_FONT_SIZE)
        .fontColor($r('app.color.text_primary'))
        .placeholderColor($r('app.color.text_secondary'))
        .backgroundColor($r('app.color.surface_subtle'))
        .borderRadius(QUICK_SITE_EDITOR_INPUT_RADIUS)
        .onChange((value: string): void => {
          this.name = value;
        })

      Text($r('app.string.quick_site_url'))
        .width('100%')
        .fontSize(QUICK_SITE_EDITOR_LABEL_FONT_SIZE)
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: QUICK_SITE_EDITOR_LABEL_SECTION_GAP })
      TextInput({ text: this.url, placeholder: $r('app.string.quick_site_url_placeholder') })
        .id('quick-site-url-input')
        .width('100%')
        .height(QUICK_SITE_EDITOR_FIELD_HEIGHT)
        .padding({ left: QUICK_SITE_EDITOR_INPUT_HORIZONTAL_PADDING, right: QUICK_SITE_EDITOR_INPUT_HORIZONTAL_PADDING })
        .fontSize(QUICK_SITE_EDITOR_INPUT_FONT_SIZE)
        .fontColor($r('app.color.text_primary'))
        .placeholderColor($r('app.color.text_secondary'))
        .backgroundColor($r('app.color.surface_subtle'))
        .borderRadius(QUICK_SITE_EDITOR_INPUT_RADIUS)
        .onChange((value: string): void => {
          this.url = value;
        })

      Blank()
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  private ActionButton(label: Resource, primary: boolean, action: () => void) {
    Row() {
      Text(label)
        .fontSize(QUICK_SITE_EDITOR_ACTION_FONT_SIZE)
        .fontWeight(FontWeight.Medium)
        .fontColor(primary ? $r('app.color.content_background') : $r('app.color.text_primary'))
    }
    .height(QUICK_SITE_EDITOR_FIELD_HEIGHT)
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .borderRadius(QUICK_SITE_EDITOR_ACTION_RADIUS)
    .backgroundColor(primary ? $r('app.color.accent') : $r('app.color.surface_subtle'))
    .opacity(primary && !this.canSaveCustom() ? 0.45 : 1)
    .onClick(() => {
      if (!primary || this.canSaveCustom()) {
        action();
      }
    })
  }

  private canSaveCustom(): boolean {
    const value: string = this.url.trim();
    return value.includes('://') || (value.includes('.') && !value.includes(' '));
  }

  private saveCustom(): void {
    if (this.canSaveCustom()) {
      this.onSave(this.name.trim(), this.url.trim());
    }
  }
}
