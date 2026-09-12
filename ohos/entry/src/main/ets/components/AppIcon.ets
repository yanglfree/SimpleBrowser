/**
 * The design's icon set, authored as SVG paths on a 24x24 grid so every glyph
 * keeps the source proportions and stroke weight at any render size.
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
  Tabs = 19,
  Sliders = 20,
  Menu = 21,
  Home = 22,
  Incognito = 23,
  Settings = 24,
  Download = 25,
  Trash = 26,
  Mic = 27,
  Star = 28,
  WifiOff = 29,
  CloudOff = 30,
  Globe = 31,
  Moon = 32
}

const COMMANDS: string[] = [
  'M12 3l7 2.6v5.2c0 4.6-2.9 7.6-7 9.2-4.1-1.6-7-4.6-7-9.2V5.6z',
  'M12 3l7 2.6v5.2c0 4.6-2.9 7.6-7 9.2-4.1-1.6-7-4.6-7-9.2V5.6zM9.2 11.8l2 2 3.6-3.8',
  'M15.25 4.75L8 12l7.25 7.25',
  'M8.75 4.75L16 12l-7.25 7.25',
  'M4.75 15.25L12 8l7.25 7.25',
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
  'M6 6l12 12M18 6L6 18',
  'M16 15.5L8.5 8M15.5 8h-7v7',
  'M5 12.5l4.5 4.5L19 7.5',
  'M10.5 8.5h7a2 2 0 0 1 2 2v7a2 2 0 0 1-2 2h-7a2 2 0 0 1-2-2v-7a2 2 0 0 1 2-2z'
    + 'M6.5 15.5a2 2 0 0 1-2-2v-7a2 2 0 0 1 2-2h7a2 2 0 0 1 2 2',
  'M4 7h9M17 7h3M4 17h3M11 17h9M13 4v6M7 14v6',
  'M4.5 7h15M4.5 12h15M4.5 17h15',
  'M4 11.75L12 4.5l8 7.25M6.5 10.3V19.5h11V10.3M10 19.5v-5.5h4v5.5',
  'M3 15l2-7h14l2 7M5 15h5l2-2 2 2h5M8 11h2M14 11h2',
  'M12 8.5a3.5 3.5 0 1 0 0 7 3.5 3.5 0 1 0 0-7' +
    'M19 12a7 7 0 0 0-.1-1l2-1.5-2-3.4-2.3 1A8 8 0 0 0 15 6l-.3-2.5h-4' +
    'L10.4 6a8 8 0 0 0-1.6.9l-2.3-1-2 3.5 2 1.5a7 7 0 0 0 0 2l-2 1.5 2 3.5 2.3-1' +
    'a8 8 0 0 0 1.6.9l.3 2.5h4l.3-2.5a8 8 0 0 0 1.6-.9l2.3 1 2-3.5-2-1.5a7 7 0 0 0 .1-1z',
  'M12 3v12M7 10l5 5 5-5M5 20h14',
  'M5 7h14M9 7V4h6v3M8 10v7M12 10v7M16 10v7M7 7l1 14h8l1-14',
  'M12 3a4 4 0 0 0-4 4v5a4 4 0 0 0 8 0V7a4 4 0 0 0-4-4M5 11v1a7 7 0 0 0 14 0v-1M12 19v3M9 22h6',
  'M12 4l2.18 5.01 5.43.52-4.09 3.61 1.18 5.33L12 15.7'
    + 'l-4.7 2.77 1.18-5.33-4.09-3.61 5.44-.52z',
  'M1.42 9a16 16 0 0 1 21.16 0M5 12.55a11 11 0 0 1 14.08 0M8.53 16.11a6 6 0 0 1 6.95 0M12 20h.01M3 3l18 18',
  'M18 10h-1.26A8 8 0 1 0 9 20h9a5 5 0 0 0 0-10zM3 3l18 18',
  'M4 12a8 8 0 1 0 16 0a8 8 0 1 0-16 0'
    + 'M12 4a11.6 11.6 0 0 0 0 16a11.6 11.6 0 0 0 0-16M4 12h16',
  'M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z'
];

/** The grid every command string above is authored on. */
export const GLYPH_GRID: number = 24;

/**
 * `strokeWidth` is expressed in grid units, so the drawn line thickens with the
 * glyph box: the same 1.8 reads as 1.2vp on a 16 glyph and 2.1vp on a 28 one. A
 * bar of controls wants one weight across boxes of different sizes, which means
 * converting the intended vp back into grid units per glyph.
 */
export function iconStrokeUnits(glyphSize: number, strokeVp: number): number {
  if (glyphSize <= 0) {
    return strokeVp;
  }
  return strokeVp * GLYPH_GRID / glyphSize;
}

const SCALED_COMMANDS: Map<string, string> = new Map<string, string>();

/**
 * `Path` measures itself in vp but reads its commands in px, so a 24-grid glyph
 * has to be rescaled to the requested size *and* converted to px — otherwise it
 * draws at 24px, roughly a third of its box on a 3x display.
 */
function glyphCommands(name: IconName, glyphSize: number): string {
  const glyphPx: number = vp2px(glyphSize);
  const key: string = `${name as number}@${glyphPx}`;
  const cached: string | undefined = SCALED_COMMANDS.get(key);
  if (cached !== undefined) {
    return cached;
  }
  const scaled: string = scaleCommands(COMMANDS[name as number], glyphPx / GLYPH_GRID);
  SCALED_COMMANDS.set(key, scaled);
  return scaled;
}

function scaleCommands(commands: string, scale: number): string {
  const tokens: RegExpMatchArray | null = commands.match(/[a-zA-Z]|-?\d*\.?\d+/g);
  if (tokens === null) {
    return commands;
  }
  const parts: string[] = [];
  let verb: string = '';
  let param: number = 0;
  for (const token of tokens) {
    if (isVerb(token)) {
      verb = token;
      param = 0;
      parts.push(token);
      continue;
    }
    if (isArcSetting(verb, param)) {
      parts.push(token);
    } else {
      parts.push(round(Number.parseFloat(token) * scale));
    }
    param += 1;
  }
  return parts.join(' ');
}

/**
 * Three of an arc's seven parameters — the x-axis rotation and the two flags —
 * describe shape rather than length, so scaling them would bend the curve.
 */
function isArcSetting(verb: string, param: number): boolean {
  if (verb !== 'a' && verb !== 'A') {
    return false;
  }
  const slot: number = param % 7;
  return slot === 2 || slot === 3 || slot === 4;
}

function isVerb(token: string): boolean {
  const code: number = token.charCodeAt(0);
  return (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
}

function round(value: number): string {
  return (Math.round(value * 1000) / 1000).toString();
}

@Component
export struct AppIcon {
  @Prop name: IconName = IconName.Shield;
  @Prop glyphSize: number = 20;
  @Prop color: ResourceColor = $r('app.color.text_primary');
  /** Solid glyph — used for the bookmarked state. */
  @Prop filled: boolean = false;
  /** Stroke weight on the 24-grid; scaled with the glyph so weight stays proportional. */
  @Prop strokeWidth: number = 1.5;

  build() {
    Path()
      .commands(glyphCommands(this.name, this.glyphSize))
      .width(this.glyphSize)
      .height(this.glyphSize)
      .fill(this.filled ? this.color : Color.Transparent)
      .stroke(this.color)
      .strokeWidth(this.filled ? 0 : this.strokeWidth * this.glyphSize / GLYPH_GRID)
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
      case IconName.Sliders:
        return $r('app.string.page_settings');
      case IconName.Menu:
        return $r('app.string.tools_menu');
      case IconName.Home:
        return $r('app.string.home');
      case IconName.Incognito:
        return $r('app.string.new_private_tab');
      case IconName.Settings:
        return $r('app.string.settings');
      case IconName.Download:
        return $r('app.string.download_title');
      case IconName.Trash:
        return $r('app.string.clear_browsing_data');
      case IconName.Mic:
        return $r('app.string.voice_search');
      case IconName.Star:
        return this.filled ? $r('app.string.action_bookmark_remove') : $r('app.string.action_bookmark_add');
      case IconName.Globe:
        return $r('app.string.address_placeholder');
      case IconName.WifiOff:
      case IconName.CloudOff:
        return $r('app.string.error_offline_title');
      default:
        return $r('app.string.app_name');
    }
  }
}
