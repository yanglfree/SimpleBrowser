import { Suggestion, SuggestionKind } from '../models/BrowserModels';
import { looksLikeUrl } from '../utils/UrlUtils';
import {
  applyOmniboxShortcut,
  OmniboxEditResult,
  OmniboxShortcut,
  omniboxShortcuts
} from '../utils/OmniboxInput';
import { AppIcon, IconName } from './AppIcon';

const INPUT_ID: string = 'address-input';

function suggestionIcon(kind: SuggestionKind): IconName {
  if (kind === SuggestionKind.History) {
    return IconName.Clock;
  }
  if (kind === SuggestionKind.Bookmark) {
    return IconName.Bookmark;
  }
  return IconName.Search;
}

/**
 * 1d — the capsule floated up into a text field. The list is rendered bottom-up
 * so the best match sits against the input, where the thumb already is.
 */
@Component
export struct AddressSheet {
  @Prop topInset: number = 0;
  @Prop keyboardInset: number = 0;
  @Prop suggestions: Suggestion[] = [];
  @Prop currentHost: string = '';
  initialText: string = '';
  onQueryChange: (query: string) => void = (_query: string): void => {};
  onSubmit: (query: string) => void = (_query: string): void => {};
  onPick: (url: string) => void = (_url: string): void => {};
  onDismiss: () => void = (): void => {};
  @State private text: string = '';
  @State private selectionStart: number = 0;
  @State private selectionEnd: number = 0;
  private inputController: TextInputController = new TextInputController();

  aboutToAppear(): void {
    this.text = this.initialText;
  }

  build() {
    Column() {
      Column()
        .layoutWeight(1)
        .width('100%')
        .onClick(() => this.onDismiss())

      this.Panel()
      this.Shortcuts()
    }
    .width('100%')
    .height('100%')
    .padding({ top: Math.max(0, this.topInset), bottom: Math.max(0, this.keyboardInset) })
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  private Panel() {
    Column() {
      if (this.suggestions.length > 0) {
        Scroll() {
          Column() {
            // Reversed: most relevant last, i.e. directly above the input.
            ForEach(this.suggestions.slice(0).reverse(), (item: Suggestion, index: number) => {
              this.SuggestionRow(item, index === this.suggestions.length - 1)
            }, (item: Suggestion) => item.id)
          }
          .width('100%')
        }
        .constraintSize({ maxHeight: '50%' })
        .scrollBar(BarState.Off)
      }

      Row({ space: 10 }) {
        Row({ space: 10 }) {
          AppIcon({ name: IconName.Search, glyphSize: 17, color: $r('app.color.text_secondary') })
          TextInput({
            text: this.text,
            placeholder: $r('app.string.address_placeholder'),
            controller: this.inputController
          })
            .id(INPUT_ID)
            .defaultFocus(true)
            .onAppear(() => {
              focusControl.requestFocus(INPUT_ID);
              setTimeout((): void => {
                this.selectionStart = 0;
                this.selectionEnd = this.text.length;
                this.inputController.setTextSelection(0, this.text.length);
              }, 0);
            })
            .layoutWeight(1)
            .height(48)
            .padding(0)
            .borderRadius(0)
            .fontSize(16)
            .fontColor($r('app.color.text_primary'))
            .placeholderColor($r('app.color.text_secondary'))
            .backgroundColor(Color.Transparent)
            .caretColor($r('app.color.accent'))
            .enterKeyType(looksLikeUrl(this.text) ? EnterKeyType.Go : EnterKeyType.Search)
            .onChange((value: string) => {
              this.text = value;
              this.onQueryChange(value);
            })
            .onTextSelectionChange((start: number, end: number): void => {
              this.selectionStart = start;
              this.selectionEnd = end;
            })
            .onSubmit(() => this.onSubmit(this.text))

          if (this.text.length > 0) {
            Column() {
              AppIcon({ name: IconName.Close, glyphSize: 16, color: $r('app.color.text_secondary') })
            }
              .width(48)
              .height(48)
              .justifyContent(FlexAlign.Center)
              .focusable(true)
              .accessibilityText($r('app.string.address_clear_input'))
              .onClick(() => {
                this.text = '';
                this.selectionStart = 0;
                this.selectionEnd = 0;
                this.inputController.caretPosition(0);
                this.onQueryChange('');
              })
          }
        }
        .layoutWeight(1)
        .height(48)
        .padding({ left: 16, right: 16 })
        .borderRadius(16)
        .backgroundColor($r('app.color.surface_subtle'))

        Row() {
          Text($r('app.string.cancel'))
            .fontSize(15)
            .fontColor($r('app.color.text_secondary'))
        }
          .height(48)
          .justifyContent(FlexAlign.Center)
          .focusable(true)
          .accessibilityText($r('app.string.cancel'))
          .onClick(() => this.onDismiss())
      }
      .width('100%')
      .padding({ top: 10, bottom: 12 })
    }
    .width('100%')
    .padding({ top: 6, left: 20, right: 20 })
    .backgroundColor($r('app.color.surface_panel'))
    .borderRadius({ topLeft: 20, topRight: 20 })
    .shadow({ radius: 12, color: $r('app.color.shadow_soft'), offsetX: 0, offsetY: -2 })
  }

  @Builder
  private SuggestionRow(item: Suggestion, isLast: boolean) {
    Row({ space: 14 }) {
      AppIcon({
        name: suggestionIcon(item.kind),
        glyphSize: 17,
        color: $r('app.color.text_secondary')
      })
      Text() {
        Span(item.title)
        if (item.subtitle.length > 0) {
          Span(`  ${item.subtitle}`)
            .fontSize(12.5)
            .fontColor($r('app.color.text_secondary'))
        }
      }
      .fontSize(15)
      .fontColor($r('app.color.text_primary'))
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .layoutWeight(1)

      if (isLast) {
        Column() {
          AppIcon({ name: IconName.ArrowUpLeft, glyphSize: 16, color: $r('app.color.text_secondary') })
        }
          .width(48)
          .height(48)
          .justifyContent(FlexAlign.Center)
          .focusable(true)
          .accessibilityText(item.url)
          .onClick(() => {
            this.text = item.url;
            this.selectionStart = item.url.length;
            this.selectionEnd = item.url.length;
            this.inputController.caretPosition(item.url.length);
            this.onQueryChange(item.url);
          })
      }
    }
    .width('100%')
    .height(52)
    .border({ width: { bottom: 1 }, color: $r('app.color.border') })
    .focusable(true)
    .accessibilityText(item.title)
    .onClick(() => this.onPick(item.url))
  }

  /** Domain shortcuts, sitting where the keyboard's suggestion strip would be. */
  @Builder
  private Shortcuts() {
    Row({ space: 6 }) {
      ForEach(omniboxShortcuts(this.currentHost), (shortcut: OmniboxShortcut) => {
        Text(shortcut.label)
          .layoutWeight(1)
          .height(48)
          .borderRadius(8)
          .backgroundColor($r('app.color.surface_panel'))
          .border({ width: 1, color: $r('app.color.border') })
          .fontSize(13)
          .fontColor($r('app.color.text_primary'))
          .textAlign(TextAlign.Center)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .focusable(true)
          .accessibilityText(shortcut.label)
          .onClick(() => {
            const result: OmniboxEditResult = applyOmniboxShortcut(
              this.text,
              this.selectionStart,
              this.selectionEnd,
              shortcut
            );
            this.text = result.text;
            this.selectionStart = result.selection.start;
            this.selectionEnd = result.selection.end;
            this.inputController.setTextSelection(result.selection.start, result.selection.end);
            this.onQueryChange(this.text);
          })
      }, (shortcut: OmniboxShortcut, index: number) => `${index}-${shortcut.label}`)
    }
    .width('100%')
    .padding({ left: 8, right: 8, top: 8, bottom: 8 })
    .backgroundColor($r('app.color.page_background'))
  }

}
