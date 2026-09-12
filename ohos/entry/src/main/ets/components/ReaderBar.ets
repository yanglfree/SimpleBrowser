import { READER_LINE_HEIGHTS } from '../constants/AppConstants';
import { ReaderPaper, ReaderTheme, getReaderTheme } from '../models/BrowserModels';
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
  @Prop topInset: number = 0;
  @Prop paper: ReaderPaper = ReaderPaper.Sepia;
  @Prop canShrink: boolean = true;
  @Prop canGrow: boolean = true;
  @Prop isSaving: boolean = false;
  onSave: () => void = (): void => {};
  onShrink: () => void = (): void => {};
  onGrow: () => void = (): void => {};
  onCycleLineHeight: () => void = (): void => {};
  onPickPaper: (paper: ReaderPaper) => void = (_paper: ReaderPaper): void => {};
  onDone: () => void = (): void => {};

  build() {
    Column() {
      Row() {
        Row({ space: 2 }) {
          Text('A−')
            .width(32)
            .height(44)
            .textAlign(TextAlign.Center)
            .fontSize(13)
            .fontColor(this.theme().textSecondary)
            .opacity(this.canShrink ? 1 : 0.35)
            .onClick(() => {
              if (this.canShrink) {
                this.onShrink();
              }
            })
          Text('A+')
            .width(32)
            .height(44)
            .textAlign(TextAlign.Center)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.theme().textPrimary)
            .opacity(this.canGrow ? 1 : 0.35)
            .onClick(() => {
              if (this.canGrow) {
                this.onGrow();
              }
            })
        }
        .alignItems(VerticalAlign.Center)

        Row({ space: 4 }) {
          AppIcon({ name: IconName.LineHeight, glyphSize: 15, color: this.theme().textSecondary })
          Text($r('app.string.reader_line_height'))
            .fontSize(12)
            .fontColor(this.theme().textSecondary)
        }
        .height(44)
        .padding({ left: 4, right: 4 })
        .accessibilityText($r('app.string.reader_line_height'))
        .onClick(() => this.onCycleLineHeight())

        Row({ space: 6 }) {
          ForEach(SWATCHES, (swatch: PaperSwatch) => {
            Row() {
              Circle()
                .width(18)
                .height(18)
                .fill(swatch.color)
                .stroke(this.paper === swatch.paper
                  ? $r('app.color.accent')
                  : this.theme().border)
                .strokeWidth(this.paper === swatch.paper ? 1.5 : 1)
            }
            .width(28)
            .height(44)
            .justifyContent(FlexAlign.Center)
            .accessibilityText(swatch.label)
            .onClick(() => this.onPickPaper(swatch.paper))
          }, (swatch: PaperSwatch) => `${swatch.paper}`)
        }

        Text($r('app.string.article_save'))
          .fontSize(12)
          .height(44)
          .fontColor(this.theme().textPrimary)
          .enabled(!this.isSaving)
          .onClick(() => this.onSave())

        Text($r('app.string.done'))
          .height(44)
          .padding({ left: 6, right: 2 })
          .textAlign(TextAlign.Center)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.theme().textPrimary)
          .onClick(() => this.onDone())
      }
      .width('100%')
      .height(44)
      .padding({ left: 16, right: 16 })
      .justifyContent(FlexAlign.SpaceBetween)
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({ top: Math.max(0, this.topInset) })
    .backgroundColor(this.theme().background)
    .border({ width: { bottom: 1 }, color: this.theme().border })
  }

  private theme(): ReaderTheme {
    return getReaderTheme(this.paper);
  }
}

/** Cycles 1.7 → 2.05 → 2.4 → 1.7, matching the three steps in the design. */
export function nextLineHeight(current: number): number {
  const index: number = READER_LINE_HEIGHTS.indexOf(current);
  const next: number = index < 0 ? 1 : (index + 1) % READER_LINE_HEIGHTS.length;
  return READER_LINE_HEIGHTS[next];
}
