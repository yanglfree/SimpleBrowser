import { Suggestion, SuggestionKind } from '../models/BrowserModels';
import { looksLikeUrl } from '../utils/UrlUtils';
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
  @Prop suggestions: Suggestion[] = [];
  @Prop currentHost: string = '';
  initialText: string = '';
  onQueryChange: (query: string) => void = (_query: string): void => {};
  onSubmit: (query: string) => void = (_query: string): void => {};
  onPick: (url: string) => void = (_url: string): void => {};
  onDismiss: () => void = (): void => {};
  @State private text: string = '';

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
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  private Panel() {
    Column() {
      // Reversed: most relevant last, i.e. directly above the input.
      ForEach(this.suggestions.slice(0).reverse(), (item: Suggestion, index: number) => {
        this.SuggestionRow(item, index === this.suggestions.length - 1)
      }, (item: Suggestion) => item.id)

      Row({ space: 10 }) {
        Row({ space: 10 }) {
          AppIcon({ name: IconName.Search, glyphSize: 17, color: $r('app.color.text_secondary') })
          TextInput({ text: this.text, placeholder: $r('app.string.address_placeholder') })
            .id(INPUT_ID)
            .defaultFocus(true)
            .onAppear(() => focusControl.requestFocus(INPUT_ID))
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
            .onPaste((content: string, _event: PasteEvent) => {
              this.text = content;
              this.onSubmit(content);
            })
            .onSubmit(() => this.onSubmit(this.text))

          if (this.text.length > 0) {
            AppIcon({ name: IconName.Close, glyphSize: 16, color: $r('app.color.text_secondary') })
              .onClick(() => {
                this.text = '';
                this.onQueryChange('');
              })
          }
        }
        .layoutWeight(1)
        .height(48)
        .padding({ left: 16, right: 16 })
        .borderRadius(16)
        .backgroundColor($r('app.color.surface_subtle'))

        Text($r('app.string.cancel'))
          .fontSize(15)
          .fontColor($r('app.color.text_secondary'))
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
        AppIcon({ name: IconName.ArrowUpLeft, glyphSize: 16, color: $r('app.color.text_secondary') })
          .onClick(() => {
            this.text = item.url;
            this.onQueryChange(item.url);
          })
      }
    }
    .width('100%')
    .height(52)
    .border({ width: { bottom: 1 }, color: $r('app.color.border') })
    .onClick(() => this.onPick(item.url))
  }

  /** Domain shortcuts, sitting where the keyboard's suggestion strip would be. */
  @Builder
  private Shortcuts() {
    Row({ space: 6 }) {
      ForEach(this.shortcutTokens(), (token: string) => {
        Text(token)
          .layoutWeight(1)
          .height(32)
          .borderRadius(8)
          .backgroundColor($r('app.color.surface_panel'))
          .border({ width: 1, color: $r('app.color.border') })
          .fontSize(13)
          .fontColor($r('app.color.text_primary'))
          .textAlign(TextAlign.Center)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .onClick(() => {
            this.text = `${this.text}${token}`;
            this.onQueryChange(this.text);
          })
      }, (token: string, index: number) => `${index}-${token}`)
    }
    .width('100%')
    .padding({ left: 8, right: 8, top: 8, bottom: 8 })
    .backgroundColor($r('app.color.page_background'))
  }

  private shortcutTokens(): string[] {
    const tokens: string[] = ['.com', '.cn', 'www.', '/'];
    return this.currentHost.length > 0 ? [this.currentHost].concat(tokens) : tokens;
  }
}
