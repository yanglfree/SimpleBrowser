/**
 * The design's icon set, drawn as SVG paths on a 24x24 view port so every glyph
 * keeps the source stroke weight no matter what size it is rendered at.
 */
export enum IconName {
  Shield = 0,
  ShieldCheck = 1,
  ChevronLeft = 2,
  ChevronRight = 3,
  ChevronUp = 4,
  Refresh = 5,
  Share = 6,
  Bookmark = 7,
  Reader = 8,
  Desktop = 9,
  Search = 10,
  Clock = 11,
  Close = 12,
  Plus = 13,
  ArrowLeft = 14,
  LineHeight = 15,
  Stop = 16,
  ArrowUpLeft = 17,
  Check = 18,
  Tabs = 19
}

const COMMANDS: string[] = [
  'M12 3l7 2.6v5.2c0 4.6-2.9 7.6-7 9.2-4.1-1.6-7-4.6-7-9.2V5.6z',
  'M12 3l7 2.6v5.2c0 4.6-2.9 7.6-7 9.2-4.1-1.6-7-4.6-7-9.2V5.6zM9.2 11.8l2 2 3.6-3.8',
  'M15 6l-6 6 6 6',
  'M9 6l6 6-6 6',
  'M6 15l6-6 6 6',
  'M20 12a8 8 0 1 1-2.3-5.6M20 3.5V8h-4.5',
  'M12 14V3M8.5 6L12 3l3.5 3M7 10H5v11h14V10h-2',
  'M7 4h10v16l-5-3.8L7 20z',
  'M4 6h16M4 11h16M4 16h9',
  'M5 5h14a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2zM9 21h6M12 17v4',
  'M4 11a7 7 0 1 0 14 0a7 7 0 1 0-14 0M16.5 16.5L21 21',
  'M4 12a8 8 0 1 0 16 0a8 8 0 1 0-16 0M12 7.5V12l3 1.8',
  'M6 6l12 12M18 6L6 18',
  'M12 5v14M5 12h14',
  'M19 12H5M11 6l-6 6 6 6',
  'M8 7h12M8 12h12M8 17h12M4 6.5v11M4 6.5l-1.4 1.6M4 6.5l1.4 1.6M4 17.5l-1.4-1.6M4 17.5l1.4-1.6',
  'M7.5 7.5h9v9h-9z',
  'M16 15.5L8.5 8M15.5 8h-7v7',
  'M5 12.5l4.5 4.5L19 7.5',
  'M5 5h10v10H5zM9 9h10v10H9z'
];

@Component
export struct AppIcon {
  @Prop name: IconName = IconName.Shield;
  @Prop glyphSize: number = 20;
  @Prop color: ResourceColor = $r('app.color.text_primary');
  /** Solid glyph — used for the bookmarked state. */
  @Prop filled: boolean = false;
  @Prop strokeWidth: number = 1.5;

  build() {
    Shape() {
      Path()
        .commands(COMMANDS[this.name as number])
        .width(this.glyphSize)
        .height(this.glyphSize)
    }
    .viewPort({ x: 0, y: 0, width: 24, height: 24 })
    .width(this.glyphSize)
    .height(this.glyphSize)
    .fill(this.filled ? this.color : Color.Transparent)
    .stroke(this.color)
    .strokeWidth(this.filled ? 0 : this.strokeWidth)
    .strokeLineCap(LineCapStyle.Round)
    .strokeLineJoin(LineJoinStyle.Round)
    .accessibilityText(this.accessibilityLabel())
  }

  private accessibilityLabel(): Resource {
    switch (this.name) {
      case IconName.Shield:
      case IconName.ShieldCheck:
        return $r('app.string.security_secure');
      case IconName.ChevronLeft:
      case IconName.ArrowLeft:
        return $r('app.string.action_back');
      case IconName.ChevronRight:
        return $r('app.string.action_forward');
      case IconName.ChevronUp:
        return $r('app.string.action_share');
      case IconName.Refresh:
        return $r('app.string.action_reload');
      case IconName.Share:
        return $r('app.string.action_share');
      case IconName.Bookmark:
        return $r('app.string.action_bookmark_add');
      case IconName.Reader:
        return $r('app.string.action_reader');
      case IconName.Desktop:
        return $r('app.string.action_desktop');
      case IconName.Search:
        return $r('app.string.address_placeholder');
      case IconName.Clock:
        return $r('app.string.history_title');
      case IconName.Close:
        return $r('app.string.cancel');
      case IconName.Plus:
        return $r('app.string.new_tab');
      case IconName.LineHeight:
        return $r('app.string.reader_line_height');
      case IconName.Stop:
        return $r('app.string.action_stop');
      case IconName.ArrowUpLeft:
        return $r('app.string.share_panel_copy');
      case IconName.Check:
        return $r('app.string.done');
      case IconName.Tabs:
        return $r('app.string.tabs_count_suffix');
      default:
        return $r('app.string.app_name');
    }
  }
}
