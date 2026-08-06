import { READER_LINE_HEIGHTS } from '../constants/AppConstants';
import { ReaderPaper } from '../models/BrowserModels';
import { AppIcon, IconName } from './AppIcon';

interface PaperSwatch {
  paper: ReaderPaper;
  color: Resource;
  label: Resource;
}

const SWATCHES: PaperSwatch[] = [
  { paper: ReaderPaper.White, color: $r('app.color.reader_paper_white'), label: $r('app.string.reader_paper_white') },
  { paper: ReaderPaper.Sepia, color: $r('app.color.reader_paper_sepia'), label: $r('app.string.reader_paper_sepia') },
  { paper: ReaderPaper.Night, color: $r('app.color.reader_paper_night'), label: $r('app.string.reader_paper_night') }
];

/**
 * 1g — a 42vp strip above the reflowed article. Font size, line height and paper
 * colour, nothing else; the selected paper is the only outlined control.
 */
@Component
export struct ReaderBar {
  @Prop paper: ReaderPaper = ReaderPaper.Sepia;
  @Prop canShrink: boolean = true;
  @Prop canGrow: boolean = true;
  onShrink: () => void = (): void => {};
  onGrow: () => void = (): void => {};
  onCycleLineHeight: () => void = (): void => {};
  onPickPaper: (paper: ReaderPaper) => void = (_paper: ReaderPaper): void => {};
  onDone: () => void = (): void => {};

  build() {
    Row() {
      Row({ space: 18 }) {
        Text('A−')
          .constraintSize({ minWidth: 44, minHeight: 44 })
          .textAlign(TextAlign.Center)
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .opacity(this.canShrink ? 1 : 0.35)
          .onClick(() => {
            if (this.canShrink) {
              this.onShrink();
            }
          })
        Text('A+')
          .constraintSize({ minWidth: 44, minHeight: 44 })
          .textAlign(TextAlign.Center)
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .opacity(this.canGrow ? 1 : 0.35)
          .onClick(() => {
            if (this.canGrow) {
              this.onGrow();
            }
          })
      }
      .alignItems(VerticalAlign.Bottom)

      Row({ space: 6 }) {
        AppIcon({ name: IconName.LineHeight, glyphSize: 15, color: $r('app.color.text_secondary') })
        Text($r('app.string.reader_line_height'))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
      }
      .constraintSize({ minWidth: 44, minHeight: 44 })
      .accessibilityText($r('app.string.reader_line_height'))
      .onClick(() => this.onCycleLineHeight())

      Row({ space: 10 }) {
        ForEach(SWATCHES, (swatch: PaperSwatch) => {
          Row() {
            Circle()
              .width(20)
              .height(20)
              .fill(swatch.color)
              .stroke(this.paper === swatch.paper
                ? $r('app.color.accent')
                : $r('app.color.border'))
              .strokeWidth(this.paper === swatch.paper ? 1.5 : 1)
          }
          .width(44)
          .height(44)
          .justifyContent(FlexAlign.Center)
          .accessibilityText(swatch.label)
          .onClick(() => this.onPickPaper(swatch.paper))
        }, (swatch: PaperSwatch) => `${swatch.paper}`)
      }

      Text($r('app.string.done'))
        .constraintSize({ minWidth: 44, minHeight: 44 })
        .textAlign(TextAlign.Center)
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .onClick(() => this.onDone())
    }
    .width('100%')
    .height(44)
    .padding({ left: 24, right: 24 })
    .justifyContent(FlexAlign.SpaceBetween)
    .backgroundColor($r('app.color.page_background'))
    .border({ width: { bottom: 1 }, color: $r('app.color.border') })
  }
}

/** Cycles 1.7 → 2.05 → 2.4 → 1.7, matching the three steps in the design. */
export function nextLineHeight(current: number): number {
  const index: number = READER_LINE_HEIGHTS.indexOf(current);
  const next: number = index < 0 ? 1 : (index + 1) % READER_LINE_HEIGHTS.length;
  return READER_LINE_HEIGHTS[next];
}
